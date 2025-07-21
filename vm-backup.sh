#!/bin/bash

# VM Backup and Restore Script for libvirt/KVM
# Usage: vm-backup.sh [backup|restore|list] [options]

set -euo pipefail

# Configuration
BACKUP_DIR="/backup/vms"
VM_IMAGES_DIR="/var/lib/libvirt/images"
LIBVIRT_CONFIG_DIR="/etc/libvirt/qemu"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
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
        mkdir -p "$BACKUP_DIR"
    fi
}

# Get list of VMs
get_vm_list() {
    if [[ -n "${1:-}" ]]; then
        echo "$1"
    else
        virsh list --all --name | grep -v '^$'
    fi
}

# Check if VM exists
vm_exists() {
    local vm_name="$1"
    if ! virsh dominfo "$vm_name" &>/dev/null; then
        return 1
    fi
    return 0
}

# Get VM state
get_vm_state() {
    local vm_name="$1"
    virsh domstate "$vm_name" 2>/dev/null
}

# Backup a single VM
backup_vm() {
    local vm_name="$1"
    local backup_timestamp="${2:-$(date +%Y%m%d_%H%M%S)}"
    local vm_backup_dir="$BACKUP_DIR/${vm_name}_${backup_timestamp}"
    
    log "Starting backup of VM: $vm_name"
    
    if ! vm_exists "$vm_name"; then
        error "VM '$vm_name' does not exist"
        return 1
    fi
    
    # Create VM-specific backup directory
    mkdir -p "$vm_backup_dir"
    
    # Get VM state
    local vm_state
    vm_state=$(get_vm_state "$vm_name")
    echo "$vm_state" > "$vm_backup_dir/vm_state.txt"
    
    # Shutdown VM if running
    local was_running=false
    if [[ "$vm_state" == "running" ]]; then
        warning "VM $vm_name is running. Shutting down for backup..."
        virsh shutdown "$vm_name"
        was_running=true
        
        # Wait for shutdown (max 60 seconds)
        local timeout=60
        while [[ $timeout -gt 0 ]] && [[ $(get_vm_state "$vm_name") == "running" ]]; do
            sleep 2
            ((timeout-=2))
        done
        
        if [[ $(get_vm_state "$vm_name") == "running" ]]; then
            warning "Graceful shutdown failed. Force stopping VM..."
            virsh destroy "$vm_name"
            sleep 5
        fi
    fi
    
    # Export VM configuration
    log "Exporting VM configuration..."
    virsh dumpxml "$vm_name" > "$vm_backup_dir/${vm_name}.xml"
    
    # Get disk images
    log "Finding disk images..."
    local disk_images
    disk_images=$(virsh domblklist "$vm_name" --details | awk '/^file.*disk/ {print $4}')
    
    if [[ -z "$disk_images" ]]; then
        warning "No disk images found for VM $vm_name"
    else
        # Backup each disk image
        while IFS= read -r disk_path; do
            if [[ -f "$disk_path" ]]; then
                local disk_name
                disk_name=$(basename "$disk_path")
                log "Backing up disk: $disk_name"
                
                # Use qemu-img convert for better compression and consistency
                qemu-img convert -O qcow2 -c "$disk_path" "$vm_backup_dir/$disk_name"
                
                # Store original disk path for restore
                echo "$disk_path" >> "$vm_backup_dir/disk_paths.txt"
            else
                warning "Disk image not found: $disk_path"
            fi
        done <<< "$disk_images"
    fi
    
    # Backup snapshots list
    log "Exporting snapshots..."
    virsh snapshot-list "$vm_name" --name 2>/dev/null > "$vm_backup_dir/snapshots.txt" || true
    
    # Create backup manifest
    cat > "$vm_backup_dir/backup_manifest.txt" << EOF
VM Name: $vm_name
Backup Date: $(date)
Original State: $vm_state
Backup Directory: $vm_backup_dir
Script Version: 1.0
EOF
    
    # Restart VM if it was running
    if [[ "$was_running" == true ]]; then
        log "Restarting VM $vm_name..."
        virsh start "$vm_name"
    fi
    
    success "Backup completed for VM: $vm_name"
    success "Backup location: $vm_backup_dir"
}

# Restore a single VM
restore_vm() {
    local vm_name="$1"
    local backup_path="$2"
    local overwrite="${3:-false}"
    
    log "Starting restore of VM: $vm_name from $backup_path"
    
    if [[ ! -d "$backup_path" ]]; then
        error "Backup directory does not exist: $backup_path"
        return 1
    fi
    
    if [[ ! -f "$backup_path/${vm_name}.xml" ]]; then
        error "VM configuration file not found: $backup_path/${vm_name}.xml"
        return 1
    fi
    
    # Check if VM already exists
    if vm_exists "$vm_name"; then
        if [[ "$overwrite" != "true" ]]; then
            error "VM '$vm_name' already exists. Use --overwrite to replace it."
            return 1
        else
            warning "Removing existing VM: $vm_name"
            # Stop VM if running
            if [[ $(get_vm_state "$vm_name") == "running" ]]; then
                virsh destroy "$vm_name"
            fi
            # Undefine VM (keep storage)
            virsh undefine "$vm_name" --nvram 2>/dev/null || virsh undefine "$vm_name"
        fi
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
                
                # Create target directory if it doesn't exist
                mkdir -p "$target_dir"
                
                log "Restoring $(basename "$backup_disk") to $original_path"
                qemu-img convert "$backup_disk" "$original_path"
                chown qemu:qemu "$original_path" 2>/dev/null || true
            fi
            ((line_number++))
        done < "$backup_path/disk_paths.txt"
    fi
    
    # Restore VM configuration
    log "Restoring VM configuration..."
    virsh define "$backup_path/${vm_name}.xml"
    
    # Check if VM should be started
    if [[ -f "$backup_path/vm_state.txt" ]]; then
        local original_state
        original_state=$(cat "$backup_path/vm_state.txt")
        if [[ "$original_state" == "running" ]]; then
            log "Starting VM as it was running during backup..."
            virsh start "$vm_name"
        fi
    fi
    
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
    
    printf "%-30s %-20s %-15s\n" "VM Name" "Backup Date" "Size"
    printf "%-30s %-20s %-15s\n" "-------" "-----------" "----"
    
    while IFS= read -r backup_dir; do
        if [[ -f "$backup_dir/backup_manifest.txt" ]]; then
            local vm_backup_name
            local backup_date
            local backup_size
            
            vm_backup_name=$(basename "$backup_dir" | cut -d'_' -f1)
            backup_date=$(basename "$backup_dir" | cut -d'_' -f2- | sed 's/_/ /g')
            backup_size=$(du -sh "$backup_dir" 2>/dev/null | cut -f1)
            
            printf "%-30s %-20s %-15s\n" "$vm_backup_name" "$backup_date" "$backup_size"
        fi
    done <<< "$backup_dirs"
}

# Show usage information
show_usage() {
    cat << EOF
VM Backup and Restore Script

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
                vm_list=$(virsh list --all --name | grep -v '^$')
                if [[ -z "$vm_list" ]]; then
                    warning "No VMs found"
                    exit 0
                fi
                
                while IFS= read -r vm; do
                    backup_vm "$vm" "$timestamp"
                done <<< "$vm_list"
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