#!/bin/bash

# entries="⇠ Logout\n⏾ Suspend\n⏽ Hibernate\n↻ Reboot\n⏻ Shutdown\n🔒 Lock"
entries="⇠ Logout\n⏽ Hibernate\n↻ Reboot\n⏻ Shutdown\n🔒 Lock"

selected=$(echo -e $entries | wofi --dmenu --cache-file /dev/null --hide-scroll --width 250 --height 300 --location center --style ~/.config/wofi/powermenu.css --prompt "Power Menu")

case $selected in
  "⇠ Logout")
    swaymsg exit;;
  "⏾ Suspend")
    systemctl suspend;;
  "⏽ Hibernate")
    systemctl hibernate;;
  "↻ Reboot")
    systemctl reboot;;
  "⏻ Shutdown")
    systemctl poweroff;;
  "🔒 Lock")
    swaylock \
        --color 2d353b \
        --inside-color 3a454a \
        --inside-clear-color 5c6a72 \
        --inside-ver-color 5a524c \
        --inside-wrong-color 543a3a \
        --ring-color 7a8478 \
        --ring-clear-color a7c080 \
        --ring-ver-color dbbc7f \
        --ring-wrong-color e67e80 \
        --key-hl-color d699b6 \
        --bs-hl-color e69875 \
        --separator-color 2d353b \
        --text-color d3c6aa \
        --text-clear-color d3c6aa \
        --text-ver-color d3c6aa \
        --text-wrong-color d3c6aa \
        --indicator-radius 100 \
        --indicator-thickness 10 \
        --font "JetBrainsMono Nerd Font";;
esac