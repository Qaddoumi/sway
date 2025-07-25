#!/bin/bash

# Enhanced VM Backup Script with Real Compression
# This version adds multiple compression strategies for better space savings

# Compression Configuration Options
# ==================================

# Compression method selection:
# - "gzip": Good balance of speed/compression (recommended for most cases)
# - "xz": Best compression ratio but slower (good for archival)  
# - "zstd": Fast compression with good ratio (requires zstd package)
# - "qcow2-sparse": Create sparse qcow2 without external compression
# - "raw-sparse": Create sparse RAW then compress with gzip
COMPRESSION_METHOD="gzip"

# Compression level (affects compression ratio vs speed):
# - gzip/xz: 1 (fastest) to 9 (best compression)
# - zstd: 1 (fastest) to 22 (best compression, level 6 recommended)
COMPRESSION_LEVEL="6"

# Advanced options
USE_SPARSE_COPY="true"         # Enable sparse file handling
ENABLE_ZERO_DETECTION="true"   # Enable zero block detection
PARALLEL_COMPRESSION="false"   # Use pigz/pxz for parallel compression (if available)

# Set compression method based on use case:
# For regular backups: COMPRESSION_METHOD="gzip" COMPRESSION_LEVEL="6"
# For archival: COMPRESSION_METHOD="xz" COMPRESSION_LEVEL="9"  
# For speed: COMPRESSION_METHOD="zstd" COMPRESSION_LEVEL="3"

# Enhanced disk backup function with multiple compression strategies
backup_disk_image_compressed() {
    local source_disk="$1"
    local dest_file="$2"
    local disk_name="$3"
    
    info "Starting compressed backup of disk: $disk_name"
    info "Source: $source_disk"
    info "Compression method: $COMPRESSION_METHOD"
    
    # Check source disk accessibility
    if ! sudo test -r "$source_disk"; then
        error "Cannot read source disk: $source_disk"
        return 1
    fi
    
    # Get source disk info
    local disk_info
    if ! disk_info=$(sudo qemu-img info "$source_disk" 2>&1); then
        error "Failed to get disk info for $source_disk"
        return 1
    fi
    
    local disk_size
    disk_size=$(sudo stat -c "%s" "$source_disk")
    info "Source disk size: $disk_size bytes ($(numfmt --to=iec-i --suffix=B "$disk_size"))"
    
    case "$COMPRESSION_METHOD" in
        "gzip")
            backup_disk_with_gzip "$source_disk" "$dest_file" "$disk_name"
            ;;
        "xz")
            backup_disk_with_xz "$source_disk" "$dest_file" "$disk_name"
            ;;
        "zstd")
            backup_disk_with_zstd "$source_disk" "$dest_file" "$disk_name"
            ;;
        "qcow2-sparse")
            backup_disk_qcow2_sparse "$source_disk" "$dest_file" "$disk_name"
            ;;
        "raw-sparse")
            backup_disk_raw_sparse "$source_disk" "$dest_file" "$disk_name"
            ;;
        *)
            error "Unknown compression method: $COMPRESSION_METHOD"
            return 1
            ;;
    esac
}

# Backup with gzip compression (good balance of speed/compression)
backup_disk_with_gzip() {
    local source_disk="$1"
    local dest_file="$2"
    local disk_name="$3"
    
    local temp_raw="/tmp/${disk_name}_temp.raw"
    local final_file="${dest_file%.qcow2}.img.gz"
    
    info "Converting to RAW format first..."
    if ! sudo qemu-img convert -f qcow2 -O raw "$source_disk" "$temp_raw"; then
        error "Failed to convert to RAW format"
        return 1
    fi
    
    # Use dd with sparse handling and pipe to gzip
    info "Compressing with gzip (level $COMPRESSION_LEVEL)..."
    if ! sudo dd if="$temp_raw" bs=1M status=progress 2>/dev/null | \
         gzip -"$COMPRESSION_LEVEL" | sudo tee "$final_file" >/dev/null; then
        error "Failed to compress with gzip"
        sudo rm -f "$temp_raw" "$final_file"
        return 1
    fi
    
    # Clean up temp file
    sudo rm -f "$temp_raw"
    
    # Update dest_file for checksum calculation
    echo "$final_file" > "${dest_file}.final_path"
    
    local compressed_size
    compressed_size=$(sudo stat -c "%s" "$final_file")
    local original_size
    original_size=$(sudo stat -c "%s" "$source_disk")
    local compression_ratio=$((compressed_size * 100 / original_size))
    
    success "Gzip compression completed. Size: $(numfmt --to=iec-i --suffix=B "$compressed_size") (${compression_ratio}% of original)"
    return 0
}

