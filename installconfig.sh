#!/bin/bash


if [ -d ~/sway ]; then
    rm -rf ~/sway
fi
if ! git clone --depth 1 https://github.com/Qaddoumi/sway.git ~/sway; then
    echo "Failed to clone repository" >&2
    exit 1
fi
rm -rf ~/.config/sway ~/.config/waybar ~/.config/wofi ~/.config/kitty ~/.config/dunst ~/.config/kanshi ~/.config/oh-my-posh
mkdir -p ~/.config && cp -r ~/sway/.config/* ~/.config/
rm -rf ~/sway

chmod +x ~/.config/waybar/scripts/*.sh
chmod +x ~/.config/sway/scripts/*.sh

swaymsg reload

# if ! grep -q 'export PATH="$PATH:$HOME/.local/bin"' ~/.bashrc; then
#     echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
# fi
if ! grep -q "source ~/.config/oh-my-posh/gmay.omp.json" ~/.bashrc; then
    echo 'eval "$(oh-my-posh init bash --config ~/.config/oh-my-posh/gmay.omp.json)"' >> ~/.bashrc
fi
