#!/bin/bash

set -euo pipefail

# Color codes
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
no_color='\033[0m' # rest the color to default

echo -e "${green} ******************* Sway Installation Script ******************* ${no_color}"

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Installing yay (Yet Another Yaourt)${no_color}"

sudo pacman -S --needed --noconfirm git base-devel go
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd .. && rm -rf yay
yay --version

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
#sudo pacman -S --needed --noconfirm flameshot # Screenshot tool

yay -S --needed --noconfirm google-chrome # Web browser
yay -S --needed --noconfirm visual-studio-code-bin # Visual Studio Code
yay -S --needed --noconfirm oh-my-posh # Theme engine for terminal

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Setting up environment variable for Electron apps so they lunch in wayland mode${no_color}"
ENV_FILE="/etc/environment"
if grep -q "ELECTRON_OZONE_PLATFORM_HINT" "$ENV_FILE"; then
    echo "ELECTRON_OZONE_PLATFORM_HINT already exists in $ENV_FILE"
else
    sudo echo "Adding ELECTRON_OZONE_PLATFORM_HINT to $ENV_FILE..."
    sudo echo "ELECTRON_OZONE_PLATFORM_HINT=wayland" >> "$ENV_FILE"
    sudo echo "Successfully added to $ENV_FILE"
fi
echo "${green}You'll need to restart your session for this to take effect system-wide${no_color}"

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}Installing fonts${no_color}"

sudo pacman -S --needed --noconfirm ttf-jetbrains-mono-nerd # Nerd font for JetBrains Mono
sudo pacman -S --needed --noconfirm noto-fonts-emoji # Emoji font

echo -e "${green}Refreshing font cache${no_color}"
fc-cache -fv

echo -e "${blue}==================================================\n==================================================${no_color}"

#echo -e "${green}Installing and configuring Qemu/Libvirt for virtualization${no_color}"
#sudo pacman -S --needed --noconfirm virt-manager qemu-desktop libvirt ebtables dnsmasq bridge-utils spice-vdagent

#echo -e "${green}Enabling and starting libvirtd service${no_color}"
#sudo systemctl enable --now libvirtd

#echo -e "${green}Adding current user to libvirt group${no_color}"
#sudo usermod -aG libvirt $(whoami)
#echo -e "${green}Adding libvirt-qemu user to input group${no_color}"
#sudo usermod -aG input libvirt-qemu

#echo -e "${green}Starting and autostarting the default network for libvirt${no_color}"
#sudo virsh net-start default
#sudo virsh net-autostart default

echo -e "${blue}==================================================\n==================================================${no_color}"

echo -e "${green}adding user to necessary groups...${no_color}"

sudo usermod -aG video $USER
sudo usermod -aG audio $USER
sudo usermod -aG input $USER

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
chmod +x ~/.config/waybar/scripts/*.sh
chmod +x ~/.config/sway/scripts/*.sh

# if ! grep -q 'export PATH="$PATH:$HOME/.local/bin"' ~/.bashrc; then
#     echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
# fi
if ! grep -q "source ~/.config/oh-my-posh/gmay.omp.json" ~/.bashrc; then
    echo 'eval "$(oh-my-posh init bash --config ~/.config/oh-my-posh/gmay.omp.json)"' >> ~/.bashrc
fi

echo -e "${blue}==================================================\n==================================================${no_color}"

# sddm
# sudo pacman -S --needed --noconfirm sddm qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg 
# if [ -d /usr/share/sddm/themes/sddm-astronaut-theme ]; then
#     sudo rm -rf /usr/share/sddm/themes/sddm-astronaut-theme
# fi
# sudo git clone -b master --depth 1 https://github.com/keyitdev/sddm-astronaut-theme.git /usr/share/sddm/themes/sddm-astronaut-theme
# sudo cp -r /usr/share/sddm/themes/sddm-astronaut-theme/Fonts/* /usr/share/fonts/
# echo -e "[Theme]\nCurrent=sddm-astronaut-theme" | sudo tee /etc/sddm.conf
# sudo mkdir -p /etc/sddm.conf.d
# echo -e "[General]\nInputMethod=qtvirtualkeyboard" | sudo tee /etc/sddm.conf.d/virtualkbd.conf
# current_sddm_theme=$(grep "ConfigFile=" /usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop | cut -d'=' -f2 | cut -d'/' -f2 | cut -d'.' -f1)
# sudo sed -i "s/ConfigFile=Themes\/${current_sddm_theme}.conf/ConfigFile=Themes\/purple_leaves.conf/" /usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop
# sudo systemctl disable display-manager.service
# sudo systemctl enable sddm

echo -e "${green}Installing and configuring ly (a lightweight display manager)${no_color}"

# ly
sudo pacman -S --needed --noconfirm ly
sudo pacman -S --needed --noconfirm cmatrix
sudo systemctl disable display-manager.service  2>/dev/null
sudo systemctl enable ly.service
# Edit the configuration file /etc/ly/config.ini
sudo sed -i 's/^animation = .*/animation = matrix/' /etc/ly/config.ini
echo -e "${blue}==================================================\n==================================================${no_color}"