# Backup with xz compression (best compression ratio, slower)
backup_disk_with_xz() {
    local source_disk="$1"
    local dest_file="$2"
    local disk_name="$3"
    
    local temp_raw="/tmp/${disk_name}_temp.raw"
    local final_file="${dest_file%.qcow2}.img.xz"
    
    info "Converting to RAW format first..."
    if ! sudo qemu-img convert -f qcow2 -O raw "$source_disk" "$temp_raw"; then
        error "Failed to convert to RAW format"
        return 1
    fi
    
    info "Compressing with xz (level $COMPRESSION_LEVEL)..."
    if ! sudo dd if="$temp_raw" bs=1M status=progress 2>/dev/null | \
         xz -"$COMPRESSION_LEVEL" | sudo tee "$final_file" >/dev/null; then
        error "Failed to compress with xz"
        sudo rm -f "$temp_raw" "$final_file"
        return 1
    fi
    
    sudo rm -f "$temp_raw"
    echo "$final_file" > "${dest_file}.final_path"
    
    local compressed_size
    compressed_size=$(sudo stat -c "%s" "$final_file")
    local original_size
    original_size=$(sudo stat -c "%s" "$source_disk")
    local compression_ratio=$((compressed_size * 100 / original_size))
    
    success "XZ compression completed. Size: $(numfmt --to=iec-i --suffix=B "$compressed_size") (${compression_ratio}% of original)"
    return 0
}

# Backup with zstd compression (good speed and compression)
backup_disk_with_zstd() {
    local source_disk="$1"
    local dest_file="$2"
    local disk_name="$3"
    
    # Check if zstd is available
    if ! command -v zstd &>/dev/null; then
        warning "zstd not available, falling back to gzip"
        backup_disk_with_gzip "$source_disk" "$dest_file" "$disk_name"
        return $?
    fi
    
    local temp_raw="/tmp/${disk_name}_temp.raw"
    local final_file="${dest_file%.qcow2}.img.zst"
    
    info "Converting to RAW format first..."
    if ! sudo qemu-img convert -f qcow2 -O raw "$source_disk" "$temp_raw"; then
        error "Failed to convert to RAW format"
        return 1
    fi
    
    info "Compressing with zstd (level $COMPRESSION_LEVEL)..."
    if ! sudo dd if="$temp_raw" bs=1M status=progress 2>/dev/null | \
         zstd -"$COMPRESSION_LEVEL" | sudo tee "$final_file" >/dev/null; then
        error "Failed to compress with zstd"
        sudo rm -f "$temp_raw" "$final_file"
        return 1
    fi
    
    sudo rm -f "$temp_raw"
    echo "$final_file" > "${dest_file}.final_path"
    
    local compressed_size
    compressed_size=$(sudo stat -c "%s" "$final_file")
    local original_size
    original_size=$(sudo stat -c "%s" "$source_disk")
    local compression_ratio=$((compressed_size * 100 / original_size))
    
    success "Zstd compression completed. Size: $(numfmt --to=iec-i --suffix=B "$compressed_size") (${compression_ratio}% of original)"
    return 0
}

