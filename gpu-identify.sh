
#!/bin/bash

# GPU PCI ID Identifier Script for VFIO Passthrough
# This script identifies GPU PCI IDs and generates VFIO configuration

# Colors for better readability
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
no_color='\033[0m' # No Color

# Function to create backup files
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sudo cp "$file" "$file.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${green}Backed up $file${no_color}"
    else
        echo -e "${yellow}File $file does not exist, skipping backup${no_color}"
    fi
}

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
    local entries_dir=""
    local systemd_boot_detected=false
    local bootctl_output
    local esp_path
    local boot_entries
    
    # Check for GRUB first
    if [[ -f "/boot/grub/grub.cfg" ]] || sudo test -d "/boot/grub"; then
        echo -e "${green}GRUB bootloader detected${no_color}"
        return 1  # GRUB detected
    fi
    
    # Check for systemd-boot in multiple possible locations
    # Check common systemd-boot paths
    if [[ -f "/boot/loader/loader.conf" ]] || sudo test -d "/boot/loader/entries"; then
        echo -e "${green}systemd-boot detected at /boot/loader/${no_color}"
        systemd_boot_detected=true
    elif [[ -f "/boot/efi/loader/loader.conf" ]] || sudo test -d "/boot/efi/loader/entries"; then
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

nvidia_audio=""
amd_audio=""

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
        AUDIO_PCI_ID="$nvidia_audio_addr"
    fi
    
    GPU_PCI_ID="$nvidia_pci_addr"
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
        AUDIO_PCI_ID="$amd_audio_addr"
    fi
    
    GPU_PCI_ID="$amd_pci_addr"
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
                #exit 1
            fi
            
            # Find boot entries
            local boot_entries=($(sudo find "$entries_dir" -name "*.conf" 2>/dev/null))
            
            if [[ ${#boot_entries[@]} -eq 0 ]]; then
                echo -e "${red}No boot entries found in $entries_dir${no_color}"
                #exit 1
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
                #exit 1
            fi

            # Check if IOMMU parameter already exists
            if sudo grep "GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_CONFIG" | grep -q "$IOMMU_PARAM"; then
                echo -e "${yellow}IOMMU parameter already present in GRUB configuration${no_color}"
            else
                # Add IOMMU parameter to GRUB_CMDLINE_LINUX_DEFAULT
                sudo sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ $IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS\"/" "$GRUB_CONFIG"
                echo -e "${green}Updated GRUB configuration with: $IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS${no_color}"
            fi

            # Regenerate GRUB configuration
            echo -e "${green}Regenerating GRUB configuration...${no_color}"
            if sudo grub-mkconfig -o /boot/grub/grub.cfg; then
                echo -e "${green}GRUB configuration updated successfully${no_color}"
            else
                echo -e "${red}Failed to regenerate GRUB configuration${no_color}"
                #exit 1
            fi
            ;;
        2)
            # No bootloader detected
            echo -e "${red}Unable to detect bootloader (GRUB or systemd-boot)${no_color}"
            echo -e "${red}Please manually add '$IOMMU_PARAM iommu=pt vfio-pci.ids=$VFIO_IDS' to your kernel parameters${no_color}"
            #exit 1
            ;;
    esac
else
    echo -e "${red}No valid GPU configuration found for VFIO passthrough${no_color}"
    #exit 1
fi

echo ""
echo -e "${green}Creating script to check IOMMU groups after reboot...${no_color}"
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

echo ""
echo -e "${green}To verify VFIO binding after reboot:${no_color}"
echo -e "${green}lspci -nnk | grep -A 3 -E '(VGA|3D controller|Audio)'${no_color}"
echo ""
echo -e "${green}To monitor logs:${no_color}"
echo -e "${green}sudo journalctl -f${no_color}"
CHECK_SCRIPT_EOF

sudo chmod +x "$CHECK_SCRIPT"
echo -e "${green}Created IOMMU groups checker script at $CHECK_SCRIPT${no_color}"

login_manager="sddm"

SWITCH_SCRIPT="/usr/local/bin/gpu-switch.sh"
echo -e "${green}Creating GPU switch script at $SWITCH_SCRIPT${no_color}"

# Determine driver based on GPU type
case "$GPU_TYPE" in
    "nvidia")
        GPU_DRIVER="nvidia"
        AUDIO_DRIVER="snd_hda_intel"
        ;;
    "amdgpu")
        GPU_DRIVER="amdgpu"
        AUDIO_DRIVER="snd_hda_intel"  # AMD audio often uses Intel HDA controller
        ;;
    *)
        echo -e "${red}No supported GPU driver detected for switching${no_color}"
        exit 1
        ;;
esac

