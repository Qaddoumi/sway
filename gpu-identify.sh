#!/bin/bash

# GPU PCI ID Identifier Script for VFIO Passthrough
# This script identifies GPU PCI IDs and generates VFIO configuration

# Colors for better readability
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
no_color='\033[0m' # No Color

echo -e "${green}Starting IOMMU setup for KVM virtualization...${no_color}"

echo -e "${green}Checking CPU vendor and IOMMU support...${no_color}"
CPU_VENDOR=$(lscpu | grep "Vendor ID" | awk '{print $3}')
echo -e "${green}CPU Vendor: $CPU_VENDOR${no_color}"

# Determine IOMMU parameter based on CPU vendor
echo -e "${green}Determining IOMMU parameter based on CPU vendor${no_color}"
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
    IOMMU_PARAM="intel_iommu=on"
    echo -e "${green}Intel CPU detected - will use intel_iommu=on${no_color}"
elif [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    IOMMU_PARAM="amd_iommu=on"
    echo -e "${green}AMD CPU detected - will use amd_iommu=on${no_color}"
else
    echo -e "${red}Unknown CPU vendor: $CPU_VENDOR${no_color}"
    echo -e "${red}Please manually add the appropriate IOMMU parameter for your CPU${no_color}"
    exit 1
fi

# Check if IOMMU is already enabled
echo -e "${green}Checking current IOMMU status...${no_color}"
if sudo dmesg | grep -q "IOMMU enabled"; then
    echo -e "${yellow}IOMMU appears to already be enabled${no_color}"
else
    echo -e "${green}IOMMU not currently enabled${no_color}"
fi

echo -e "${green}Detecting bootloader...${no_color}"
detect_bootloader() {
    # Check for GRUB first
    if [[ -f "/boot/grub/grub.cfg" ]] || sudo test -d "/boot/grub"; then
        echo -e "${green}GRUB bootloader detected${no_color}"
        return 1  # GRUB detected
    fi
    
    # Check for systemd-boot in multiple possible locations
    local systemd_boot_detected=false
    
    # Check common systemd-boot paths
    if [[ -f "/boot/loader/loader.conf" ]] || sudo test -d "/boot/loader/entries"; then
        echo -e "${green}systemd-boot detected at /boot/loader/${no_color}"
        systemd_boot_detected=true
    elif [[ -f "/boot/efi/loader/entries" ]] || sudo test -d "/boot/efi/loader/loader.conf"; then
        echo -e "${green}systemd-boot detected at /boot/efi/loader/${no_color}"
        systemd_boot_detected=true
    elif [[ -f "/efi/loader/loader.conf" ]] || sudo test -d "/efi/loader/entries"; then
        echo -e "${green}systemd-boot detected at /efi/loader/${no_color}"
        systemd_boot_detected=true
    fi
    
    # Additional checks for systemd-boot
    if [[ "$systemd_boot_detected" == false ]]; then
        # Check if bootctl is available and can list entries
        if command -v bootctl &> /dev/null; then
            if bootctl list &>/dev/null; then
                echo -e "${green}systemd-boot detected via bootctl${no_color}"
                systemd_boot_detected=true
            fi
        fi
        
        # Check for ESP mount point
        if findmnt -t vfat /boot &>/dev/null || findmnt -t vfat /boot/efi &>/dev/null || findmnt -t vfat /efi &>/dev/null; then
            echo -e "${green}EFI System Partition found, likely systemd-boot${no_color}"
            systemd_boot_detected=true
        fi
    fi
    
    if [[ "$systemd_boot_detected" == true ]]; then
        return 0  # systemd-boot detected
    else
        return 2  # No bootloader detected
    fi
}

echo -e "${green}=== GPU PCI ID Identifier for VFIO Passthrough ===${no_color}"
echo ""

# Function to extract PCI ID (vendor:device) from lspci output
extract_pci_id() {
    echo "$1" | grep -o '[0-9a-f]\{4\}:[0-9a-f]\{4\}' | tail -1
}

# Function to extract PCI address
extract_pci_address() {
    echo "$1" | cut -d' ' -f1
}

echo -e "${green}Detecting all GPUs in system...${no_color}"
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
echo -e "${green}Categorizing GPUs...${no_color}"
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
echo -e "${green}Finding associated audio devices...${no_color}"
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
echo -e "${green}VFIO Configuration for GPU Passthrough...${no_color}"
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
        
        VFIO_IDS="$VFIO_IDS,$nvidia_audio_id"
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
        
        VFIO_IDS="$VFIO_IDS,$amd_audio_id"
    fi
    
    GPU_PCI_ID="$amd_pci_addr"
    AUDIO_PCI_ID="$amd_audio_addr"
fi

detect_bootloader
detection_result=$?

if [ -n "$VFIO_IDS" ]; then
    case $detection_result in
        0)
            # systemd-boot detected
            echo -e "${green}Configuring systemd-boot...${no_color}"
            
            # Find the correct entries directory
            local entries_dir=""
            for path in "/boot/efi/loader/entries" "/boot/loader/entries" "/efi/loader/entries"; do
                echo -e "${blue}Checking path: $path${no_color}"
                if sudo test -d "$path"; then
                    entries_dir="$path"
                    echo -e "${green}Found entries directory: $entries_dir${no_color}"
                    break
                fi
            done
            
            if [[ -z "$entries_dir" ]]; then
                echo -e "${red}systemd-boot entries directory not found${no_color}"
                echo -e "${yellow}Attempting to find entries using bootctl...${no_color}"
                
                # Try to get boot entries using bootctl
                if command -v bootctl &> /dev/null; then
                    local bootctl_output=$(bootctl list 2>/dev/null)
                    if [[ -n "$bootctl_output" ]]; then
                        echo -e "${green}Found boot entries via bootctl:${no_color}"
                        echo "$bootctl_output"
                        
                        # Get the ESP path from bootctl
                        local esp_path=$(bootctl status 2>/dev/null | grep "ESP:" | awk '{print $2}')
                        if [[ -n "$esp_path" ]]; then
                            entries_dir="$esp_path/loader/entries"
                            echo -e "${green}Using ESP path: $entries_dir${no_color}"
                        fi
                    fi
                fi
            fi
            
            if [[ -z "$entries_dir" ]] || ! sudo test -d "$entries_dir"; then
                echo -e "${red}Could not locate systemd-boot entries directory${no_color}"
                echo -e "${yellow}Please manually add '$IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS' to your boot entry${no_color}"
                #return 1
            fi
            
            # Find boot entries
            local boot_entries=($(sudo find "$entries_dir" -name "*.conf" 2>/dev/null))
            
            if [[ ${#boot_entries[@]} -eq 0 ]]; then
                echo -e "${red}No boot entries found in $entries_dir${no_color}"
                #return 1
            fi
            
            echo -e "${green}Found ${#boot_entries[@]} boot entries:${no_color}"
            for entry in "${boot_entries[@]}"; do
                echo "  - $(basename "$entry")"
            done
            
            # Process each boot entry
            for entry in "${boot_entries[@]}"; do
                echo -e "${green}Processing boot entry: $(basename "$entry")${no_color}"
                backup_file "$entry"
                
                # Check if IOMMU parameter already exists
                if sudo grep -q "$IOMMU_PARAM" "$entry"; then
                    echo -e "${yellow}IOMMU parameter already present in $(basename "$entry")${no_color}"
                    continue
                fi
                
                # Add IOMMU parameter to the options line
                if sudo grep -q "^options" "$entry"; then
                    sudo sed -i "/^options/ s/$/ $IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS/" "$entry"
                    echo -e "${green}Updated $(basename "$entry") with: $IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS${no_color}"
                else
                    # If no options line exists, add one
                    echo "options $IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS" | sudo tee -a "$entry" > /dev/null
                    echo -e "${green}Added options line to $(basename "$entry") with: $IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS${no_color}"
                fi
            done
            ;;
        1)
            echo -e "${green}Configuring GRUB bootloader...${no_color}"

            GRUB_CONFIG="/etc/default/grub"
            backup_file "$GRUB_CONFIG"

            # Check if GRUB_CMDLINE_LINUX_DEFAULT exists
            if ! sudo grep -q "GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_CONFIG"; then
                echo -e "${red}GRUB_CMDLINE_LINUX_DEFAULT not found in $GRUB_CONFIG${no_color}"
            fi

            # Check if IOMMU parameter already exists
            if sudo grep "GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_CONFIG" | grep -q "$IOMMU_PARAM"; then
                echo -e "${yellow}IOMMU parameter already present in GRUB configuration${no_color}"
            fi

            # Add IOMMU parameter to GRUB_CMDLINE_LINUX_DEFAULT
            sudo sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ $IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS\"/" "$GRUB_CONFIG"

            echo -e "${green}Updated GRUB configuration with: $IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS${no_color}"

            # Regenerate GRUB configuration
            echo -e "${green}Regenerating GRUB configuration...${no_color}"
            sudo grub-mkconfig -o /boot/grub/grub.cfg

            echo -e "${green}GRUB configuration updated successfully${no_color}"
            ;;
        2)
            # No bootloader detected
            echo -e "${red}Unable to detect bootloader (GRUB or systemd-boot)${no_color}"
            echo -e "${red}Please manually add '$IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS' to your kernel parameters${no_color}"
            ;;
    esac
else
    echo -e "${red}No valid GPU configuration found for VFIO passthrough${no_color}"
    #return
fi

# Load vfio modules
echo -e "${green}Loading VFIO kernel modules...${no_color}"
MODULES_LOAD_CONF="/etc/modules-load.d/vfio.conf"
if [[ ! -f "$MODULES_LOAD_CONF" ]]; then
    echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" | sudo tee "$MODULES_LOAD_CONF" > /dev/null
    echo -e "${green}Created $MODULES_LOAD_CONF with VFIO modules${no_color}"
else
    echo -e "${yellow}VFIO modules configuration already exists${no_color}"
fi
# TODO: VFIO Configuration
# Create VFIO module loading:
# sudo nano /etc/mkinitcpio.conf
# Add to MODULES:
# MODULES=(vfio vfio_iommu_type1 vfio_virqfd vfio_pci)
# Regenerate initramfs:
# sudo mkinitcpio -P
echo ""

echo -e "${green}Create a script to check IOMMU groups after reboot${no_color}"
CHECK_SCRIPT="/usr/local/bin/check-iommu-groups"
cat << 'CHECK_SCRIPT_EOF' | sudo tee "$CHECK_SCRIPT" > /dev/null
#!/bin/bash

# Colors for better readability
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
no_color='\033[0m' # No Color

echo -e "${green}IOMMU Group Information...${no_color}"
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
fi
echo -e "${green}Verify VFIO binding:${no_color}"
echo -e "${green}lspci -nnk -d $VFIO_IDS${no_color}"
echo -e "${green}Monitor logs:${no_color}"
echo -e "${green}sudo journalctl -f${no_color}"
CHECK_SCRIPT_EOF

sudo chmod +x "$CHECK_SCRIPT"
echo -e "${green}Created IOMMU groups checker script at $CHECK_SCRIPT${no_color}"

SWITCH_SCRIPT="/usr/local/bin/gpu-switch.sh"
echo -e "${green}Creating GPU switch script at $SWITCH_SCRIPT${no_color}"

login_manager="sddm"

# Determine driver based on GPU type
case "$GPU_TYPE" in
    "nvidia")
        GPU_DRIVER="nvidia"
        AUDIO_DRIVER="snd_hda_intel"
        ;;
    "amdgpu")
        GPU_DRIVER="amdgpu"
        AUDIO_DRIVER="snd_hda_intel" # TODO: Shouldn't this be snd_hda_amd ?
        ;;
    *)
        echo -e "${red}No supported GPU driver detected for switching${no_color}"
        exit 1
        ;;