# Create a properly sparse qcow2 (removes unused space)
backup_disk_qcow2_sparse() {
    local source_disk="$1"
    local dest_file="$2"
    local disk_name="$3"
    
    info "Creating sparse qcow2 backup..."
    
    # Method 1: Convert with sparse detection
    local convert_opts=(-f qcow2 -O qcow2 -c -p)
    
    # Add sparse options if available
    if qemu-img convert --help 2>&1 | grep -q "detect-zeroes"; then
        convert_opts+=(-o detect-zeroes=on)
        info "Using zero detection optimization"
    fi
    
    if qemu-img convert --help 2>&1 | grep -q "skip-zero"; then
        convert_opts+=(--skip-zero)
        info "Using skip-zero optimization"
    fi
    
    # Perform the conversion
    if ! sudo qemu-img convert "${convert_opts[@]}" "$source_disk" "$dest_file"; then
        error "Failed to create sparse qcow2 backup"
        return 1
    fi
    
    # Try to shrink the image further by removing unused blocks
    info "Attempting to shrink qcow2 image..."
    if ! sudo qemu-img resize --shrink "$dest_file" --preallocation=off 2>/dev/null; then
        warning "Could not shrink qcow2 image (this is often normal)"
    fi
    
    local final_size
    final_size=$(sudo stat -c "%s" "$dest_file")
    local original_size
    original_size=$(sudo stat -c "%s" "$source_disk")
    local compression_ratio=$((final_size * 100 / original_size))
    
    success "Sparse qcow2 backup completed. Size: $(numfmt --to=iec-i --suffix=B "$final_size") (${compression_ratio}% of original)"
    return 0
}

# Create sparse RAW backup (useful for maximum compatibility)
backup_disk_raw_sparse() {
    local source_disk="$1"
    local dest_file="$2"
    local disk_name="$3"
    
    local raw_file="${dest_file%.qcow2}.raw"
    
    info "Creating sparse RAW backup..."
    
    # Convert to RAW with sparse handling
    if ! sudo qemu-img convert -f qcow2 -O raw -S 4k "$source_disk" "$raw_file"; then
        error "Failed to create sparse RAW backup"
        return 1
    fi
    
    # Compress the sparse RAW file
    info "Compressing sparse RAW file..."
    if ! sudo gzip -"$COMPRESSION_LEVEL" "$raw_file"; then
        error "Failed to compress RAW file"
        return 1
    fi
    
    local final_file="${raw_file}.gz"
    echo "$final_file" > "${dest_file}.final_path"
    
    local compressed_size
    compressed_size=$(sudo stat -c "%s" "$final_file")
    local original_size
    original_size=$(sudo stat -c "%s" "$source_disk")
    local compression_ratio=$((compressed_size * 100 / original_size))
    
    success "Sparse RAW backup completed. Size: $(numfmt --to=iec-i --suffix=B "$compressed_size") (${compression_ratio}% of original)"
    return 0
}

# Enhanced restore function to handle different compression formats
restore_compressed_disk() {
    local backup_file="$1"
    local target_path="$2"
    local disk_name="$3"
    
    info "Restoring compressed disk: $disk_name"
    info "From: $backup_file"
    info "To: $target_path"
    
    local file_ext="${backup_file##*.}"
    local temp_file="/tmp/restore_${disk_name}_temp"
    
    case "$file_ext" in
        "gz")
            info "Decompressing gzip file..."
            if ! sudo gunzip -c "$backup_file" > "$temp_file"; then
                error "Failed to decompress gzip file"
                return 1
            fi
            
            # Convert RAW to qcow2 if needed
            if [[ "$target_path" == *.qcow2 ]]; then
                info "Converting RAW to qcow2..."
                if ! sudo qemu-img convert -f raw -O qcow2 "$temp_file" "$target_path"; then
                    error "Failed to convert RAW to qcow2"
                    sudo rm -f "$temp_file"
                    return 1
                fi
            else
                sudo mv "$temp_file" "$target_path"
            fi
            ;;
            
        "xz")
            info "Decompressing xz file..."
            if ! sudo xz -d -c "$backup_file" > "$temp_file"; then
                error "Failed to decompress xz file"
                return 1
            fi
            
            if [[ "$target_path" == *.qcow2 ]]; then
                if ! sudo qemu-img convert -f raw -O qcow2 "$temp_file" "$target_path"; then
                    error "Failed to convert RAW to qcow2"
                    sudo rm -f "$temp_file"
                    return 1
                fi
            else
                sudo mv "$temp_file" "$target_path"
            fi
            ;;
            
        "zst")
            info "Decompressing zstd file..."
            if ! sudo zstd -d -c "$backup_file" > "$temp_file"; then
                error "Failed to decompress zstd file"
                return 1
            fi
            
            if [[ "$target_path" == *.qcow2 ]]; then
                if ! sudo qemu-img convert -f raw -O qcow2 "$temp_file" "$target_path"; then
                    error "Failed to convert RAW to qcow2"
                    sudo rm -f "$temp_file"
                    return 1
                fi
            else
                sudo mv "$temp_file" "$target_path"
            fi
            ;;
            
        "qcow2")
            info "Copying qcow2 file directly..."
            if ! sudo cp "$backup_file" "$target_path"; then
                error "Failed to copy qcow2 file"
                return 1
            fi
            ;;
            
        *)
            error "Unknown backup file format: $file_ext"
            return 1
            ;;
    esac
    
    # Clean up temp file
    sudo rm -f "$temp_file"
    
    # Set proper ownership
    sudo chown qemu:qemu "$target_path" 2>/dev/null || true
    
    success "Disk restoration completed: $disk_name"
    return 0
}

