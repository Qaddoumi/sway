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

# Accept login_manager as a command-line argument, default to "sddm" if not provided
login_manager="${1:-sddm}"
if [[ $# -ge 1 ]]; then
    echo -e "${green}Login manager argument provided: $login_manager${no_color}"
else
    echo -e "${yellow}No login manager argument provided. Using default: $login_manager${no_color}"
fi

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
sudo pacman -S --needed --noconfirm mpv # video player
sudo pacman -S --needed --noconfirm celluloid # frontend for mpv
sudo pacman -S --needed --noconfirm imv # image viewer
#sudo pacman -S --needed --noconfirm flameshot # Screenshot tool

yay -S --needed --noconfirm google-chrome || true # Web browser
yay -S --needed --noconfirm visual-studio-code-bin || true # Visual Studio Code
yay -S --needed --noconfirm oh-my-posh || true # Theme engine for terminal

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Setting up environment variable for Electron apps so they lunch in wayland mode${no_color}"
ENV_FILE="/etc/environment"
if grep -q "ELECTRON_OZONE_PLATFORM_HINT" "$ENV_FILE"; then
    echo "${green}ELECTRON_OZONE_PLATFORM_HINT already exists in $ENV_FILE${no_color}"
else
    echo -e "${green}Adding ELECTRON_OZONE_PLATFORM_HINT to $ENV_FILE...${no_color}"
    echo "ELECTRON_OZONE_PLATFORM_HINT=wayland" | sudo tee -a "$ENV_FILE" > /dev/null || true
fi
echo -e "${yellow}You'll need to restart your session for this to take effect system-wide${no_color}"

# Check if .bashrc exists
BASHRC_FILE="$HOME/.bashrc"
if [ ! -f "$BASHRC_FILE" ]; then
    echo -e "${green}Creating .bashrc file${no_color}"
    touch "$BASHRC_FILE"
fi

# Check if the export line already exists
if grep -q "ELECTRON_OZONE_PLATFORM_HINT=wayland" "$BASHRC_FILE"; then
    echo -e "${green}ELECTRON_OZONE_PLATFORM_HINT=wayland already exists in .bashrc${no_color}"
else
    echo -e "${green}Adding ELECTRON_OZONE_PLATFORM_HINT=wayland to .bashrc...${no_color}"
    echo "" >> "$BASHRC_FILE"
    echo "# Enable Wayland for Electron apps" >> "$BASHRC_FILE"
    echo "ELECTRON_OZONE_PLATFORM_HINT=wayland" >> "$BASHRC_FILE"
    echo -e "${green}Successfully added to .bashrc${no_color}"
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
sudo pacman -S --needed --noconfirm linux-headers # for vfio modules

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
echo "IOMMU Groups:"
echo "============="
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

echo -e "${green}Nested Virtualization Setup${no_color}"
echo -e "${green}Detecting CPU type and enabling nested virtualization${no_color}"

enable_nested_virtualization(){

    echo -e "${green}Detecting CPU vendor...${no_color}"
    local cpu_type=""
    local cpu_vendor
    cpu_vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | cut -d: -f2 | tr -d ' ')
    case "$cpu_vendor" in
        "GenuineIntel")
            cpu_type="intel"
            ;;
        "AuthenticAMD")
            cpu_type="amd"
            ;;
        *)
            echo -e "${red}Unknown CPU vendor: $cpu_vendor${no_color}"
            echo -e "${red}Supported vendors: Intel, AMD${no_color}"
            return 1
            ;;
    esac
    echo -e "${green}Detected CPU: $(echo "$cpu_type" | tr '[:lower:]' '[:upper:]')${no_color}"

    echo -e "${green}Checking KVM modules...${no_color}"
    if ! lsmod | grep -q "^kvm "; then
        echo -e "${red}KVM module is not loaded${no_color}"
        echo -e "${red}Please install KVM first: sudo pacman -S qemu-full${no_color}"
        return 1
    fi
    local kvm_module=""
    case "$cpu_type" in
        "intel")
            kvm_module="kvm_intel"
            ;;
        "amd")
            kvm_module="kvm_amd"
            ;;
    esac
    if ! lsmod | grep -q "^$kvm_module "; then
        echo -e "${red}$kvm_module module is not loaded${no_color}"
        echo -e "${green}Loading $kvm_module module...${no_color}"
        sudo modprobe "$kvm_module"
    fi
    echo -e "${green}KVM modules are loaded${no_color}"

    check_nested_status() {
        local cpu_type=$1
        echo -e "${green}Checking current nested virtualization status...${no_color}"
        local nested_file=""
        case "$cpu_type" in
            "intel")
                nested_file="/sys/module/kvm_intel/parameters/nested"
                ;;
            "amd")
                nested_file="/sys/module/kvm_amd/parameters/nested"
                ;;
        esac

        if [[ -f "$nested_file" ]]; then
            local status
            status=$(cat "$nested_file")
            case "$status" in
                "Y"|"1")
                    echo -e "${green}Nested virtualization is already enabled, but continuing with requested action...${no_color}"
                    ;;
                "N"|"0")
                    echo -e "${yellow}Nested virtualization is currently disabled${no_color}"
                    ;;
                *)
                    echo -e "${yellow}Unknown nested virtualization status: $status${no_color}"
                    ;;
            esac
        else
            echo -e "${yellow}Cannot determine nested virtualization status${no_color}"
        fi
    }
    check_nested_status "$cpu_type"

    echo -e "${green}Enabling nested virtualization for current session...${no_color}"
    case "$cpu_type" in
        "intel")
            sudo modprobe -r kvm_intel
            sudo modprobe kvm_intel nested=1
            ;;
        "amd")
            sudo modprobe -r kvm_amd
            sudo modprobe kvm_amd nested=1
            ;;
    esac
    echo -e "${green}Nested virtualization enabled for current session${no_color}"

    echo -e "${green}Enabling persistent nested virtualization...${no_color}"
    local conf_file=""
    local module_name=""
    case "$cpu_type" in
        "intel")
            conf_file="/etc/modprobe.d/kvm-intel.conf"
            module_name="kvm_intel"
            ;;
        "amd")
            conf_file="/etc/modprobe.d/kvm-amd.conf"
            module_name="kvm_amd"
            ;;
    esac
    echo -e "${green}Check if the configuration file exists${no_color}"
    if [[ -f "$conf_file" ]] && grep -q "nested=1" "$conf_file"; then
        echo -e "${green}Persistent nested virtualization is already configured${no_color}"
    else
        echo "options $module_name nested=1" | sudo tee "$conf_file"
        echo -e "${green}Persistent nested virtualization configuration created: $conf_file${no_color}"
    fi

    echo -e "${green}Verifying nested virtualization...${no_color}"
    check_nested_status "$cpu_type"

    echo -e "${green}Nested virtualization setup completed${no_color}"
    echo -e "${green}Note: Persistent configuration will take effect after the next reboot${no_color}"
    echo -e "${green}or when the KVM modules are reloaded.${no_color}"
}

