#!/bin/bash

# Get current time
time=$(date '+%H:%M:%S')

# Get kernel version
kernel=$(uname -r)

# All flower emojis
flowers=("🌸" "🌼" "🌻" "🌷" "🌺" "🥀")

# Pick a random flower
random_flower=${flowers[$RANDOM % ${#flowers[@]}]}

# Display output
echo -e "<span foreground='#ffb6c1'>Time:</span> <span foreground='white'>$time</span>"
echo -e "<span foreground='#ffb6c1'>Kernel:</span> <span foreground='white'>$kernel</span>"
echo -e "<span foreground='#ffb6c1'>Flowers:</span> <span foreground='white'>$random_flower</span>"
