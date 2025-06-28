#!/bin/bash

entries="⇠ Logout\n⏾ Suspend\n⏽ Hibernate\n↻ Reboot\n⏻ Shutdown\n🔒 Lock"

selected=$(echo -e $entries | wofi --dmenu --cache-file /dev/null --hide-scroll --width 250 --height 210 --location center --style ~/.config/wofi/powermenu.css --prompt "Power Menu")

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
    swaylock;;
esac