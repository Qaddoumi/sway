#!/bin/bash

# GPU PCI ID Identifier Script for VFIO Passthrough
# This script identifies GPU PCI IDs and generates VFIO configuration

echo "=== GPU PCI ID Identifier for VFIO Passthrough ==="
echo ""

# Colors for better readability
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
no_color='\033[0m' # No Color

# Function to extract PCI ID from lspci output
extract_pci_id() {
    echo "$1" | grep -o '\[.*\]' | tail -1 | tr -d '[]' | sed "s/^\(.*\)$/'\1'/"
}

# Function to extract PCI address
extract_pci_address() {
    echo "$1" | cut -d' ' -f1
}

echo -e "${green}1. Detecting all GPUs in system...${no_color}"
echo ""

# Get all VGA and 3D controllers
gpu_devices=$(lspci -nn | grep -E "(VGA|3D controller)")

if [ -z "$gpu_devices" ]; then
    echo -e "${red}No GPU devices found!${no_color}"
    exit 1
fi

echo -e "${green}Found GPU devices:${no_color}"
echo "$gpu_devices"
echo ""

# Separate integrated and discrete GPUs
echo -e "${green}2. Categorizing GPUs...${no_color}"
echo ""

intel_gpu=""
nvidia_gpu=""
amd_gpu=""

while IFS= read -r line; do
    if [[ $line == *"Intel"* ]]; then
        intel_gpu="$line"
        echo -e "${green}Intel iGPU:${no_color} $line"
    elif [[ $line == *"NVIDIA"* ]]; then
        nvidia_gpu="$line"
        echo -e "${green}NVIDIA dGPU:${no_color} $line"
    elif [[ $line == *"AMD"* ]] || [[ $line == *"Advanced Micro Devices"* ]]; then
        amd_gpu="$line"
        echo -e "${green}AMD GPU:${no_color} $line"
    fi
done <<< "$gpu_devices"

echo ""

# Find associated audio devices for discrete GPUs
echo -e "${green}3. Finding associated audio devices...${no_color}"
echo ""

if [ -n "$nvidia_gpu" ]; then
    nvidia_pci_addr=$(extract_pci_address "$nvidia_gpu")
    nvidia_bus=$(echo "$nvidia_pci_addr" | cut -d':' -f1)
    
    # Look for NVIDIA audio on same bus
    nvidia_audio=$(lspci -nn | grep -E "Audio.*NVIDIA" | grep "^$nvidia_bus:")
    
    if [ -n "$nvidia_audio" ]; then
        echo -e "${green}NVIDIA Audio Device:${no_color} $nvidia_audio"
    else
        echo -e "${yellow}No NVIDIA audio device found on same bus${no_color}"
    fi
fi

if [ -n "$amd_gpu" ]; then
    amd_pci_addr=$(extract_pci_address "$amd_gpu")
    amd_bus=$(echo "$amd_pci_addr" | cut -d':' -f1)
    
    # Look for AMD audio on same bus
    amd_audio=$(lspci -nn | grep -E "Audio.*AMD" | grep "^$amd_bus:")
    
    if [ -n "$amd_audio" ]; then
        echo -e "${green}AMD Audio Device:${no_color} $amd_audio"
    else
        echo -e "${yellow}No AMD audio device found on same bus${no_color}"
    fi
fi

echo ""

# Generate VFIO configuration
echo -e "${green}4. VFIO Configuration for GPU Passthrough...${no_color}"
echo ""

GPU_PCI_ID=""
AUDIO_PCI_ID=""
VFIO_IDS=""
GPU_TYPE=""

if [ -n "$nvidia_gpu" ]; then
    nvidia_gpu_id=$(extract_pci_id "$nvidia_gpu")
    nvidia_pci_addr=$(extract_pci_address "$nvidia_gpu")
    GPU_TYPE="nvidia"
    
    echo -e "${green}=== NVIDIA GPU Passthrough Configuration ===${no_color}"
    echo -e "${yellow}GPU PCI Address:${no_color} $nvidia_pci_addr"
    echo -e "${yellow}GPU PCI ID:${no_color} $nvidia_gpu_id"
    
    VFIO_IDS="$nvidia_gpu_id"
    
    if [ -n "$nvidia_audio" ]; then
        nvidia_audio_id=$(extract_pci_id "$nvidia_audio")
        nvidia_audio_addr=$(extract_pci_address "$nvidia_audio")
        echo -e "${yellow}Audio PCI Address:${no_color} $nvidia_audio_addr"
        echo -e "${yellow}Audio PCI ID:${no_color} $nvidia_audio_id"
        
        VFIO_IDS="$VFIO_IDS $nvidia_audio_id"
    fi
    
    GPU_PCI_ID="$nvidia_pci_addr"
    AUDIO_PCI_ID="$nvidia_audio_addr"
fi