echo -e "${green}Checking virtualization support...${no_color}"
if ! grep -q -E "(vmx|svm)" /proc/cpuinfo; then
    echo -e "${yellow}CPU does not support virtualization (VT-x/AMD-V)${no_color}"
    echo -e "${yellow}Please enable virtualization in your BIOS/UEFI settings${no_color}"
else
    echo -e "${green}CPU supports virtualization${no_color}"
    enable_nested_virtualization
fi

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}KVM ACL Setup Sets up ACL permissions for the libvirt images directory${no_color}"
# Default KVM images directory
KVM_IMAGES_DIR="/var/lib/libvirt/images"
target_user="$USER"
backup_file="/tmp/kvm_acl_backup_$(date +%Y%m%d_%H%M%S).txt"

kvm_acl_setup() {

    echo -e "${green}Checking if ACL tools are installed...${no_color}"
    if ! command -v getfacl &> /dev/null; then
        echo -e "${red}getfacl command not found. ACL tools are not installed.${no_color}"
        echo -e "${green}Install ACL tools:${no_color}"
        echo -e "${green}  Ubuntu/Debian: sudo apt install acl${no_color}"
        echo -e "${green}  CentOS/RHEL: sudo yum install acl${no_color}"
        echo -e "${green}  Fedora: sudo dnf install acl${no_color}"
        return
    fi
    if ! command -v setfacl &> /dev/null; then
        echo -e "${red}setfacl command not found. ACL tools are not installed.${no_color}"
        echo -e "${green}Install ACL tools first.${no_color}"
        return
    fi
    echo -e "${green}ACL tools are installed${no_color}"

    echo -e "${green}Checking if directory exists: $KVM_IMAGES_DIR${no_color}"
    if [[ ! -d "$KVM_IMAGES_DIR" ]]; then
        echo -e "${red}Directory does not exist: $KVM_IMAGES_DIR${no_color}"
        echo -e "${green}Please install libvirt first or create the directory manually.${no_color}"
        return
    fi
    echo -e "${green}Directory exists: $KVM_IMAGES_DIR${no_color}"

    echo -e "${green}Checking ACL support for filesystem...${no_color}"
    # Try to read ACL - if it fails, ACL might not be supported
    if ! sudo getfacl "$KVM_IMAGES_DIR" &>/dev/null; then
        echo -e "${red}ACL is not supported on this filesystem${no_color}"
        echo -e "${green}Make sure the filesystem is mounted with ACL support${no_color}"
        echo -e "${green}For ext4: mount -o remount,acl /mount/point${no_color}"
        return
    fi
    echo -e "${green}Filesystem supports ACL${no_color}"

    echo -e "${green}Current ACL permissions for $KVM_IMAGES_DIR:${no_color}"
    echo "----------------------------------------"
    sudo getfacl "$KVM_IMAGES_DIR" 2>/dev/null || {
        echo -e "${red}Failed to read ACL permissions${no_color}"
        return
    }
    echo "----------------------------------------"

    echo -e "${green}Backing up current ACL permissions to: $backup_file${no_color}"
    if sudo getfacl -R "$KVM_IMAGES_DIR" > "$backup_file" 2>/dev/null; then
        echo -e "${green}ACL permissions backed up to: $backup_file${no_color}"
        echo "$backup_file"
    else
        echo -e "${yellow}Failed to backup ACL permissions, continuing anyway...${no_color}"
        echo ""
    fi

    echo -e "${green}Setting up ACL permissions for user: $target_user${no_color}"
    
    if ! id "$target_user" &>/dev/null; then
        echo -e "${red}User does not exist: $target_user${no_color}"
        return
    fi

    echo -e "${green}Removing existing ACL permissions from $KVM_IMAGES_DIR...${no_color}"
    if sudo setfacl -R -b "$KVM_IMAGES_DIR" 2>/dev/null; then
        echo -e "${green}Existing ACL permissions removed${no_color}"
    else
        echo -e "${red}Failed to remove existing ACL permissions${no_color}"
        return
    fi

    echo -e "${green}Granting permissions to user: $target_user${no_color}"
    if sudo setfacl -R -m "u:${target_user}:rwX" "$KVM_IMAGES_DIR" 2>/dev/null; then
        echo -e "${green}Granted rwX permissions to user: $target_user${no_color}"
    else
        echo -e "${red}Failed to grant permissions to user: $target_user${no_color}"
        return
    fi

    echo -e "${green}Setting default ACL for new files/directories...${no_color}"
    if sudo setfacl -m "d:u:${target_user}:rwx" "$KVM_IMAGES_DIR" 2>/dev/null; then
        echo -e "${green}Default ACL set for user: $target_user${no_color}"
    else
        echo -e "${red}Failed to set default ACL for user: $target_user${no_color}"
        return
    fi

    echo -e "${green}Verifying ACL setup...${no_color}"
    # Check if user has the expected permissions
    local acl_output
    acl_output=$(sudo getfacl "$KVM_IMAGES_DIR" 2>/dev/null)
    if echo "$acl_output" | grep -q "user:$target_user:rwx"; then
        echo -e "${green}User ACL permissions verified${no_color}"
    else
        echo -e "${red}User ACL permissions not found${no_color}"
        echo -e "${red}ACL setup verification failed!${no_color}"
        if [[ -n "$backup_file" ]]; then
            echo -e "${green}You can restore from backup: $backup_file${no_color}"
        fi
        return
    fi
    if echo "$acl_output" | grep -q "default:user:$target_user:rwx"; then
        echo -e "${green}Default ACL permissions verified${no_color}"
    else
        echo -e "${red}Default ACL permissions not found${no_color}"
        echo -e "${red}ACL setup verification failed!${no_color}"
        if [[ -n "$backup_file" ]]; then
            echo -e "${green}You can restore from backup: $backup_file${no_color}"
        fi
        return
    fi
    echo -e "${green}ACL setup completed successfully!${no_color}"

    echo -e "${green}Testing ACL permissions...${no_color}"
    # Test file creation
    local test_file="$KVM_IMAGES_DIR/acl_test_file"
    local test_dir="$KVM_IMAGES_DIR/acl_test_dir"
    # Create test file
    if touch "$test_file" 2>/dev/null; then
        echo -e "${green}Successfully created test file${no_color}"
        rm -f "$test_file"
    else
        echo -e "${red}Failed to create test file${no_color}"
        echo -e "${red}ACL permissions test failed!${no_color}"
        return 1
    fi
    # Create test directory
    if mkdir "$test_dir" 2>/dev/null; then
        echo -e "${green}Successfully created test directory${no_color}"
        rmdir "$test_dir"
    else
        echo -e "${red}Failed to create test directory${no_color}"
        echo -e "${red}ACL permissions test failed!${no_color}"
        return 1
    fi
    echo -e "${green}ACL permissions test passed!${no_color}"

    echo -e "${green}Final ACL permissions for $KVM_IMAGES_DIR:${no_color}"
    echo "========================================"
    sudo getfacl "$KVM_IMAGES_DIR" 2>/dev/null || {
        echo -e "${red}Failed to read final ACL permissions${no_color}"
        return
    }

}

