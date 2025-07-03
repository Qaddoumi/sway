#!/bin/bash

set -euo pipefail

# to get a list of installed packages, you can use:
# pacman -Qqe
# or to get a list of all installed packages with their installation time and dependencies:
# grep "installed" /var/log/pacman.log

# Color codes
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
no_color='\033[0m' # rest the color to default

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo -e "${red}This script should not be run as root. Please run as a regular user with sudo privileges.${no_color}"
   exit 1
fi

backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        sudo cp "$file" "$file.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${green}Backed up $file${no_color}"
    fi
}

echo -e "${green} ******************* Sway Installation Script ******************* ${no_color}"

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Installing yay (Yet Another Yaourt)${no_color}"

sudo pacman -S --needed --noconfirm git base-devel go || true

install_yay() {
    git clone https://aur.archlinux.org/yay.git || true
    cd yay || true
    makepkg -si --noconfirm || true
    cd .. && rm -rf yay || true
    yay --version || true
}

if command -v yay &> /dev/null ; then
    echo "yay is already installed."
    CURRENT_VERSION=$(yay --version | head -1 | awk '{print $2}')
    echo "Current version: $CURRENT_VERSION"
    
    echo "Checking for latest version..."
    LATEST_VERSION=$(curl -s "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=yay" | grep -o '"Version":"[^"]*"' | cut -d'"' -f4 | head -1)
    echo "Latest version: $LATEST_VERSION"

    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        echo "yay is already up to date (version $CURRENT_VERSION)"
    elif printf '%s\n%s\n' "$LATEST_VERSION" "$CURRENT_VERSION" | sort -V | tail -n1 | grep -q "^$LATEST_VERSION$"; then
        echo "Update available: $CURRENT_VERSION -> $LATEST_VERSION"
        echo "Proceeding with update..."
        install_yay
    else
        echo "Current version is newer than or equal to latest available"
    fi
else
    echo "yay is not installed. Proceeding with installation..."
    install_yay
fi

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Installing Sway and related packages${no_color}"
sudo pacman -S --needed --noconfirm sway # Sway window manager
sudo pacman -S --needed --noconfirm waybar # Status bar for sway
sudo pacman -S --needed --noconfirm wofi # Application launcher
sudo pacman -S --needed --noconfirm dunst # Notification daemon
sudo pacman -S --needed --noconfirm kitty # Terminal emulator
sudo pacman -S --needed --noconfirm swayidle # Idle management for sway
sudo pacman -S --needed --noconfirm swaylock # Screen locker for sway
sudo pacman -S --needed --noconfirm xdg-desktop-portal xdg-desktop-portal-wlr # Portal for Wayland
sudo pacman -S --needed --noconfirm playerctl # Media player control
sudo pacman -S --needed --noconfirm pavucontrol # PulseAudio volume control
#sudo pacman -S --needed --noconfirm autotiling # Auto-tiling for sway
sudo pacman -S --needed --noconfirm htop # System monitor
sudo pacman -S --needed --noconfirm wget # Download utility
sudo pacman -S --needed --noconfirm nemo # File manager
sudo pacman -S --needed --noconfirm kanshi # Automatic Display manager for Wayland
sudo pacman -S --needed --noconfirm nano # Text editor
sudo pacman -S --needed --noconfirm neovim # Neovim text editor
sudo pacman -S --needed --noconfirm brightnessctl # Brightness control
sudo pacman -S --needed --noconfirm s-tui # Terminal UI for monitoring CPU
sudo pacman -S --needed --noconfirm gdu # Disk usage analyzer
sudo pacman -S --needed --noconfirm jq # JSON processor
sudo pacman -S --needed --noconfirm bc # Arbitrary precision calculator language
sudo pacman -S --needed --noconfirm fastfetch # Fast system information tool
sudo pacman -S --needed --noconfirm less # Pager program for viewing text files
#sudo pacman -S --needed --noconfirm flameshot # Screenshot tool

yay -S --needed --noconfirm google-chrome || true # Web browser
yay -S --needed --noconfirm visual-studio-code-bin || true # Visual Studio Code
yay -S --needed --noconfirm oh-my-posh || true # Theme engine for terminal

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Setting up environment variable for Electron apps so they lunch in wayland mode${no_color}"
ENV_FILE="/etc/environment"
if grep -q "ELECTRON_OZONE_PLATFORM_HINT" "$ENV_FILE"; then
    echo "ELECTRON_OZONE_PLATFORM_HINT already exists in $ENV_FILE"
