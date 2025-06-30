#!/bin/bash

# This script is used by Waybar to display the current media player status.
# Enhanced version that detects VM audio and multiple sinks

if ! command -v playerctl &> /dev/null; then
    echo ""
    exit 0
fi
if ! command -v pactl &> /dev/null; then
    echo ""
    exit 0
fi

# Function to get volume from any active sink
get_active_volume() {
    # Get all sinks and their volumes
    local max_volume=0
    local active_sink=""
    local is_muted=false
    
    # Check default sink first
    local default_volume=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '[0-9]+%' | head -1 | tr -d '%')
    local default_mute=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -q "yes" && echo "true" || echo "false")
    
    if [ -n "$default_volume" ] && [ "$default_volume" -gt 0 ]; then
        max_volume=$default_volume
        active_sink="@DEFAULT_SINK@"
        is_muted=$default_mute
    fi
    
    # Check all other sinks for active audio
    while IFS= read -r sink; do
        if [ -n "$sink" ] && [ "$sink" != "@DEFAULT_SINK@" ]; then
            local sink_volume=$(pactl get-sink-volume "$sink" 2>/dev/null | grep -oP '[0-9]+%' | head -1 | tr -d '%')
            local sink_mute=$(pactl get-sink-mute "$sink" 2>/dev/null | grep -q "yes" && echo "true" || echo "false")
            
            # Check if this sink is currently playing audio
            local sink_inputs=$(pactl list sink-inputs 2>/dev/null | grep -A 10 "Sink Input" | grep -B 10 "Sink: $sink" | grep -c "State: RUNNING")
            
            if [ -n "$sink_volume" ] && [ "$sink_volume" -gt "$max_volume" ] && [ "$sink_inputs" -gt 0 ]; then
                max_volume=$sink_volume
                active_sink=$sink
                is_muted=$sink_mute
            fi
        fi
    done < <(pactl list short sinks 2>/dev/null | awk '{print $2}')
    
    echo "$max_volume|$active_sink|$is_muted"
}

# Function to detect if VM audio is playing
detect_vm_audio() {
    # Look for VM-related processes that might be playing audio
    local vm_processes=("qemu" "VirtualBox" "vmware" "kvm" "libvirt" "virt-manager")
    local vm_audio_detected=false
    
    for process in "${vm_processes[@]}"; do
        if pgrep -f "$process" > /dev/null 2>&1; then
            # Check if this process has audio streams
            local audio_streams=$(pactl list sink-inputs 2>/dev/null | grep -i "$process" | wc -l)
            if [ "$audio_streams" -gt 0 ]; then
                vm_audio_detected=true
                break
            fi
        fi
    done
    
    echo $vm_audio_detected
}

# Get volume information from active sinks
volume_info=$(get_active_volume)
volume_percent=$(echo "$volume_info" | cut -d'|' -f1)
active_sink=$(echo "$volume_info" | cut -d'|' -f2)
is_muted=$(echo "$volume_info" | cut -d'|' -f3)

vm_audio=$(detect_vm_audio)

# Set volume display
if [ "$is_muted" = "true" ]; then
    mute=true
    text="󰖁 muted"
elif [ "$volume_percent" -eq 0 ]; then
    text="󰕿 0%"
else
    mute=false
    # Choose icon based on volume level
    if [ "$volume_percent" -le 30 ]; then
        icon=""
    elif [ "$volume_percent" -le 70 ]; then
        icon=""
    else
        icon=" "
    fi
    text="$icon ${volume_percent}%"
fi

# Add VM indicator if VM audio detected
if [ "$vm_audio" = "true" ]; then
    text="$text 󰍹"
fi

state=$(playerctl status 2>/dev/null) # Paused, Playing, Stopped
player_name=$(playerctl metadata --format '{{playerName}}' 2>/dev/null)
artist_name=$(playerctl metadata --format '{{artist}}' 2>/dev/null)
title_name=$(playerctl metadata --format '{{markup_escape(title)}}' 2>/dev/null)

if [ -z "$player_name" ] || [ -z "$artist_name" ] || [ -z "$title_name" ]; then
    tooltip="No media playing\\n"
    class="none"
else
    tooltip="State : $state\\n"
    tooltip+="Player : $player_name\\n"
    tooltip+="Artist : $artist_name\\n"
    tooltip+="Title : $title_name\\n"
    class="$state"
fi

tooltip+="*******************************\\n"
tooltip+="Volume : ${volume_percent}%\\n"
tooltip+="Mute : $mute\\n"
tooltip+="Active Sink : $active_sink\\n"
if [ "$vm_audio" = "true" ]; then
    tooltip+="VM Audio : Detected 󰍹\\n"
fi
tooltip+="*******************************\\n"
tooltip+="on-click : 󰐎 play-pause\\n"
tooltip+="on-click-right : toggle mute/unmute\\n"
tooltip+="on-scroll-up : 󰝝 increase volume\\n"
tooltip+="on-scroll-down : 󰝞 decrease volume\\n"
tooltip+="on-click-middle : open pavucontrol\\n"
tooltip+="on-double-click: 󰒭 play next\\n"
tooltip+="on-double-click-right: 󰒮 play previous"

echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"$class\"}"