#!/bin/bash


if [ -d ~/sway ]; then
    sudo rm -rf ~/sway
fi
if ! git clone --depth 1 https://github.com/Qaddoumi/sway.git ~/sway; then
    echo "Failed to clone repository" >&2
    exit 1
fi
sudo rm -rf ~/.config/sway ~/.config/waybar ~/.config/wofi ~/.config/kitty ~/.config/swaync ~/.config/kanshi ~/.config/oh-my-posh ~/.config/fastfetch ~/.config/mimeapps.list ~/.config/looking-glass ~/.config/gtk-3.0 ~/.config/gtk-4.0
sudo mkdir -p ~/.config && sudo cp -r ~/sway/.config/* ~/.config/
sudo rm -rf ~/sway

sudo chmod +x ~/.config/waybar/scripts/*.sh
sudo chmod +x ~/.config/sway/scripts/*.sh

swaymsg reload

# if ! grep -q 'export PATH="$PATH:$HOME/.local/bin"' ~/.bashrc; then
#     echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
# fi
if ! grep -q "source ~/.config/oh-my-posh/gmay.omp.json" ~/.bashrc; then
    echo 'eval "$(oh-my-posh init bash --config ~/.config/oh-my-posh/gmay.omp.json)"' >> ~/.bashrc
fi