# Generate the GPU switch script
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
        echo -e "\${green}Switching GPU to VM mode...\${no_color}"
        # Stop display manager
        if ! sudo systemctl stop "\$LOGIN_MANAGER"; then
            echo -e "\${red}Failed to stop display manager\${no_color}"
            exit 1
        fi
        
        # Unload host GPU drivers
        sudo modprobe -r \$GPU_DRIVER 2>/dev/null || true
        sudo modprobe -r nvidia_drm nvidia_modeset nvidia_uvm 2>/dev/null || true
        
        # Unbind devices from host drivers
        if [[ -n "\$GPU_PCI_ID" && -d "/sys/bus/pci/devices/\$GPU_PCI_ID" ]]; then
            echo "\$GPU_PCI_ID" | sudo tee /sys/bus/pci/devices/\$GPU_PCI_ID/driver/unbind 2>/dev/null || true
        fi
        if [[ -n "\$AUDIO_PCI_ID" && -d "/sys/bus/pci/devices/\$AUDIO_PCI_ID" ]]; then
            echo "\$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/devices/\$AUDIO_PCI_ID/driver/unbind 2>/dev/null || true
        fi
        
        # Bind to vfio-pci
        if ! sudo modprobe vfio-pci; then
            echo -e "\${red}Failed to load vfio-pci\${no_color}"
            exit 1
        fi
        
        if [[ -n "\$GPU_PCI_ID" && -d "/sys/bus/pci/devices/\$GPU_PCI_ID" ]]; then
            echo "\$GPU_PCI_ID" | sudo tee /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
        fi
        if [[ -n "\$AUDIO_PCI_ID" && -d "/sys/bus/pci/devices/\$AUDIO_PCI_ID" ]]; then
            echo "\$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
        fi
        
        echo -e "\${green}GPU switched to VM mode\${no_color}"
        ;;
    "host")
        echo -e "\${green}Switching GPU to host mode...\${no_color}"
        # Unbind from vfio-pci
        if [[ -n "\$GPU_PCI_ID" && -d "/sys/bus/pci/devices/\$GPU_PCI_ID" ]]; then
            echo "\$GPU_PCI_ID" | sudo tee /sys/bus/pci/devices/\$GPU_PCI_ID/driver/unbind 2>/dev/null || true
        fi
        if [[ -n "\$AUDIO_PCI_ID" && -d "/sys/bus/pci/devices/\$AUDIO_PCI_ID" ]]; then
            echo "\$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/devices/\$AUDIO_PCI_ID/driver/unbind 2>/dev/null || true
        fi
        
        # Clear driver overrides
        if [[ -n "\$GPU_PCI_ID" && -d "/sys/bus/pci/devices/\$GPU_PCI_ID" ]]; then
            echo "" | sudo tee /sys/bus/pci/devices/\$GPU_PCI_ID/driver_override 2>/dev/null || true
        fi
        if [[ -n "\$AUDIO_PCI_ID" && -d "/sys/bus/pci/devices/\$AUDIO_PCI_ID" ]]; then
            echo "" | sudo tee /sys/bus/pci/devices/\$AUDIO_PCI_ID/driver_override 2>/dev/null || true
        fi
        
        # Load host GPU driver
        if ! sudo modprobe \$GPU_DRIVER; then
            echo -e "\${red}Failed to load \$GPU_DRIVER\${no_color}"
            exit 1
        fi
        
        # Bind to host drivers
        if [[ -n "\$GPU_PCI_ID" && -d "/sys/bus/pci/devices/\$GPU_PCI_ID" ]]; then
            echo "\$GPU_PCI_ID" | sudo tee /sys/bus/pci/drivers/\$GPU_DRIVER/bind 2>/dev/null || true
        fi
        if [[ -n "\$AUDIO_PCI_ID" && -d "/sys/bus/pci/devices/\$AUDIO_PCI_ID" ]]; then
            echo "\$AUDIO_PCI_ID" | sudo tee /sys/bus/pci/drivers/\$AUDIO_DRIVER/bind 2>/dev/null || true
        fi
        
        # Restart display manager
        if ! sudo systemctl start "\$LOGIN_MANAGER"; then
            echo -e "\${red}Failed to start display manager\${no_color}"
            exit 1
        fi
        
        echo -e "\${green}GPU switched to host mode\${no_color}"
        ;;
    *)
        echo -e "\${red}Usage: \$0 {vm|host}\${no_color}"
        echo -e "\${yellow}  vm   - Switch GPU to VM mode (bind to vfio-pci)\${no_color}"
        echo -e "\${yellow}  host - Switch GPU to host mode (bind to host driver)\${no_color}"
        exit 1
        ;;
esac
SWITCH_SCRIPT_EOF

sudo chmod +x "$SWITCH_SCRIPT"
echo -e "${green}Created GPU switch script at $SWITCH_SCRIPT${no_color}"

