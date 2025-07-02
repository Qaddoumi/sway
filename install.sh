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
git clone https://aur.archlinux.org/yay.git || true
cd yay || true
makepkg -si --noconfirm || true
cd .. && rm -rf yay || true
yay --version || true

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
sudo pacman -S --needed --noconfirm nemo # File manager
sudo pacman -S --needed --noconfirm kanshi # Automatic Display manager for Wayland
sudo pacman -S --needed --noconfirm neovim # Text editor
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
    sudo echo "Adding ELECTRON_OZONE_PLATFORM_HINT to $ENV_FILE..." || true
    sudo echo "ELECTRON_OZONE_PLATFORM_HINT=wayland" >> "$ENV_FILE" || true
    sudo echo "Successfully added to $ENV_FILE" || true
fi
echo "${green}You'll need to restart your session for this to take effect system-wide${no_color}"

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
sudo systemctl enable --now libvirtd || true

echo -e "${green}Adding current user to libvirt group${no_color}"
sudo usermod -aG libvirt $(whoami) || true
echo -e "${green}Adding libvirt-qemu user to input group${no_color}"
sudo usermod -aG input libvirt-qemu || true

echo -e "${green}Starting and autostarting the default network for libvirt${no_color}"
sudo virsh net-start default || true
sudo virsh net-autostart default || true

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
if dmesg | grep -q "IOMMU enabled"; then
    echo -e "${yellow}IOMMU appears to already be enabled${no_color}"
else
    echo -e "${green}IOMMU not currently enabled, proceeding with setup...${no_color}"
fi

echo -e "${green}Detecting bootloader...${no_color}"
if [[ -f "/boot/grub/grub.cfg" ]] || [[ -d "/boot/grub" ]]; then
    echo -e "${green}GRUB bootloader detected${no_color}"
    echo -e "${green}Configuring GRUB bootloader...${no_color}"
    
    GRUB_CONFIG="/etc/default/grub"
    backup_file "$GRUB_CONFIG"
    
    # Check if GRUB_CMDLINE_LINUX_DEFAULT exists
    if ! grep -q "GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_CONFIG"; then
        echo -e "${red}GRUB_CMDLINE_LINUX_DEFAULT not found in $GRUB_CONFIG${no_color}"
        exit 1
    fi
    
    # Check if IOMMU parameter already exists
    if grep "GRUB_CMDLINE_LINUX_DEFAULT" "$GRUB_CONFIG" | grep -q "$IOMMU_PARAM"; then
        echo -e "${yellow}IOMMU parameter already present in GRUB configuration${no_color}"
        exit 0
    fi
    
    # Add IOMMU parameter to GRUB_CMDLINE_LINUX_DEFAULT
    sudo sed -i "/GRUB_CMDLINE_LINUX_DEFAULT=/ s/\"$/ $IOMMU_PARAM iommu=pt\"/" "$GRUB_CONFIG"
    
    echo -e "${green}Updated GRUB configuration with: $IOMMU_PARAM iommu=pt${no_color}"
    
    # Regenerate GRUB configuration
    echo -e "${green}Regenerating GRUB configuration...${no_color}"
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    
    echo -e "${green}GRUB configuration updated successfully${no_color}"
elif [[ -d "/boot/loader" ]] && [[ -f "/boot/loader/loader.conf" ]]; then
    echo -e "${green}systemd-boot detected${no_color}"
    echo -e "${green}Configuring systemd-boot...${no_color}"
    
    # Find the default boot entry
    BOOT_ENTRIES_DIR="/boot/loader/entries"
    
    if [[ ! -d "$BOOT_ENTRIES_DIR" ]]; then
        echo -e "${red}systemd-boot entries directory not found: $BOOT_ENTRIES_DIR${no_color}"
        exit 1
    fi
    
    # Find the current default entry or the most recent one
    DEFAULT_ENTRY=$(find "$BOOT_ENTRIES_DIR" -name "*.conf" | head -1)
    
    if [[ -z "$DEFAULT_ENTRY" ]]; then
        echo -e "${red}No boot entries found in $BOOT_ENTRIES_DIR${no_color}"
        exit 1
    fi
    
    echo -e "${green}Found boot entry: $DEFAULT_ENTRY${no_color}"
    backup_file "$DEFAULT_ENTRY"
    
    # Check if IOMMU parameter already exists
    if grep -q "$IOMMU_PARAM" "$DEFAULT_ENTRY"; then
        echo -e "${yellow}IOMMU parameter already present in systemd-boot configuration${no_color}"
        exit 0
    fi
    
    # Add IOMMU parameter to the options line
    if grep -q "^options" "$DEFAULT_ENTRY"; then
        sudo sed -i "/^options/ s/$/ $IOMMU_PARAM iommu=pt/" "$DEFAULT_ENTRY"
    else
        # If no options line exists, add one
        echo "options $IOMMU_PARAM iommu=pt" | sudo tee -a "$DEFAULT_ENTRY" > /dev/null
    fi
    
    echo -e "${green}Updated systemd-boot entry with: $IOMMU_PARAM iommu=pt${no_color}"
else
    echo -e "${red}Unable to detect bootloader (GRUB or systemd-boot)${no_color}"
    echo -e "${red}Please manually add '$IOMMU_PARAM iommu=pt' to your kernel parameters${no_color}"
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

echo -e "${green}CCreate a script to check IOMMU groups after reboot${no_color}"
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

echo -e "${green}IOMMU setup completed successfully!${no_color}"

echo -e "${green}After reboot, you can check IOMMU groups with: sudo $CHECK_SCRIPT${no_color}"
echo -e "${green}You can also verify IOMMU is enabled with: dmesg | grep -i iommu${no_color}"

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

# Check if .bashrc exists
BASHRC_FILE="$HOME/.bashrc"
if [ ! -f "$BASHRC_FILE" ]; then
    echo "Creating .bashrc file"
    touch "$BASHRC_FILE"
fi
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
echo "1. Check IOMMU groups: sudo $CHECK_SCRIPT${no_color}"
echo "2. Verify IOMMU is enabled: dmesg | grep -i iommu${no_color}"

echo -e "${yellow}REBOOT REQUIRED - Please reboot your system now!${no_color}"