echo -e "${green}Target directory: $KVM_IMAGES_DIR${no_color}"
echo -e "${green}Target user: $target_user${no_color}"

kvm_acl_setup

echo -e "${green}KVM ACL setup completed${no_color}"
echo -e "${green}New files and directories should inherit proper permissions.${no_color}"
if [[ -n "$backup_file" ]]; then
    echo -e "${green}Backup file: $backup_file${no_color}"
fi

echo -e "${blue}==================================================\n==================================================${no_color}"

#TODO: Add AMD SEV Support
#TODO: Optimise Host with TuneD

echo -e "${blue}==================================================\n==================================================${no_color}"



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
rm -rf ~/.config/sway ~/.config/waybar ~/.config/wofi ~/.config/kitty ~/.config/dunst ~/.config/kanshi ~/.config/oh-my-posh ~/.config/fastfetch ~/.config/mimeapps.list
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

if [[ "$login_manager" == "ly" ]]; then
    echo -e "${green}Installing and configuring ly (a lightweight display manager)${no_color}"

    sudo pacman -S --needed --noconfirm cmatrix
    sudo pacman -S --needed --noconfirm ly
    sudo systemctl disable display-manager.service || true
    sudo systemctl enable ly.service || true
    # Edit the configuration file /etc/ly/config.ini to use matrix for animation
    sudo sed -i 's/^animation = .*/animation = matrix/' /etc/ly/config.ini || true