else
    echo "Adding ELECTRON_OZONE_PLATFORM_HINT to $ENV_FILE..."
    echo "ELECTRON_OZONE_PLATFORM_HINT=wayland" | sudo tee -a "$ENV_FILE" > /dev/null || true
fi
echo -e "${green}You'll need to restart your session for this to take effect system-wide${no_color}"

# Check if .bashrc exists
BASHRC_FILE="$HOME/.bashrc"
if [ ! -f "$BASHRC_FILE" ]; then
    echo "Creating .bashrc file"
    touch "$BASHRC_FILE"
fi

# Check if the export line already exists
if grep -q "ELECTRON_OZONE_PLATFORM_HINT=wayland" "$BASHRC_FILE"; then
    echo "ELECTRON_OZONE_PLATFORM_HINT=wayland already exists in .bashrc"
else
    echo "Adding ELECTRON_OZONE_PLATFORM_HINT=wayland to .bashrc..."
    echo "" >> "$BASHRC_FILE"
    echo "# Enable Wayland for Electron apps" >> "$BASHRC_FILE"
    echo "ELECTRON_OZONE_PLATFORM_HINT=wayland" >> "$BASHRC_FILE"
    echo "Successfully added to .bashrc"
fi
source ~/.bashrc || true

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Installing fonts${no_color}"

sudo pacman -S --needed --noconfirm ttf-jetbrains-mono-nerd # Nerd font for JetBrains Mono
sudo pacman -S --needed --noconfirm noto-fonts-emoji # Emoji font

echo -e "${green}Refreshing font cache${no_color}"
fc-cache -fv

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Installing and configuring Qemu/Libvirt for virtualization${no_color}"
sudo pacman -S --needed --noconfirm qemu-full # Full QEMU package with all features
sudo pacman -S --needed --noconfirm qemu-img # QEMU disk image utility: provides create, convert, modify, and snapshot, offline disk images
sudo pacman -S --needed --noconfirm libvirt # Libvirt for managing virtualization: provides a unified interface for managing virtual machines
sudo pacman -S --needed --noconfirm virt-install # Tool for installing virtual machines: CLI tool to create guest VMs
sudo pacman -S --needed --noconfirm virt-manager # GUI for managing virtual machines: GUI tool to create and manage guest VMs
sudo pacman -S --needed --noconfirm virt-viewer # Viewer for virtual machines
sudo pacman -S --needed --noconfirm edk2-ovmf # UEFI firmware for virtual machines
sudo pacman -S --needed --noconfirm dnsmasq # DNS and DHCP server: lightweight DNS forwarder and DHCP server
sudo pacman -S --needed --noconfirm swtpm # Software TPM emulator
sudo pacman -S --needed --noconfirm guestfs-tools # Tools for managing guest file systems
sudo pacman -S --needed --noconfirm libosinfo # Library for managing OS information
sudo pacman -S --needed --noconfirm tuned # system tuning service for linux allows us to optimise the hypervisor for speed.
sudo pacman -S --needed --noconfirm spice-vdagent # SPICE agent for guest OS
sudo pacman -S --needed --noconfirm bridge-utils # Utilities for managing network bridges

echo -e "${green}Enabling and starting libvirtd service${no_color}"
sudo systemctl enable libvirtd || true

echo -e "${green}Adding current user to libvirt group${no_color}"
sudo usermod -aG libvirt $(whoami) || true
echo -e "${green}Adding libvirt-qemu user to input group${no_color}"
sudo usermod -aG input libvirt-qemu || true

echo -e "${green}Starting and autostarting the default network for libvirt${no_color}"
sudo virsh net-start default || true
sudo virsh net-autostart default || true

echo -e "${blue}==================================================\n==================================================${no_color}"

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