# Add a function to show compression statistics
show_compression_stats() {
    local backup_dir="$1"
    
    if [[ ! -d "$backup_dir" ]]; then
        return 0
    fi
    
    info "Compression Statistics for $(basename "$backup_dir"):"
    
    local total_original=0
    local total_compressed=0
    
    # Find all backup files
    find "$backup_dir" -name "*.gz" -o -name "*.xz" -o -name "*.zst" -o -name "*.qcow2" | while read -r backup_file; do
        if [[ -f "${backup_file}.original_size" ]]; then
            local original_size
            original_size=$(cat "${backup_file}.original_size")
            local compressed_size
            compressed_size=$(stat -c "%s" "$backup_file")
            local ratio=$((compressed_size * 100 / original_size))
            local saved=$((original_size - compressed_size))
            
            printf "  %-30s: %s -> %s (%d%%, saved %s)\n" \
                "$(basename "$backup_file")" \
                "$(numfmt --to=iec-i --suffix=B "$original_size")" \
                "$(numfmt --to=iec-i --suffix=B "$compressed_size")" \
                "$ratio" \
                "$(numfmt --to=iec-i --suffix=B "$saved")"
                
            total_original=$((total_original + original_size))
            total_compressed=$((total_compressed + compressed_size))
        fi
    done
    
    if [[ $total_original -gt 0 ]]; then
        local total_ratio=$((total_compressed * 100 / total_original))
        local total_saved=$((total_original - total_compressed))
        
        echo
        printf "  %-30s: %s -> %s (%d%%, saved %s)\n" \
            "TOTAL" \
            "$(numfmt --to=iec-i --suffix=B "$total_original")" \
            "$(numfmt --to=iec-i --suffix=B "$total_compressed")" \
            "$total_ratio" \
            "$(numfmt --to=iec-i --suffix=B "$total_saved")"
    fi
}

# Replace the original backup_disk_image function call in backup_vm()
# Find this section in the original script and replace the backup call:

# In the backup_vm function, replace this part:
#                if ! backup_disk_image "$disk_path" "$dest_file" "$disk_name"; then
#                    error "Failed to backup disk image: $disk_path"
#                    release_vm_lock "$vm_name"
#                    return 1
#                fi

# With this:
#                # Store original size for compression statistics
#                local original_size
#                original_size=$(sudo stat -c "%s" "$disk_path")
#                echo "$original_size" | sudo tee "${dest_file}.original_size" >/dev/null
#                
#                if ! backup_disk_image_compressed "$disk_path" "$dest_file" "$disk_name"; then
#                    error "Failed to backup disk image: $disk_path"
#                    release_vm_lock "$vm_name"
#                    return 1
#                fi