if [ -n "$amd_gpu" ]; then
    amd_gpu_id=$(extract_pci_id "$amd_gpu")
    amd_pci_addr=$(extract_pci_address "$amd_gpu")
    GPU_TYPE="amdgpu"
    
    echo ""
    echo -e "${green}=== AMD GPU Passthrough Configuration ===${no_color}"
    echo -e "${yellow}GPU PCI Address:${no_color} $amd_pci_addr"
    echo -e "${yellow}GPU PCI ID:${no_color} $amd_gpu_id"
    
    VFIO_IDS="$amd_gpu_id"
    
    if [ -n "$amd_audio" ]; then
        amd_audio_id=$(extract_pci_id "$amd_audio")
        amd_audio_addr=$(extract_pci_address "$amd_audio")
        echo -e "${yellow}Audio PCI Address:${no_color} $amd_audio_addr"
        echo -e "${yellow}Audio PCI ID:${no_color} $amd_audio_id"
        
        VFIO_IDS="$VFIO_IDS $amd_audio_id"
    fi
    
    GPU_PCI_ID="$amd_pci_addr"
    AUDIO_PCI_ID="$amd_audio_addr"
fi

if [ -n "$VFIO_IDS" ]; then
    echo ""
    echo -e "${green}Kernel parameter for GRUB:${no_color}"
    echo "intel_iommu=on iommu=pt vfio-pci.ids=$VFIO_IDS"
    
    echo ""
    echo -e "${green}To add to GRUB:${no_color}"
    echo "1. Edit /etc/default/grub"
    echo "2. Add or modify GRUB_CMDLINE_LINUX_DEFAULT to include:"
    echo "   GRUB_CMDLINE_LINUX_DEFAULT=\"... intel_iommu=on iommu=pt vfio-pci.ids=$VFIO_IDS\""
    echo "3. Update GRUB: sudo grub-mkconfig -o /boot/grub/grub.cfg"
    echo ""
    echo -e "${green}PCI addresses for unbinding script:${no_color}"
    echo "GPU: $GPU_PCI_ID"
    [ -n "$AUDIO_PCI_ID" ] && echo "Audio: $AUDIO_PCI_ID"
else
    echo -e "${red}No valid GPU configuration found for VFIO passthrough${no_color}"
    exit 1
fi

echo ""

# Check IOMMU groups
echo -e "${green}5. IOMMU Group Information...${no_color}"
echo ""

if [ -d "/sys/kernel/iommu_groups" ]; then
    echo -e "${green}Checking IOMMU groups for GPU devices:${no_color}"
    echo ""
    
    for d in /sys/kernel/iommu_groups/*/devices/*; do 
        if [ -e "$d" ]; then
            n=${d#*/iommu_groups/*}
            n=${n%%/*}
            device_info=$(lspci -nns "${d##*/}" 2>/dev/null)
            
            # Check if this device is one of our GPUs or audio devices
            if [[ $device_info == *"VGA"* ]] || [[ $device_info == *"3D controller"* ]] || [[ $device_info == *"Audio"* ]]; then
                if [[ $device_info == *"Intel"* ]] || [[ $device_info == *"NVIDIA"* ]] || [[ $device_info == *"AMD"* ]]; then
                    printf "${yellow}IOMMU Group %s:${no_color} %s\n" "$n" "$device_info"
                fi
            fi
        fi
    done
else
    echo -e "${red}IOMMU not enabled or not available${no_color}"
    echo "Make sure VT-d (Intel) or AMD-Vi is enabled in BIOS and intel_iommu=on or amd_iommu=on is in kernel parameters"
    exit 1
fi

echo ""

# Generate GPU switch script
echo -e "${green}6. Creating GPU switch script...${no_color}"
SWITCH_SCRIPT="/usr/local/bin/gpu-switch.sh"

login_manager="sddm"  

# Determine driver based on GPU type
case "$GPU_TYPE" in
    "nvidia")
        GPU_DRIVER="nvidia"
        AUDIO_DRIVER="snd_hda_intel"
        ;;
    "amdgpu")
        GPU_DRIVER="amdgpu"
        AUDIO_DRIVER="snd_hda_intel"
        ;;
    *)
        echo -e "${red}No supported GPU driver detected for switching${no_color}"
        exit 1
        ;;
esac

# Generate the script
cat << SWITCH_SCRIPT_EOF | sudo tee "$SWITCH_SCRIPT" > /dev/null
#!/bin/bash

# GPU Switch Script for VFIO Passthrough
# Switches GPU between host and VM

GPU_PCI_ID="$GPU_PCI_ID"
AUDIO_PCI_ID="$AUDIO_PCI_ID"
GPU_DRIVER="$GPU_DRIVER"
AUDIO_DRIVER="$AUDIO_DRIVER"
LOGIN_MANAGER="$login_manager"