# Enhanced systemd-boot configuration function
configure_systemd_boot() {
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
        echo -e "${yellow}Please manually add '$IOMMU_PARAM iommu=pt' to your boot entry${no_color}"
        return 1
    fi
    
    # Find boot entries
    local boot_entries=($(sudo find "$entries_dir" -name "*.conf" 2>/dev/null))
    
    if [[ ${#boot_entries[@]} -eq 0 ]]; then
        echo -e "${red}No boot entries found in $entries_dir${no_color}"
        return 1
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
            sudo sed -i "/^options/ s/$/ $IOMMU_PARAM iommu=pt/" "$entry"
            echo -e "${green}Updated $(basename "$entry") with: $IOMMU_PARAM iommu=pt${no_color}"
        else
            # If no options line exists, add one
            echo "options $IOMMU_PARAM iommu=pt" | sudo tee -a "$entry" > /dev/null
            echo -e "${green}Added options line to $(basename "$entry") with: $IOMMU_PARAM iommu=pt${no_color}"
        fi
    done
    
    return 0
}

detect_bootloader
detection_result=$?

case $detection_result in
    0)
        # systemd-boot detected
        configure_systemd_boot
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
        sudo sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ $IOMMU_PARAM iommu=pt\"/" "$GRUB_CONFIG"

        echo -e "${green}Updated GRUB configuration with: $IOMMU_PARAM iommu=pt${no_color}"

        # Regenerate GRUB configuration
        echo -e "${green}Regenerating GRUB configuration...${no_color}"
        sudo grub-mkconfig -o /boot/grub/grub.cfg

        echo -e "${green}GRUB configuration updated successfully${no_color}"
        ;;
    2)
        # No bootloader detected
        echo -e "${red}Unable to detect bootloader (GRUB or systemd-boot)${no_color}"
        echo -e "${red}Please manually add '$IOMMU_PARAM iommu=pt' to your kernel parameters${no_color}"
        ;;
esac

# Load vfio modules
echo -e "${green}Loading VFIO kernel modules...${no_color}"
MODULES_LOAD_CONF="/etc/modules-load.d/vfio.conf"
if [[ ! -f "$MODULES_LOAD_CONF" ]]; then
    echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" | sudo tee "$MODULES_LOAD_CONF" > /dev/null
    echo -e "${green}Created $MODULES_LOAD_CONF with VFIO modules${no_color}"
else
    echo -e "${yellow}VFIO modules configuration already exists${no_color}"
fi

echo -e "${green}Create a script to check IOMMU groups after reboot${no_color}"
CHECK_SCRIPT="/usr/local/bin/check-iommu-groups"
cat << 'CHECK_SCRIPT_EOF' | sudo tee "$CHECK_SCRIPT" > /dev/null
#!/bin/bash
echo "IOMMU Groups:${no_color}"
echo "=============${no_color}"
for d in /sys/kernel/iommu_groups/*/devices/*; do
    n=${d#*/iommu_groups/*}; n=${n%%/*}
    printf 'IOMMU Group %s ' "$n"
    lspci -nns "${d##*/}"
done | sort -V
CHECK_SCRIPT_EOF

sudo chmod +x "$CHECK_SCRIPT"
echo -e "${green}Created IOMMU groups checker script at $CHECK_SCRIPT${no_color}"
echo -e "${green}IOMMU setup completed${no_color}"

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}adding user to necessary groups...${no_color}"

sudo usermod -aG video $USER || true
sudo usermod -aG audio $USER || true
sudo usermod -aG input $USER || true

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Cloning and setting up configuration files${no_color}"

if [ -d ~/sway ]; then
    rm -rf ~/sway
fi
if ! git clone --depth 1 https://github.com/Qaddoumi/sway.git ~/sway; then
    echo "Failed to clone repository" >&2
    exit 1
fi
rm -rf ~/.config/sway ~/.config/waybar ~/.config/wofi ~/.config/kitty ~/.config/dunst ~/.config/kanshi ~/.config/oh-my-posh ~/.config/fastfetch
mkdir -p ~/.config && cp -r ~/sway/.config/* ~/.config/
rm -rf ~/sway

echo -e "${green}Setting up permissions for configuration files${no_color}"
# TODO: give permission to run other scripts.
chmod +x ~/.config/waybar/scripts/*.sh || true
chmod +x ~/.config/sway/scripts/*.sh || true

# if ! grep -q 'export PATH="$PATH:$HOME/.local/bin"' ~/.bashrc; then
#     echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
# fi
if ! grep -q "source ~/.config/oh-my-posh/gmay.omp.json" ~/.bashrc; then
    echo 'eval "$(oh-my-posh init bash --config ~/.config/oh-my-posh/gmay.omp.json)"' >> ~/.bashrc || true
fi

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Installing and configuring ly (a lightweight display manager)${no_color}"

sudo pacman -S --needed --noconfirm cmatrix
sudo pacman -S --needed --noconfirm ly
sudo systemctl disable display-manager.service || true
sudo systemctl enable ly.service || true
# Edit the configuration file /etc/ly/config.ini
sudo sed -i 's/^animation = .*/animation = matrix/' /etc/ly/config.ini || true
echo -e "${blue}==================================================\n==================================================${no_color}"

# Final instructions
echo ""
echo -e "${green}Additional steps after reboot:${no_color}"
echo -e "1. Check IOMMU groups: sudo $CHECK_SCRIPT"
echo -e "2. Verify IOMMU is enabled: sudo dmesg | grep -i iommu"

echo -e "${yellow}REBOOT REQUIRED - Please reboot your system now!${no_color}"