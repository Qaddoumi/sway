#!/bin/sh
ACTION=$(printf "Paste\nDelete" | wofi --dmenu --prompt "Clipboard action...")
SELECTION=$(cliphist list | wofi --dmenu --prompt "Search the clipboard...")

case "$ACTION" in
    "Paste") 
        echo "$SELECTION" | cliphist decode | wl-copy
        ;;
    "Delete") 
        echo "$SELECTION" | cliphist delete
        ;;
esac