elif [[ "$login_manager" == "sddm" ]]; then
    echo -e "${green}Installing and configuring SDDM (Simple Desktop Display Manager)${no_color}"

    sudo pacman -S --needed --noconfirm sddm
    sudo systemctl disable display-manager.service || true
    sudo systemctl enable sddm.service || true
    # # Edit the configuration file /etc/sddm.conf to set the default session to sway
    # if ! grep -q "Session=sway" /etc/sddm.conf; then
    #     echo -e "${green}Setting default session to sway in /etc/sddm.conf${no_color}"
    #     echo -e "[General]\nInputMethod=\n\n[Autologin]\nUser=$USER\nSession=sway" | sudo tee /etc/sddm.conf > /dev/null || true
    # else
    #     echo -e "${yellow}Default session is already set to sway in /etc/sddm.conf${no_color}"
    # fi
    echo -e "${green}Setting up my Hacker theme for SDDM${no_color}"
    bash <(curl -sL https://raw.githubusercontent.com/Qaddoumi/sddm-hacker-theme/main/install.sh)
else
    echo -e "${red}Unsupported login manager: $login_manager${no_color}"
fi


echo -e "${blue}==================================================\n==================================================${no_color}"

# Final instructions
echo ""
echo -e "${green}Additional steps after reboot:${no_color}"
echo -e "1. Check IOMMU groups: sudo $CHECK_SCRIPT"
echo -e "2. Verify IOMMU is enabled: sudo dmesg | grep -i iommu"

echo -e "${yellow}REBOOT REQUIRED - Please reboot your system now!${no_color}"
echo -e "${blue}==================================================\n==================================================${no_color}"
