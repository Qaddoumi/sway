#!/bin/bash

# Simple Offline Hijri date calculator (approximate)
calculate_hijri() {
    # Get current date
    local greg_year=$(date +%Y)
    local greg_month=$(date +%m)
    local greg_day=$(date +%d)
    
    # Convert to Julian day number
    local a=$(( (14 - greg_month) / 12 ))
    local y=$(( greg_year - a ))
    local m=$(( greg_month + 12 * a - 3 ))
    local jd=$(( greg_day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 + 1721119 ))
    
    # Convert Julian day to Hijri (approximate calculation)
    local hijri_jd=$(( jd - 1948440 ))  # Hijri epoch offset
    local hijri_year=$(( (hijri_jd * 30) / 10631 + 1 ))
    local remaining_days=$(( hijri_jd - ((hijri_year - 1) * 10631) / 30 ))
    local hijri_month=1
    local hijri_day=$remaining_days
    
    # Approximate month calculation (simplified)
    if [ $remaining_days -gt 295 ]; then
        hijri_month=12
        hijri_day=$(( remaining_days - 295 ))
    elif [ $remaining_days -gt 266 ]; then
        hijri_month=11
        hijri_day=$(( remaining_days - 266 ))
    elif [ $remaining_days -gt 236 ]; then
        hijri_month=10
        hijri_day=$(( remaining_days - 236 ))
    elif [ $remaining_days -gt 207 ]; then
        hijri_month=9
        hijri_day=$(( remaining_days - 207 ))
    elif [ $remaining_days -gt 177 ]; then
        hijri_month=8
        hijri_day=$(( remaining_days - 177 ))
    elif [ $remaining_days -gt 148 ]; then
        hijri_month=7
        hijri_day=$(( remaining_days - 148 ))
    elif [ $remaining_days -gt 118 ]; then
        hijri_month=6
        hijri_day=$(( remaining_days - 118 ))
    elif [ $remaining_days -gt 89 ]; then
        hijri_month=5
        hijri_day=$(( remaining_days - 89 ))
    elif [ $remaining_days -gt 59 ]; then
        hijri_month=4
        hijri_day=$(( remaining_days - 59 ))
    elif [ $remaining_days -gt 30 ]; then
        hijri_month=3
        hijri_day=$(( remaining_days - 30 ))
    elif [ $remaining_days -gt 0 ]; then
        hijri_month=2
        hijri_day=$remaining_days
    else
        hijri_month=1
        hijri_day=1
    fi
    
    echo "$hijri_day/$hijri_month/$hijri_year"
}

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

# Get Hijri date (try API, fallback to offline)
HIJRI_DATE=$(get_hijri_date)
if [[ "$HIJRI_DATE" == "N/A" ]]; then
    HIJRI_DATE=$(calculate_hijri)
fi

# Get regular time
REGULAR_TIME=$(date "+%I:%M %p")

# Output for Waybar
echo "{\"text\":\"$REGULAR_TIME\", \"tooltip\":\"Gregorian: $(date '+%d-%m-%Y')\\nHijri:     $HIJRI_DATE\"}"
