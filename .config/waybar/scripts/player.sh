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

tooltip=$( echo -e "State : $state\\nPlayer : $player_name\\nArtist : $artist_name\\nTitle : $title_name\\n*******************************\\nVolume : $volume\\nMute : $mute\\n*******************************\\non-click : play-pause\\non-click-right : toggle mute/unmute\\non-scroll-up : increase volume\\non-scroll-down : decrease volume\\non-click-middle : open pavucontrol\\non-double-click: play next\\non-double-click-right: play previous" )

echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"$state\"}"