esac

# Generate the script
cat << SWITCH_SCRIPT_EOF | sudo tee "$SWITCH_SCRIPT" > /dev/null
#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
no_color='\033[0m' # No Color

# GPU Switch Script for VFIO Passthrough
# Switches GPU between host and VM

GPU_PCI_ID="$GPU_PCI_ID"
AUDIO_PCI_ID="$AUDIO_PCI_ID"
GPU_DRIVER="$GPU_DRIVER"
AUDIO_DRIVER="$AUDIO_DRIVER"
LOGIN_MANAGER="$login_manager"

case "\$1" in
    "vm")
        echo -e "${green}Switching GPU to VM mode...${no_color}"
        # Stop display manager
        sudo systemctl stop "\$LOGIN_MANAGER" || { echo -e "${red}Failed to stop display manager${no_color}"; exit 1; }
        
        # Unload host GPU drivers
        sudo modprobe -r \$GPU_DRIVER 2>/dev/null || true
        sudo modprobe -r nvidia_drm nvidia_modeset nvidia_uvm 2>/dev/null || true
        
        # Unbind devices from host drivers
        [ -n "\$GPU_PCI_ID" ] && echo "\$GPU_PCI_ID" | sudo tee /sys/bus/pci/devices/\$GPU_PCI_ID/driver/unbind 2>/dev/null || true
        [ -n "\$AUDIO_PCI_ID" ] && echo "\$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/devices/\$AUDIO_PCI_ID/driver/unbind 2>/dev/null || true
        
        # Bind to vfio-pci
        sudo modprobe vfio-pci || { echo -e "${red}Failed to load vfio-pci${no_color}"; exit 1; }
        [ -n "\$GPU_PCI_ID" ] && echo "\$GPU_PCI_ID" | sudo tee /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
        [ -n "\$AUDIO_PCI_ID" ] && echo "\$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
        
        echo -e "${green}GPU switched to VM mode${no_color}"
        ;;
    "host")
        echo -e "${green}Switching GPU to host mode...${no_color}"
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
        sudo modprobe \$GPU_DRIVER || { echo -e "${red}Failed to load \$GPU_DRIVER${no_color}"; exit 1; }
        
        # Restart display manager
        sudo systemctl start "\$LOGIN_MANAGER" || { echo -e "${red}Failed to start display manager${no_color}"; exit 1; }
        
        echo -e "${green}GPU switched to host mode${no_color}"
        ;;
    *)
        echo -e "${red}Usage: \$0 {vm|host}${no_color}"
        exit 1
        ;;
esac
SWITCH_SCRIPT_EOF

sudo chmod +x "$SWITCH_SCRIPT"
echo -e "${green}Created GPU switch script at $SWITCH_SCRIPT${no_color}"
#TODO: the bottom line.
echo -e "${green}Additional Notes\n . Some laptops require additional ACPI patches for proper GPU switching${no_color}"
echo ""

# Recommendations
echo -e "${green}7. Next Steps...${no_color}"
echo ""
echo "1. Ensure VFIO modules are loaded at boot:"
echo "   Edit /etc/mkinitcpio.conf and add to MODULES:"
echo "   MODULES=(... vfio vfio_iommu_type1 vfio_virqfd vfio_pci ...)"
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