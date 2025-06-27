#!/bin/bash

# Get current Hijri date using online API
get_hijri_date() {
    # Try multiple APIs for reliability
    local hijri_date
    
    # API 1: AlAdhan API
    hijri_date=$(curl -s --connect-timeout 5 "http://api.aladhan.com/v1/gToH/$(date +%d-%m-%Y)" | jq -r '.data.hijri.date' 2>/dev/null)
    
    if [[ "$hijri_date" != "null" && -n "$hijri_date" ]]; then
        echo "$hijri_date"
        return 0
    fi
    
    # API 2: IslamicFinder API
    hijri_date=$(curl -s --connect-timeout 5 "https://api.islamicfinder.org/v1/hijri/$(date +%Y-%m-%d)" | jq -r '.data.date' 2>/dev/null)
    
    if [[ "$hijri_date" != "null" && -n "$hijri_date" ]]; then
        echo "$hijri_date"
        return 0
    fi
    
    # Fallback: show error
    echo "N/A"
}

# Get Hijri date
HIJRI_DATE=$(get_hijri_date)

# Get regular time
REGULAR_TIME=$(date "+%I:%M %p")

# Output for Waybar
echo "{\"text\":\"$REGULAR_TIME\", \"tooltip\":\"Gregorian: $(date '+%d-%m-%Y')\\nHijri: $HIJRI_DATE\"}"