echo ""
# Load vfio modules
echo -e "${green}Loading VFIO kernel modules...${no_color}"
MODULES_LOAD_CONF="/etc/modules-load.d/vfio.conf"
if [[ ! -f "$MODULES_LOAD_CONF" ]]; then
    echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" | sudo tee "$MODULES_LOAD_CONF" > /dev/null
    echo -e "${green}Created $MODULES_LOAD_CONF with VFIO modules${no_color}"
else
    echo -e "${yellow}VFIO modules configuration already exists${no_color}"
fi
echo ""
echo -e "${green}Update initramfs to include VFIO modules:${no_color}"

# Configuration file
MKINITCPIO_CONF="/etc/mkinitcpio.conf"
# VFIO modules to add
VFIO_MODULES="vfio vfio_iommu_type1 vfio_virqfd vfio_pci"

echo -e "${green}Starting VFIO modules configuration for $MKINITCPIO_CONF...${no_color}"

# Check if mkinitcpio.conf exists
if [[ ! -f "$MKINITCPIO_CONF" ]]; then
    echo -e "${red}Error: $MKINITCPIO_CONF not found${no_color}"
else 
    # Backup the configuration file
    backup_file "$MKINITCPIO_CONF"

    # Check if MODULES line exists
    if ! sudo grep -q "^MODULES=" "$MKINITCPIO_CONF"; then
        echo -e "${yellow}No MODULES line found in $MKINITCPIO_CONF${no_color}"
        echo -e "${green}Adding MODULES line with VFIO modules${no_color}"
        echo "MODULES=($VFIO_MODULES)" | sudo tee -a "$MKINITCPIO_CONF" > /dev/null
    else
        # Get current MODULES line
        current_modules=$(sudo grep "^MODULES=" "$MKINITCPIO_CONF" | sed 's/MODULES=//; s/[()]//g')

        # Check if all VFIO modules are already present
        all_present=true
        for module in $VFIO_MODULES; do
            if ! echo "$current_modules" | grep -qw "$module"; then
                all_present=false
                break
            fi
        done

        if [[ "$all_present" == true ]]; then
            echo -e "${yellow}All VFIO modules ($VFIO_MODULES) are already present in $MKINITCPIO_CONF${no_color}"
        else
            echo -e "${green}Adding missing VFIO modules to $MKINITCPIO_CONF${no_color}"
            # Remove existing MODULES line
            sudo sed -i "/^MODULES=/d" "$MKINITCPIO_CONF"
            # Add new MODULES line with all modules
            new_modules="$current_modules $VFIO_MODULES"
            # Remove duplicates and extra spaces
            new_modules=$(echo "$new_modules" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')
            echo "MODULES=($new_modules)" | sudo tee -a "$MKINITCPIO_CONF" > /dev/null
            echo -e "${green}Updated MODULES line with: $new_modules${no_color}"
        fi
    fi

    echo -e "${green}VFIO modules configuration completed${no_color}"
    echo -e "${yellow}Please reboot your system to apply the changes.${no_color}"

fi

echo -e "${green}Blacklist host GPU drivers to prevent automatic binding:${no_color}"
echo "   Create /etc/modprobe.d/vfio.conf"

if [ "$GPU_TYPE" = "nvidia" ]; then
    echo -e "blacklist nvidia\nblacklist nvidia_drm\nblacklist nvidia_modeset\nblacklist nouveau" | sudo tee /etc/modprobe.d/vfio.conf
elif [ "$GPU_TYPE" = "amdgpu" ]; then
    echo -e "blacklist amdgpu\nblacklist radeon" | sudo tee /etc/modprobe.d/vfio.conf
fi

# Update initramfs
echo -e "${green}Updating initramfs...${no_color}"
if sudo mkinitcpio -P; then
    echo -e "${green}Initramfs updated successfully${no_color}"
else
    echo -e "${red}Failed to update initramfs${no_color}"
fi

echo ""
LIBVIRTHOOK_SCRIPT="/etc/libvirt/hooks/qemu"
echo -e "${green}Create libvirt hook to automate GPU switching, at $LIBVIRTHOOK_SCRIPT${no_color}"

cat << LIBVIRTHOOK_SCRIPT_EOF | sudo tee "$LIBVIRTHOOK_SCRIPT" > /dev/null
#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
no_color='\033[0m' # No Color

GUEST_NAME="your-vm-name"
COMMAND="\$1"
EVENT="\$2"
if [ "\$COMMAND" = "\$GUEST_NAME" ]; then
    if [ "\$EVENT" = "prepare" ]; then
        $SWITCH_SCRIPT vm
    elif [ "\$EVENT" = "release" ]; then
        $SWITCH_SCRIPT host
    fi
fi

LIBVIRTHOOK_SCRIPT_EOF
sudo chmod +x $LIBVIRTHOOK_SCRIPT
sudo systemctl restart libvirtd || true

#TODO: the bottom line.
echo -e "${green}Additional Notes\n . Some laptops require additional ACPI patches for proper GPU switching${no_color}"
echo ""
