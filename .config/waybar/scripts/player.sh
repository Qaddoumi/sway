#!/bin/bash

# This script is used by Waybar to display the current media player status.
# It uses playerctl to get the metadata of the currently playing media.
# If no media is playing, it returns an empty string.
if ! command -v playerctl &> /dev/null; then
    echo ""
    exit 0
fi
if ! command -v pactl &> /dev/null; then
    echo ""
    exit 0
fi

volume=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '[0-9]+%' | head -1)
if pactl get-sink-mute @DEFAULT_SINK@ | grep -q "yes"; then
    mute=true
    text=" muted"
else
    mute=false
    text=" $volume"
fi

state=$(playerctl status 2>/dev/null) # Paused, Playing, Stopped
player_name=$(playerctl metadata --format '{{playerName}}' 2>/dev/null)
artist_name=$(playerctl metadata --format '{{artist}}' 2>/dev/null)
title_name=$(playerctl metadata --format '{{markup_escape(title)}}' 2>/dev/null)

if [ -z "$player_name" ] || [ -z "$artist_name" ] || [ -z "$title_name" ]; then
    tooltip="No media playing\\n"
    class="none"
else
    tooltip="State  : $state\\nPlayer : $player_name\\n"
    tooltip+="Artist : $artist_name\\n"
    tooltip+="Title : $title_name\\n"
    class="$state"
fi

tooltip+="*******************************\\n"
tooltip+="Volume : $volume\\n"
tooltip+="Mute : $mute\\n"
tooltip+="*******************************\\n"
tooltip+="on-click : play-pause\\n"
tooltip+="on-click-right : toggle mute/unmute\\n"
tooltip+="on-scroll-up : increase volume\\n"
tooltip+="on-scroll-down : decrease volume\\n"
tooltip+="on-click-middle : open pavucontrol\\n"
tooltip+="on-double-click: play next\\n"
tooltip+="on-double-click-right: play previous"

echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"$class\"}"