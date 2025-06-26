#!/bin/bash

# Colors (adjust as needed)
RED="#FF5555"
GREEN="#50FA7B"
BLUE="#8BE9FD"
YELLOW="#F1FA8C"
WHITE="#F8F8F2"

    # Get system info
    TIME=$(date +"%H:%M:%S")
    UPTIME=$(uptime -p)
    MEM=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
    CPU=$(grep 'cpu ' /proc/stat | awk '{print ($2+$4)*100/($2+$4+$5)"%"}')

    # Format output with Pango
    TEXT="<span foreground='$BLUE' face='monospace'>󰥔 $TIME</span>   \
<span foreground='$GREEN' face='monospace'> $MEM</span>   \
<span foreground='$RED' face='monospace'> $CPU</span>   \
<span foreground='$YELLOW' face='monospace'>󰓾 $UPTIME</span>"

    # Pipe to nwg-wrapper
    echo "$TEXT"