case "\$1" in
    "vm")
        echo -e "Switching GPU to VM mode..."
        # Stop display manager
        sudo systemctl stop "\$LOGIN_MANAGER" || { echo -e "Failed to stop display manager"; exit 1; }
        
        # Unload host GPU drivers
        sudo modprobe -r \$GPU_DRIVER 2>/dev/null || true
        sudo modprobe -r nvidia_drm nvidia_modeset nvidia_uvm 2>/dev/null || true
        
        # Unbind devices from host drivers
        [ -n "\$GPU_PCI_ID" ] && echo "\$GPU_PCI_ID" | sudo tee /sys/bus/pci/devices/\$GPU_PCI_ID/driver/unbind 2>/dev/null || true
        [ -n "\$AUDIO_PCI_ID" ] && echo "\$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/devices/\$AUDIO_PCI_ID/driver/unbind 2>/dev/null || true
        
        # Bind to vfio-pci
        sudo modprobe vfio-pci || { echo -e "Failed to load vfio-pci"; exit 1; }
        [ -n "\$GPU_PCI_ID" ] && echo "\$GPU_PCI_ID" | sudo tee /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
        [ -n "\$AUDIO_PCI_ID" ] && echo "\$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
        
        echo -e "GPU switched to VM mode"
        ;;
    "host")
        echo -e "Switching GPU to host mode..."
        # Unbind from vfio-pci
        sudo modprobe -r vfio-pci 2>/dev/null || true
        [ -n "\$GPU_PCI_ID" ] && echo "\$GPU_PCI_ID" | sudo tee /sys/bus/pci/devices/\$GPU_PCI_ID/driver/unbind 2>/dev/null || true
        [ -n "\$AUDIO_PCI_ID" ] && echo "\$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/devices/\$AUDIO_PCI_ID/driver/unbind 2>/dev/null || true
        
        # Clear driver overrides
        [ -n "\$GPU_PCI_ID" ] && echo "" | sudo tee /sys/bus/pci/devices/\$GPU_PCI_ID/driver_override 2>/dev/null || true
        [ -n "\$AUDIO_PCI_ID" ] && echo "" | sudo tee /sys/bus/pci/devices/\$AUDIO_PCI_ID/driver_override 2>/dev/null || true
        
        # Bind to host drivers
        [ -n "\$GPU_PCI_ID" ] && echo "\$GPU_PCI_ID" | sudo tee /sys/bus/pci/drivers/\$GPU_DRIVER/bind 2>/dev/null || true
        [ -n "\$AUDIO_PCI_ID" ] && echo "\$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/drivers/\$AUDIO_DRIVER/bind 2>/dev/null || true
        
        # Load host GPU driver
        sudo modprobe \$GPU_DRIVER || { echo -e "Failed to load \$GPU_DRIVER"; exit 1; }
        
        # Restart display manager
        sudo systemctl start "\$LOGIN_MANAGER" || { echo -e "Failed to start display manager"; exit 1; }
        
        echo -e "GPU switched to host mode"
        ;;
    *)
        echo -e "Usage: \$0 {vm|host}"
        exit 1
        ;;
esac
SWITCH_SCRIPT_EOF

sudo chmod +x "$SWITCH_SCRIPT"
echo -e "${green}Created GPU switch script at $SWITCH_SCRIPT${no_color}"
echo ""

# Recommendations
echo -e "${green}7. Next Steps...${no_color}"
echo ""
echo "1. Ensure VFIO modules are loaded at boot:"
echo "   Edit /etc/mkinitcpio.conf and add to MODULES:"
echo "   MODULES=(... vfio vfio_iommu_type1 vfio_virqfd vfio_pci."

echo "   Then run: sudo mkinitcpio -P"
echo ""
echo "2. Blacklist host GPU drivers to prevent automatic binding:"
echo "   Create /etc/modprobe.d/vfio.conf with:"
if [ "$GPU_TYPE" = "nvidia" ]; then
    echo "   blacklist nvidia"
    echo "   blacklist nvidia_drm"
    echo "   blacklist nvidia_modeset"
    echo "   blacklist nouveau"
elif [ "$GPU_TYPE" = "amdgpu" ]; then
    echo "   blacklist amdgpu"
    echo "   blacklist radeon"
fi
echo ""
echo "3. Create libvirt hook to automate GPU switching:"
echo "   Create /etc/libvirt/hooks/qemu with:"
echo "   #!/bin/bash"
echo "   GUEST_NAME=\"your-vm-name\""
echo "   COMMAND=\"\$1\""
echo "   EVENT=\"\$2\""
echo "   if [ \"\$COMMAND\" = \"\$GUEST_NAME\" ]; then"
echo "       if [ \"\$EVENT\" = \"prepare\" ]; then"
echo "           $SWITCH_SCRIPT vm"
echo "       elif [ \"\$EVENT\" = \"release\" ]; then"
echo "           $SWITCH_SCRIPT host"
echo "       fi"
echo "   fi"
echo "   Make it executable: sudo chmod +x /etc/libvirt/hooks/qemu"
echo "   Restart libvirtd: sudo systemctl restart libvirtd"
echo ""
echo -e "${green}Script completed! Use the information above to configure VFIO passthrough.${no_color}"