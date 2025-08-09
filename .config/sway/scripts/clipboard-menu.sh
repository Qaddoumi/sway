#!/bin/sh
ACTION=$(printf "Copy\nDelete\nClear" | wofi --dmenu --prompt "Clipboard action...")
SELECTION=$(cliphist list | wofi --dmenu --prompt "Search the clipboard...")

case "$ACTION" in
    "Copy") 
        echo "$SELECTION" | cliphist decode | wl-copy
        ;;
    "Delete") 
        echo "$SELECTION" | cliphist delete
        ;;
    "Clear")
        echo "$SELECTION" | rm -f ~/.cache/cliphist/db
        ;;
esac