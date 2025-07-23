#!/bin/bash

# VM Backup and Restore Script for libvirt/KVM
# Usage: vm-backup.sh [backup|restore|list] [options]

set -euo pipefail

# Configuration
BACKUP_DIR="/home/$USER/backup_vms"
LOG_DIR="$BACKUP_DIR/vm-logs"
sudo mkdir -p $BACKUP_DIR $LOG_DIR
LOG_FILE="$LOG_DIR/log_$(date '+%Y-%m-%d_%H:%M:%S').txt"
VM_IMAGES_DIR="/var/lib/libvirt/images"
LIBVIRT_CONFIG_DIR="/etc/libvirt/qemu"
LOCK_DIR="/tmp/vm-backup-locks"
MIN_FREE_SPACE_MB=1024  # Minimum 1GB free space required
VIRSH_TIMEOUT=300       # 5 minutes timeout for virsh commands
SHUTDOWN_TIMEOUT=120    # 2 minutes timeout for VM shutdown

PV_AVAILABLE=false
if command -v pv &>/dev/null; then
    PV_AVAILABLE=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables for cleanup
CURRENT_BACKUP_DIR=""
LOCKED_VMS=()

# Cleanup function for signal handling
cleanup() {
    local exit_code=$?
    
    if [[ -n "$CURRENT_BACKUP_DIR" && -d "$CURRENT_BACKUP_DIR" ]]; then
        warning "Cleaning up partial backup: $CURRENT_BACKUP_DIR"
        rm -rf "$CURRENT_BACKUP_DIR"
    fi
    
    # Release all locks
    for vm in "${LOCKED_VMS[@]}"; do
        release_vm_lock "$vm" 2>/dev/null || true
    done
    
    exit $exit_code
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Notification function
notify() {
    local title="$1"
    local message="$2"
    if command -v notify-send &>/dev/null; then
        notify-send -t 5000 "$title" "$message"
    fi
}

# Logging function
log() {
    local log_data="[$(date '+%Y-%m-%d %H:%M:%S')] - $1"
    # Save the log into a file .
    if ! echo "$log_data" >> "$LOG_FILE"; then
        echo "Failed to write to log file: $LOG_FILE" >&2
    fi
}

error() {
    local msg="$1"
    log "ERROR: $msg"
    notify "VM Backup Error" "$msg"
    echo -e "${RED}[ERROR]${NC} $msg" >&2
}

success() {
    local msg="$1"
    log "SUCCESS: $msg"
    notify "VM Backup Success" "$msg"
    echo -e "${GREEN}[SUCCESS]${NC} $msg"
}

warning() {
    local msg="$1"
    log "WARNING: $msg"
    notify "VM Backup Warning" "$msg"
    echo -e "${YELLOW}[WARNING]${NC} $msg"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Create backup directory if it doesn't exist
ensure_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "Creating backup directory: $BACKUP_DIR"
        sudo mkdir -p "$BACKUP_DIR"
    fi
    
    # Ensure lock directory exists
    sudo mkdir -p "$LOCK_DIR"
}

# Check available disk space
check_disk_space() {
    local target_dir="$1"
    local required_mb="$2"
    
    local available_mb
    available_mb=$(df "$target_dir" | tail -1 | awk '{print int($4/1024)}')
    
    if [[ $available_mb -lt $required_mb ]]; then
        error "Insufficient disk space. Available: ${available_mb}MB, Required: ${required_mb}MB"
        return 1
    fi
    
    log "Disk space check passed. Available: ${available_mb}MB"
    return 0
}

# Estimate VM backup size
estimate_vm_backup_size() {
    local vm_name="$1"
    local total_size_mb=0
    
    # Get disk images and their sizes
    local disk_images
    disk_images=$(virsh domblklist "$vm_name" --details 2>/dev/null | awk '/^file.*disk/ {print $4}' || true)
    
    if [[ -n "$disk_images" ]]; then
        while IFS= read -r disk_path; do
            if [[ -f "$disk_path" ]]; then
                local size_mb
                size_mb=$(du -m "$disk_path" | cut -f1)
                total_size_mb=$((total_size_mb + size_mb))
            fi
        done <<< "$disk_images"
    fi
    
    # Add 20% overhead for compression variations and metadata
    total_size_mb=$((total_size_mb * 120 / 100))
    echo "$total_size_mb"
}

# VM locking mechanism
acquire_vm_lock() {
    local vm_name="$1"
    local lock_file="$LOCK_DIR/${vm_name}.lock"
    local max_wait=30
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if (set -C; echo $$ > "$lock_file") 2>/dev/null; then
            LOCKED_VMS+=("$vm_name")
            log "Acquired lock for VM: $vm_name"
            return 0
        fi
        
        if [[ -f "$lock_file" ]]; then
            local lock_pid
            lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                warning "Removing stale lock for VM: $vm_name"
                rm -f "$lock_file"
                continue
            fi
        fi
        
        log "Waiting for lock on VM: $vm_name (${wait_time}s)"
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    error "Failed to acquire lock for VM: $vm_name after ${max_wait}s"
    return 1
}

release_vm_lock() {
    local vm_name="$1"
    local lock_file="$LOCK_DIR/${vm_name}.lock"
    
    if [[ -f "$lock_file" ]]; then
        rm -f "$lock_file"
        # Remove from locked VMs array
        local new_array=()
        for vm in "${LOCKED_VMS[@]}"; do
            if [[ "$vm" != "$vm_name" ]]; then
                new_array+=("$vm")
            fi
        done
        LOCKED_VMS=("${new_array[@]}")
        log "Released lock for VM: $vm_name"
    fi
}

# Execute virsh command with timeout
virsh_with_timeout() {
    local timeout="$1"
    shift
    
    if timeout "$timeout" virsh "$@"; then
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            error "Virsh command timed out after ${timeout}s: virsh $*"
        else
            error "Virsh command failed with exit code $exit_code: virsh $*"
        fi
        return $exit_code
    fi
}

# Calculate MD5 checksum
calculate_checksum() {
    local file_path="$1"
    md5sum "$file_path" | cut -d' ' -f1
}

# Verify file integrity
verify_file_integrity() {
    local file_path="$1"
    local expected_checksum="$2"
    
    if [[ ! -f "$file_path" ]]; then
        error "File not found: $file_path"
        return 1
    fi
    
    local actual_checksum
    actual_checksum=$(calculate_checksum "$file_path")
    
    if [[ "$actual_checksum" != "$expected_checksum" ]]; then
        error "Checksum mismatch for $file_path"
        error "Expected: $expected_checksum"
        error "Actual: $actual_checksum"
        return 1
    fi
    
    return 0
}

# Validate qemu-img operation
validate_qemu_img_operation() {
    local source_file="$1"
    local dest_file="$2"
    
    # Check if destination file was created
    if [[ ! -f "$dest_file" ]]; then
        error "qemu-img failed to create destination file: $dest_file"
        return 1
    fi
    
    # Check if destination file has reasonable size (at least 1MB)
    local dest_size
    dest_size=$(stat -f%z "$dest_file" 2>/dev/null || stat -c%s "$dest_file" 2>/dev/null || echo "0")
    if [[ $dest_size -lt 1048576 ]]; then
        error "Destination file suspiciously small: $dest_file ($dest_size bytes)"
        return 1
    fi
    
    # Verify the image format
    if ! qemu-img info "$dest_file" >/dev/null 2>&1; then
        error "qemu-img info failed on destination file: $dest_file"
        return 1
    fi
    
    log "qemu-img operation validation passed for: $dest_file"
    return 0
}

# Validate backup completeness
validate_backup() {
    local backup_dir="$1"
    local vm_name="$2"
    
    log "Validating backup integrity for $vm_name..."
    
    # Check required files exist
    local required_files=(
        "$backup_dir/${vm_name}.xml"
        "$backup_dir/backup_manifest.txt"
        "$backup_dir/vm_state.txt"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            error "Required backup file missing: $file"
            return 1
        fi
    done
    
    # Validate XML configuration
    if ! virsh define --validate "$backup_dir/${vm_name}.xml" --dry-run >/dev/null 2>&1; then
        error "Invalid VM XML configuration in backup"
        return 1
    fi
    
    # Validate disk images if they exist
    if [[ -f "$backup_dir/disk_paths.txt" ]]; then
        local disk_files
        disk_files=($(find "$backup_dir" -name "*.qcow2" -o -name "*.img" -o -name "*.raw"))
        
        for disk_file in "${disk_files[@]}"; do
            if ! qemu-img info "$disk_file" >/dev/null 2>&1; then
                error "Invalid disk image in backup: $disk_file"
                return 1
            fi
            
            # Verify checksum if available
            local checksum_file="${disk_file}.md5"
            if [[ -f "$checksum_file" ]]; then
                local expected_checksum
                expected_checksum=$(cat "$checksum_file")
                if ! verify_file_integrity "$disk_file" "$expected_checksum"; then
                    return 1
                fi
            fi
        done
    fi
    
    success "Backup validation passed for $vm_name"
    return 0
}

# Get list of VMs
get_vm_list() {
    if [[ -n "${1:-}" ]]; then
        echo "$1"
    else
        virsh_with_timeout "$VIRSH_TIMEOUT" list --all --name | grep -v '^$'
    fi
}

# Check if VM exists
vm_exists() {
    local vm_name="$1"
    if ! virsh_with_timeout "$VIRSH_TIMEOUT" dominfo "$vm_name" &>/dev/null; then
        return 1
    fi
    return 0
}

# Get VM state
get_vm_state() {
    local vm_name="$1"
    virsh_with_timeout "$VIRSH_TIMEOUT" domstate "$vm_name" 2>/dev/null
}

# Backup a single VM
backup_vm() {
    local vm_name="$1"
    local backup_timestamp="${2:-$(date +%Y%m%d_%H%M%S)}"
    local vm_backup_dir="$BACKUP_DIR/${vm_name}_${backup_timestamp}"
    
    log "Starting backup of VM: $vm_name"
    
    # Acquire VM lock
    if ! acquire_vm_lock "$vm_name"; then
        return 1
    fi
    
    # Set global backup dir for cleanup
    CURRENT_BACKUP_DIR="$vm_backup_dir"
    
    if ! vm_exists "$vm_name"; then
        error "VM '$vm_name' does not exist"
        release_vm_lock "$vm_name"
        return 1
    fi
    
    # Estimate backup size and check disk space
    local estimated_size_mb
    estimated_size_mb=$(estimate_vm_backup_size "$vm_name")
    local required_space_mb=$((estimated_size_mb + MIN_FREE_SPACE_MB))
    
    if ! check_disk_space "$BACKUP_DIR" "$required_space_mb"; then
        release_vm_lock "$vm_name"
        return 1
    fi
    
    # Create VM-specific backup directory
    if ! mkdir -p "$vm_backup_dir"; then
        error "Failed to create backup directory: $vm_backup_dir"
        release_vm_lock "$vm_name"
        return 1
    fi
    
    # Get VM state
    local vm_state
    vm_state=$(get_vm_state "$vm_name")
    echo "$vm_state" > "$vm_backup_dir/vm_state.txt"
    
    # Shutdown VM if running
    local was_running=false
    if [[ "$vm_state" == "running" ]]; then
        warning "VM $vm_name is running. Shutting down for backup..."
        if ! virsh_with_timeout "$VIRSH_TIMEOUT" shutdown "$vm_name"; then
            error "Failed to initiate VM shutdown"
            release_vm_lock "$vm_name"
            return 1
        fi
        was_running=true
        
        # Wait for shutdown with timeout
        local timeout=$SHUTDOWN_TIMEOUT
        while [[ $timeout -gt 0 ]] && [[ $(get_vm_state "$vm_name") == "running" ]]; do
            sleep 2
            ((timeout-=2))
        done
        
        if [[ $(get_vm_state "$vm_name") == "running" ]]; then
            warning "Graceful shutdown failed. Force stopping VM..."
            if ! virsh_with_timeout "$VIRSH_TIMEOUT" destroy "$vm_name"; then
                error "Failed to force stop VM"
                release_vm_lock "$vm_name"
                return 1
            fi
            sleep 5
        fi
    fi
    
    # Export VM configuration
    log "Exporting VM configuration..."
    if ! virsh_with_timeout "$VIRSH_TIMEOUT" dumpxml "$vm_name" > "$vm_backup_dir/${vm_name}.xml"; then
        error "Failed to export VM configuration"
        release_vm_lock "$vm_name"
        return 1
    fi
    
    # Calculate checksum for XML
    local xml_checksum
    xml_checksum=$(calculate_checksum "$vm_backup_dir/${vm_name}.xml")
    echo "$xml_checksum" > "$vm_backup_dir/${vm_name}.xml.md5"
    
    # Get disk images
    log "Finding disk images..."
    local disk_images
    disk_images=$(virsh_with_timeout "$VIRSH_TIMEOUT" domblklist "$vm_name" --details | awk '/^file.*disk/ {print $4}')
    
    if [[ -z "$disk_images" ]]; then
        warning "No disk images found for VM $vm_name"
    else
        # Backup each disk image
        while IFS= read -r disk_path; do
            if [[ -f "$disk_path" ]]; then
                local disk_name
                disk_name=$(basename "$disk_path")
                log "Backing up disk: $disk_name"
                
                local dest_file="$vm_backup_dir/$disk_name"
                local disk_size=$(stat -c "%s" "$disk_path")
                
                if $PV_AVAILABLE; then
                    # Use pv for nice progress bar if available
                    log "Using pv for progress tracking..."
                    if ! qemu-img convert -O qcow2 -c "$disk_path" - | \
                        pv -s "$disk_size" -N "$disk_name" > "$dest_file"; then
                        error "Failed to backup disk image: $disk_path"
                        release_vm_lock "$vm_name"
                        return 1
                    fi
                else
                    # Fallback to basic progress if pv not available
                    log "Starting backup (install 'pv' for better progress display)..."
                    if ! qemu-img convert -O qcow2 -c -p "$disk_path" "$dest_file"; then
                        error "Failed to backup disk image: $disk_path"
                        release_vm_lock "$vm_name"
                        return 1
                    fi
                fi
                
                # Validate the qemu-img operation
                if ! validate_qemu_img_operation "$disk_path" "$dest_file"; then
                    release_vm_lock "$vm_name"
                    return 1
                fi
                
                # Calculate and store checksum
                local disk_checksum
                disk_checksum=$(calculate_checksum "$dest_file")
                echo "$disk_checksum" > "${dest_file}.md5"
                
                # Store original disk path for restore
                echo "$disk_path" >> "$vm_backup_dir/disk_paths.txt"
            else
                warning "Disk image not found: $disk_path"
            fi
        done <<< "$disk_images"
    fi
    
    # Backup snapshots list
    log "Exporting snapshots..."
    virsh_with_timeout "$VIRSH_TIMEOUT" snapshot-list "$vm_name" --name 2>/dev/null > "$vm_backup_dir/snapshots.txt" || true
    
    # Create backup manifest with checksums
    cat > "$vm_backup_dir/backup_manifest.txt" << EOF
VM Name: $vm_name
Backup Date: $(date)
Original State: $vm_state
Backup Directory: $vm_backup_dir
Script Version: 2.0
Estimated Size (MB): $estimated_size_mb
XML Checksum: $xml_checksum
EOF
    
    # Validate the backup
    if ! validate_backup "$vm_backup_dir" "$vm_name"; then
        error "Backup validation failed"
        release_vm_lock "$vm_name"
        return 1
    fi
    
    # Restart VM if it was running
    if [[ "$was_running" == true ]]; then
        log "Restarting VM $vm_name..."
        if ! virsh_with_timeout "$VIRSH_TIMEOUT" start "$vm_name"; then
            warning "Failed to restart VM $vm_name"
        fi
    fi
    
    # Clear current backup dir since backup completed successfully
    CURRENT_BACKUP_DIR=""
    
    release_vm_lock "$vm_name"
    success "Backup completed for VM: $vm_name"
    success "Backup location: $vm_backup_dir"
}

# Restore a single VM
restore_vm() {
    local vm_name="$1"
    local backup_path="$2"
    local overwrite="${3:-false}"
    
    log "Starting restore of VM: $vm_name from $backup_path"
    
    # Acquire VM lock
    if ! acquire_vm_lock "$vm_name"; then
        return 1
    fi
    
    if [[ ! -d "$backup_path" ]]; then
        error "Backup directory does not exist: $backup_path"
        release_vm_lock "$vm_name"
        return 1
    fi
    
    # Validate backup before restore
    if ! validate_backup "$backup_path" "$vm_name"; then
        error "Backup validation failed, restore aborted"
        release_vm_lock "$vm_name"
        return 1
    fi
    
    if [[ ! -f "$backup_path/${vm_name}.xml" ]]; then
        error "VM configuration file not found: $backup_path/${vm_name}.xml"
        release_vm_lock "$vm_name"
        return 1
    fi
    
    # Check if VM already exists
    if vm_exists "$vm_name"; then
        if [[ "$overwrite" != "true" ]]; then
            error "VM '$vm_name' already exists. Use --overwrite to replace it."
            release_vm_lock "$vm_name"
            return 1
        else
            warning "Removing existing VM: $vm_name"
            # Stop VM if running
            if [[ $(get_vm_state "$vm_name") == "running" ]]; then
                if ! virsh_with_timeout "$VIRSH_TIMEOUT" destroy "$vm_name"; then
                    error "Failed to stop existing VM"
                    release_vm_lock "$vm_name"
                    return 1
                fi
            fi
            # Undefine VM (keep storage)
            if ! virsh_with_timeout "$VIRSH_TIMEOUT" undefine "$vm_name" --nvram 2>/dev/null && \
               ! virsh_with_timeout "$VIRSH_TIMEOUT" undefine "$vm_name"; then
                error "Failed to undefine existing VM"
                release_vm_lock "$vm_name"
                return 1
            fi
        fi
    fi
    
    # Estimate required space for restore
    local backup_size_mb
    backup_size_mb=$(du -m "$backup_path" | tail -1 | cut -f1)
    local required_space_mb=$((backup_size_mb * 2 + MIN_FREE_SPACE_MB))  # 2x for safety
    
    if ! check_disk_space "$VM_IMAGES_DIR" "$required_space_mb"; then
        release_vm_lock "$vm_name"
        return 1
    fi
    
    # Restore disk images
    log "Restoring disk images..."
    if [[ -f "$backup_path/disk_paths.txt" ]]; then
        local line_number=1
        while IFS= read -r original_path; do
            local backup_disk_files
            backup_disk_files=($(find "$backup_path" -name "*.qcow2" -o -name "*.img" -o -name "*.raw"))
            
            if [[ ${#backup_disk_files[@]} -ge $line_number ]]; then
                local backup_disk="${backup_disk_files[$((line_number-1))]}"
                local target_dir
                target_dir=$(dirname "$original_path")
                local disk_size=$(stat -c "%s" "$backup_disk")
                
                # Create target directory if it doesn't exist
                mkdir -p "$target_dir"
                
                log "Restoring $(basename "$backup_disk") to $original_path"
                
                # Verify backup disk checksum before restore
                local checksum_file="${backup_disk}.md5"
                if [[ -f "$checksum_file" ]]; then
                    local expected_checksum
                    expected_checksum=$(cat "$checksum_file")
                    if ! verify_file_integrity "$backup_disk" "$expected_checksum"; then
                        error "Backup disk integrity check failed"
                        release_vm_lock "$vm_name"
                        return 1
                    fi
                fi
                
                if $PV_AVAILABLE; then
                    # Use pv for restore progress
                    if ! pv -s "$disk_size" -N "$(basename "$backup_disk")" "$backup_disk" | \
                        qemu-img convert -O qcow2 - "$original_path"; then
                        error "Failed to restore disk image: $backup_disk"
                        release_vm_lock "$vm_name"
                        return 1
                    fi
                else
                    # Fallback to basic restore
                    if ! qemu-img convert "$backup_disk" "$original_path"; then
                        error "Failed to restore disk image: $backup_disk"
                        release_vm_lock "$vm_name"
                        return 1
                    fi
                fi
                
                # Validate restored disk
                if ! qemu-img info "$original_path" >/dev/null 2>&1; then
                    error "Restored disk image appears to be corrupted: $original_path"
                    release_vm_lock "$vm_name"
                    return 1
                fi
                
                chown qemu:qemu "$original_path" 2>/dev/null || true
            fi
            ((line_number++))
        done < "$backup_path/disk_paths.txt"
    fi
    
    # Verify XML checksum before restore
    local xml_checksum_file="$backup_path/${vm_name}.xml.md5"
    if [[ -f "$xml_checksum_file" ]]; then
        local expected_xml_checksum
        expected_xml_checksum=$(cat "$xml_checksum_file")
        if ! verify_file_integrity "$backup_path/${vm_name}.xml" "$expected_xml_checksum"; then
            error "XML configuration integrity check failed"
            release_vm_lock "$vm_name"
            return 1
        fi
    fi
    
    # Restore VM configuration
    log "Restoring VM configuration..."
    if ! virsh_with_timeout "$VIRSH_TIMEOUT" define "$backup_path/${vm_name}.xml"; then
        error "Failed to define VM from backup configuration"
        release_vm_lock "$vm_name"
        return 1
    fi
    
    # Check if VM should be started
    if [[ -f "$backup_path/vm_state.txt" ]]; then
        local original_state
        original_state=$(cat "$backup_path/vm_state.txt")
        if [[ "$original_state" == "running" ]]; then
            log "Starting VM as it was running during backup..."
            if ! virsh_with_timeout "$VIRSH_TIMEOUT" start "$vm_name"; then
                warning "Failed to start VM, but restore completed successfully"
            fi
        fi
    fi
    
    release_vm_lock "$vm_name"
    success "Restore completed for VM: $vm_name"
}

# List available backups
list_backups() {
    local vm_name="${1:-}"
    
    log "Available backups in $BACKUP_DIR:"
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        warning "Backup directory does not exist: $BACKUP_DIR"
        return 0
    fi
    
    local backup_dirs
    if [[ -n "$vm_name" ]]; then
        backup_dirs=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "${vm_name}_*" | sort)
    else
        backup_dirs=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "*_*" | sort)
    fi
    
    if [[ -z "$backup_dirs" ]]; then
        echo "No backups found"
        return 0
    fi
    
    printf "%-30s %-20s %-15s %-10s\n" "VM Name" "Backup Date" "Size" "Status"
    printf "%-30s %-20s %-15s %-10s\n" "-------" "-----------" "----" "------"
    
    while IFS= read -r backup_dir; do
        if [[ -f "$backup_dir/backup_manifest.txt" ]]; then
            local vm_backup_name
            local backup_date
            local backup_size
            local status="Valid"
            
            vm_backup_name=$(basename "$backup_dir" | cut -d'_' -f1)
            backup_date=$(basename "$backup_dir" | cut -d'_' -f2- | sed 's/_/ /g')
            backup_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
            
            # Quick validation check
            if ! validate_backup "$backup_dir" "$vm_backup_name" >/dev/null 2>&1; then
                status="Invalid"
            fi
            
            printf "%-30s %-20s %-15s %-10s\n" "$vm_backup_name" "$backup_date" "$backup_size" "$status"
        fi
    done <<< "$backup_dirs"
}

# Show usage information
show_usage() {
    cat << EOF
VM Backup and Restore Script v2.0

USAGE:
    $0 backup [VM_NAME] [options]        Backup VM(s)
    $0 restore VM_NAME BACKUP_PATH       Restore VM from backup
    $0 list [VM_NAME]                    List available backups

OPTIONS:
    --all                                Backup all VMs
    --overwrite                         Overwrite existing VM during restore
    --backup-dir DIR                    Set custom backup directory

EXAMPLES:
    $0 backup myvm                      Backup single VM
    $0 backup --all                     Backup all VMs
    $0 restore myvm /backup/vms/myvm_20240115_143022
    $0 restore myvm /backup/vms/myvm_20240115_143022 --overwrite
    $0 list                             List all backups
    $0 list myvm                        List backups for specific VM

FEATURES:
    - Disk space validation before backup
    - Checksum verification for data integrity
    - VM locking to prevent concurrent operations
    - Timeout handling for virsh commands
    - Automatic cleanup of failed backups
    - Comprehensive backup validation

BACKUP LOCATION: $BACKUP_DIR
EOF
}

# Main script logic
main() {
    local command="${1:-}"
    
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    # Parse global options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            backup|restore|list)
                command="$1"
                shift
                break
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                command="$1"
                shift
                break
                ;;
        esac
    done
    
    case "$command" in
        backup)
            check_root
            ensure_backup_dir
            
            local backup_all=false
            local vm_name=""
            
            # Parse backup options
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --all)
                        backup_all=true
                        shift
                        ;;
                    *)
                        vm_name="$1"
                        shift
                        ;;
                esac
            done
            
            local timestamp
            timestamp=$(date +%Y%m%d_%H%M%S)
            
            if [[ "$backup_all" == true ]]; then
                log "Starting backup of all VMs..."
                local vm_list
                vm_list=$(virsh_with_timeout "$VIRSH_TIMEOUT" list --all --name | grep -v '^$')
                if [[ -z "$vm_list" ]]; then
                    warning "No VMs found"
                    exit 0
                fi
                
                local failed_backups=()
                while IFS= read -r vm; do
                    if ! backup_vm "$vm" "$timestamp"; then
                        failed_backups+=("$vm")
                    fi
                done <<< "$vm_list"
                
                if [[ ${#failed_backups[@]} -gt 0 ]]; then
                    error "Failed to backup VMs: ${failed_backups[*]}"
                    exit 1
                fi
            elif [[ -n "$vm_name" ]]; then
                backup_vm "$vm_name" "$timestamp"
            else
                error "Please specify a VM name or use --all"
                show_usage
                exit 1
            fi
            ;;
            
        restore)
            check_root
            
            if [[ $# -lt 2 ]]; then
                error "Please specify VM name and backup path"
                show_usage
                exit 1
            fi
            
            local vm_name="$1"
            local backup_path="$2"
            local overwrite=false
            
            shift 2
            
            # Parse restore options
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --overwrite)
                        overwrite=true
                        shift
                        ;;
                    *)
                        error "Unknown option: $1"
                        exit 1
                        ;;
                esac
            done
            
            restore_vm "$vm_name" "$backup_path" "$overwrite"
            ;;
            
        list)
            local vm_name="${1:-}"
            list_backups "$vm_name"
            ;;
            
        *)
            error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"