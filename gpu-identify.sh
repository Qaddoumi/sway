#!/bin/bash

# GPU PCI ID Identifier Script for VFIO Passthrough
# This script identifies GPU PCI IDs needed for VFIO configuration

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
    echo "$1" | grep -o '\[.*\]' | tail -1 | tr -d '[]'
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

if [ -n "$nvidia_gpu" ]; then
    nvidia_gpu_id=$(extract_pci_id "$nvidia_gpu")
    nvidia_pci_addr=$(extract_pci_address "$nvidia_gpu")
    
    echo -e "${green}=== NVIDIA GPU Passthrough Configuration ===${no_color}"
    echo -e "${yellow}GPU PCI Address:${no_color} $nvidia_pci_addr"
    echo -e "${yellow}GPU PCI ID:${no_color} $nvidia_gpu_id"
    
    if [ -n "$nvidia_audio" ]; then
        nvidia_audio_id=$(extract_pci_id "$nvidia_audio")
        nvidia_audio_addr=$(extract_pci_address "$nvidia_audio")
        echo -e "${yellow}Audio PCI Address:${no_color} $nvidia_audio_addr"
        echo -e "${yellow}Audio PCI ID:${no_color} $nvidia_audio_id"
        
        echo ""
        echo -e "${green}Kernel parameter for GRUB:${no_color}"
        echo "intel_iommu=on iommu=pt vfio-pci.ids=$nvidia_gpu_id,$nvidia_audio_id"
        
        echo ""
        echo -e "${green}PCI addresses for unbinding script:${no_color}"
        echo "GPU: $nvidia_pci_addr"
        echo "Audio: $nvidia_audio_addr"
    else
        echo ""
        echo -e "${green}Kernel parameter for GRUB:${no_color}"
        echo "intel_iommu=on iommu=pt vfio-pci.ids=$nvidia_gpu_id"
        
        echo ""
        echo -e "${green}PCI address for unbinding script:${no_color}"
        echo "GPU: $nvidia_pci_addr"
    fi
    GPU_PCI_ID="$nvidia_pci_addr"
    AUDIO_PCI_ID="$nvidia_audio_addr"
fi

if [ -n "$amd_gpu" ]; then
    amd_gpu_id=$(extract_pci_id "$amd_gpu")
    amd_pci_addr=$(extract_pci_address "$amd_gpu")
    
    echo ""
    echo -e "${green}=== AMD GPU Passthrough Configuration ===${no_color}"
    echo -e "${yellow}GPU PCI Address:${no_color} $amd_pci_addr"
    echo -e "${yellow}GPU PCI ID:${no_color} $amd_gpu_id"
    
    if [ -n "$amd_audio" ]; then
        amd_audio_id=$(extract_pci_id "$amd_audio")
        amd_audio_addr=$(extract_pci_address "$amd_audio")
        echo -e "${yellow}Audio PCI Address:${no_color} $amd_audio_addr"
        echo -e "${yellow}Audio PCI ID:${no_color} $amd_audio_id"
        
        echo ""
        echo -e "${green}Kernel parameter for GRUB:${no_color}"
        echo "intel_iommu=on iommu=pt vfio-pci.ids=$amd_gpu_id,$amd_audio_id"
        
        echo ""
        echo -e "${green}PCI addresses for unbinding script:${no_color}"
        echo "GPU: $amd_pci_addr"
        echo "Audio: $amd_audio_addr"
    else
        echo ""
        echo -e "${green}Kernel parameter for GRUB:${no_color}"
        echo "intel_iommu=on iommu=pt vfio-pci.ids=$amd_gpu_id"
        
        echo ""
        echo -e "${green}PCI address for unbinding script:${no_color}"
        echo "GPU: $amd_pci_addr"
    fi
    GPU_PCI_ID="$amd_pci_addr"
    AUDIO_PCI_ID="$amd_audio_addr"
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
    echo "Make sure VT-d is enabled in BIOS and intel_iommu=on is in kernel parameters"
fi

echo ""

# Additional recommendations
# echo -e "${green}6. Recommendations...${no_color}"
# echo ""

# if [ -n "$intel_gpu" ] && [ -n "$nvidia_gpu" ]; then
#     echo -e "${green}✓ Perfect setup detected: Intel iGPU + NVIDIA dGPU${no_color}"
#     echo "  - Intel iGPU will handle host display"
#     echo "  - NVIDIA dGPU can be passed through to VM"
# elif [ -n "$intel_gpu" ] && [ -n "$amd_gpu" ]; then
#     echo -e "${green}✓ Good setup detected: Intel iGPU + AMD dGPU${no_color}"
#     echo "  - Intel iGPU will handle host display"
#     echo "  - AMD dGPU can be passed through to VM"
# elif [ -n "$nvidia_gpu" ] && [ -z "$intel_gpu" ]; then
#     echo -e "${yellow}⚠ Single NVIDIA GPU detected${no_color}"
#     echo "  - You'll need SSH or remote access when GPU is passed through"
#     echo "  - Consider enabling Intel iGPU in BIOS if available"
# else
#     echo -e "${yellow}⚠ Unusual GPU configuration detected${no_color}"
#     echo "  - Manual configuration may be required"
# fi

echo ""
echo -e "${green}Script completed! Use the information above to configure VFIO passthrough.${no_color}"


echo -e "${green}Create a script to switch the gpu between host and guests${no_color}"
SWITCH_SCRIPT="/usr/local/bin/gpu-switch.sh"

login_manager="sddm"

# Generate the script
cat << SWITCH_SCRIPT_EOF | sudo tee "$SWITCH_SCRIPT" > /dev/null
#!/bin/bash
login_manager="$login_manager"

case "\$1" in
    "vm")
        # Stop display manager and unload nvidia
        sudo systemctl stop "\$login_manager" || true
        sudo rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia
        echo "$GPU_PCI_ID" | sudo tee /sys/bus/pci/devices/$GPU_PCI_ID/driver/unbind
        echo "$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/devices/$AUDIO_PCI_ID/driver/unbind
        sudo modprobe vfio-pci
        echo "GPU switched to VM mode"
        ;;
    "host")
        # Reload nvidia and restart display manager
        sudo rmmod vfio-pci
        echo "$GPU_PCI_ID" | sudo tee /sys/bus/pci/drivers/nvidia/bind
        echo "$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/drivers/snd_hda_intel/bind
        sudo modprobe nvidia
        sudo systemctl start "\$login_manager" || true
        echo "GPU switched to host mode"
        ;;
esac
SWITCH_SCRIPT_EOF
sudo chmod +x "$SWITCH_SCRIPT"
