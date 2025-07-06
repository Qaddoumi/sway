#!/bin/bash
login_manager="sddm"
case "$1" in
    "vm")
        # Stop display manager and unload nvidia
        sudo systemctl stop $login_manager
        sudo rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia
        echo "0000:01:00.0" | sudo tee /sys/bus/pci/devices/0000:01:00.0/driver/unbind
        echo "0000:01:00.1" | sudo tee /sys/bus/pci/devices/0000:01:00.1/driver/unbind
        sudo modprobe vfio-pci
        echo "GPU switched to VM mode"
        ;;
    "host")
        # Reload nvidia and restart display manager
        sudo rmmod vfio-pci
        echo "0000:01:00.0" | sudo tee /sys/bus/pci/drivers/nvidia/bind
        echo "0000:01:00.1" | sudo tee /sys/bus/pci/drivers/snd_hda_intel/bind
        sudo modprobe nvidia
        sudo systemctl start $login_manager
        echo "GPU switched to host mode"
        ;;
esac