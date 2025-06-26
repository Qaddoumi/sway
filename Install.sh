#!/bin/bash


sudo pacman -S --needed --noconfirm git base-devel 
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd .. && rm -rf yay
yay --version


sudo pacman -S --needed --noconfirm sway # Sway window manager
sudo pacman -S --needed --noconfirm waybar # Status bar for sway
sudo pacman -S --needed --noconfirm wofi # Application launcher
sudo pacman -S --needed --noconfirm mako # Notification daemon (mako-notifier in apt)
sudo pacman -S --needed --noconfirm kitty # Terminal emulator
sudo pacman -S --needed --noconfirm swayidle # Idle management for sway
sudo pacman -S --needed --noconfirm swaylock # Screen locker for sway
sudo pacman -S --needed --noconfirm xdg-desktop-portal xdg-desktop-portal-wlr # Portal for Wayland
sudo pacman -S --needed --noconfirm ttf-jetbrains-mono-nerd # Nerd font for JetBrains Mono
sudo pacman -S --needed --noconfirm playerctl # Media player control
sudo pacman -S --needed --noconfirm autotiling # Auto-tiling for sway
sudo pacman -S --needed --noconfirm nemo # File manager
sudo pacman -S --needed --noconfirm kanshi # Automatic Display manager for Wayland
sudo pacman -S --needed --noconfirm neovim # Text editor
sudo pacman -S --needed --noconfirm code # Visual Studio Code
sudo pacman -S --needed --noconfirm brightnessctl # Brightness control
sudo pacman -S --needed --noconfirm s-tui # Terminal UI for monitoring CPU
sudo pacman -S --needed --noconfirm gdu # Disk usage analyzer
#sudo pacman -S --needed --noconfirm flameshot # Screenshot tool

yay -S --needed --noconfirm google-chrome # Web browser


fc-cache -fv


sudo usermod -aG video $USER
sudo usermod -aG audio $USER
sudo usermod -aG input $USER


if [ -d ~/sway ]; then
    rm -rf ~/sway
fi
if ! git clone --depth 1 https://github.com/Qaddoumi/sway.git ~/sway; then
    echo "Failed to clone repository" >&2
    exit 1
fi
rm -rf ~/.config/sway ~/.config/waybar ~/.config/wofi ~/.config/kitty ~/.config/mako ~/.config/kanshi
mkdir -p ~/.config && cp -r ~/sway/.config/* ~/.config/
rm -rf ~/sway


# sddm
sudo pacman -S --needed --noconfirm sddm qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg 
if [ -d /usr/share/sddm/themes/sddm-astronaut-theme ]; then
    sudo rm -rf /usr/share/sddm/themes/sddm-astronaut-theme
fi
sudo git clone -b master --depth 1 https://github.com/keyitdev/sddm-astronaut-theme.git /usr/share/sddm/themes/sddm-astronaut-theme
sudo cp -r /usr/share/sddm/themes/sddm-astronaut-theme/Fonts/* /usr/share/fonts/
echo -e "[Theme]\nCurrent=sddm-astronaut-theme" | sudo tee /etc/sddm.conf
sudo mkdir -p /etc/sddm.conf.d
echo -e "[General]\nInputMethod=qtvirtualkeyboard" | sudo tee /etc/sddm.conf.d/virtualkbd.conf
current_sddm_theme=$(grep "ConfigFile=" /usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop | cut -d'=' -f2 | cut -d'/' -f2 | cut -d'.' -f1)
sudo sed -i "s/ConfigFile=Themes\/${current_sddm_theme}.conf/ConfigFile=Themes\/purple_leaves.conf/" /usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop
sudo systemctl disable display-manager.service
sudo systemctl enable sddm

