#!/bin/bash

# Script to unmount and power off the Mkohaa4TB external drive

DRIVE_NAME="Mkohaa4TB"

echo "Starting unmount process for $DRIVE_NAME..."

# Find the device path by searching for the drive label
DEVICE_NAME=$(lsblk -no NAME,LABEL | grep "$DRIVE_NAME" | awk '{print $1}' | sed 's/^[^a-zA-Z0-9]*//')
DEVICE="/dev/$DEVICE_NAME"

if [ -z "$DEVICE_NAME" ]; then
    echo "Error: Could not find device with label '$DRIVE_NAME'"
    echo "Available drives:"
    lsblk -no NAME,LABEL,SIZE,MOUNTPOINTS
    exit 1
fi

# Get the parent device (remove partition number)
PARENT_DEVICE=$(echo $DEVICE | sed 's/[0-9]*$//')

echo "Found drive: $DEVICE (parent: $PARENT_DEVICE)"

# Check if the drive is mounted
MOUNT_POINT=$(lsblk -no MOUNTPOINTS $DEVICE | grep -v "^$" | head -1)

if [ -n "$MOUNT_POINT" ]; then
    echo "Drive is mounted at: $MOUNT_POINT"
    echo "Unmounting $DRIVE_NAME..."
    
    # Unmount the drive
    if udisksctl unmount -b "$DEVICE"; then
        echo "Successfully unmounted $DRIVE_NAME"
    else
        echo "Error: Failed to unmount $DRIVE_NAME"
        exit 1
    fi
else
    echo "$DRIVE_NAME is not currently mounted"
fi

# Power off the drive
echo "Powering off $PARENT_DEVICE..."
if udisksctl power-off -b $PARENT_DEVICE; then
    echo "Successfully powered off $PARENT_DEVICE"
    echo "It is now safe to disconnect the drive"
else
    echo "Error: Failed to power off $PARENT_DEVICE"
    exit 1
fi

echo "Process completed successfully!"