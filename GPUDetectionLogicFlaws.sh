#!/bin/bash

# Fix: GPU Detection Logic Flaws
# This script provides robust GPU detection and handling for multiple GPU scenarios

# Colors for output
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
no_color='\033[0m'

# Arrays to store GPU information
declare -a NVIDIA_GPUS
declare -a AMD_GPUS
declare -a INTEL_GPUS
declare -a NVIDIA_AUDIO
declare -a AMD_AUDIO
declare -a INTEL_AUDIO

# Function to extract PCI ID (vendor:device) from lspci output
extract_pci_id() {
    echo "$1" | grep -o '[0-9a-f]\{4\}:[0-9a-f]\{4\}' | tail -1
}

# Function to extract PCI address
extract_pci_address() {
    echo "$1" | cut -d' ' -f1
}

# Function to detect and categorize all GPUs
detect_all_gpus() {
    echo -e "${green}Detecting all GPUs in the system...${no_color}"
    
    # Clear arrays
    NVIDIA_GPUS=()
    AMD_GPUS=()
    INTEL_GPUS=()
    NVIDIA_AUDIO=()
    AMD_AUDIO=()
    INTEL_AUDIO=()
    
    # Get all VGA and 3D controllers
    local gpu_devices=$(lspci -nn | grep -E "(VGA|3D controller)")
    
    if [[ -z "$gpu_devices" ]]; then
        echo -e "${red}No GPU devices found!${no_color}"
        return 1
    fi
    
    echo -e "${blue}Found GPU devices:${no_color}"
    echo "$gpu_devices"
    echo ""
    
    # Process each GPU device
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            if [[ $line == *"NVIDIA"* ]]; then
                NVIDIA_GPUS+=("$line")
                echo -e "${green}NVIDIA GPU detected:${no_color} $line"
            elif [[ $line == *"AMD"* ]] || [[ $line == *"Advanced Micro Devices"* ]]; then
                AMD_GPUS+=("$line")
                echo -e "${green}AMD GPU detected:${no_color} $line"
            elif [[ $line == *"Intel"* ]]; then
                INTEL_GPUS+=("$line")
                echo -e "${green}Intel GPU detected:${no_color} $line"
            else
                echo -e "${yellow}Unknown GPU vendor:${no_color} $line"
            fi
        fi
    done <<< "$gpu_devices"
    
    # Find associated audio devices
    find_associated_audio_devices
    
    return 0
}

# Function to find audio devices associated with each GPU
find_associated_audio_devices() {
    echo -e "${green}Finding associated audio devices...${no_color}"
    
    # Process NVIDIA GPUs
    for gpu in "${NVIDIA_GPUS[@]}"; do
        local pci_addr=$(extract_pci_address "$gpu")
        local bus=$(echo "$pci_addr" | cut -d':' -f1)
        
        # Look for NVIDIA audio on same bus
        local audio_device=$(lspci -nn | grep -E "Audio.*NVIDIA" | grep "^$bus:")
        
        if [[ -n "$audio_device" ]]; then
            NVIDIA_AUDIO+=("$audio_device")
            echo -e "${green}NVIDIA Audio found:${no_color} $audio_device"
        fi
    done
    
    # Process AMD GPUs
    for gpu in "${AMD_GPUS[@]}"; do
        local pci_addr=$(extract_pci_address "$gpu")
        local bus=$(echo "$pci_addr" | cut -d':' -f1)
        
        # Look for AMD audio on same bus
        local audio_device=$(lspci -nn | grep -E "Audio.*AMD" | grep "^$bus:")
        
        if [[ -n "$audio_device" ]]; then
            AMD_AUDIO+=("$audio_device")
            echo -e "${green}AMD Audio found:${no_color} $audio_device"
        fi
    done
    
    # Process Intel GPUs (less common to have dedicated audio)
    for gpu in "${INTEL_GPUS[@]}"; do
        local pci_addr=$(extract_pci_address "$gpu")
        local bus=$(echo "$pci_addr" | cut -d':' -f1)
        
        # Look for Intel audio on same bus
        local audio_device=$(lspci -nn | grep -E "Audio.*Intel" | grep "^$bus:")
        
        if [[ -n "$audio_device" ]]; then
            INTEL_AUDIO+=("$audio_device")
            echo -e "${green}Intel Audio found:${no_color} $audio_device"
        fi
    done
}

# Function to identify integrated vs discrete GPUs
identify_gpu_types() {
    echo -e "${green}Identifying GPU types (integrated vs discrete)...${no_color}"
    
    declare -a INTEGRATED_GPUS
    declare -a DISCRETE_GPUS
    
    # Check Intel GPUs (usually integrated)
    for gpu in "${INTEL_GPUS[@]}"; do
        # Intel GPUs are typically integrated, but some are discrete (Arc series)
        if [[ $gpu == *"Arc"* ]] || [[ $gpu == *"Xe"* ]]; then
            DISCRETE_GPUS+=("INTEL:$gpu")
            echo -e "${blue}Intel Discrete GPU:${no_color} $gpu"
        else
            INTEGRATED_GPUS+=("INTEL:$gpu")
            echo -e "${blue}Intel Integrated GPU:${no_color} $gpu"
        fi
    done
    
    # Check AMD GPUs
    for gpu in "${AMD_GPUS[@]}"; do
        # AMD integrated GPUs often have "APU" in their name or are on bus 00
        local pci_addr=$(extract_pci_address "$gpu")
        local bus=$(echo "$pci_addr" | cut -d':' -f1)
        
        if [[ $gpu == *"APU"* ]] || [[ $gpu == *"Integrated"* ]] || [[ "$bus" == "00" ]]; then
            INTEGRATED_GPUS+=("AMD:$gpu")
            echo -e "${blue}AMD Integrated GPU:${no_color} $gpu"
        else
            DISCRETE_GPUS+=("AMD:$gpu")
            echo -e "${blue}AMD Discrete GPU:${no_color} $gpu"
        fi
    done
    
    # All NVIDIA GPUs are typically discrete
    for gpu in "${NVIDIA_GPUS[@]}"; do
        DISCRETE_GPUS+=("NVIDIA:$gpu")
        echo -e "${blue}NVIDIA Discrete GPU:${no_color} $gpu"
    done
    
    # Export arrays for use in other scripts
    export INTEGRATED_GPUS
    export DISCRETE_GPUS
}

# Function to select GPU for passthrough
select_gpu_for_passthrough() {
    echo -e "${green}Selecting GPU for passthrough...${no_color}"
    
    # Count available discrete GPUs
    local discrete_count=0
    discrete_count=$((${#NVIDIA_GPUS[@]} + ${#AMD_GPUS[@]}))
    
    if [[ $discrete_count -eq 0 ]]; then
        echo -e "${red}No discrete GPUs found for passthrough${no_color}"
        return 1
    fi
    
    if [[ $discrete_count -eq 1 ]]; then
        echo -e "${green}Single discrete GPU found - auto-selecting for passthrough${no_color}"
        
        if [[ ${#NVIDIA_GPUS[@]} -eq 1 ]]; then
            export SELECTED_GPU="${NVIDIA_GPUS[0]}"
            export SELECTED_AUDIO="${NVIDIA_AUDIO[0]:-}"
            export SELECTED_GPU_TYPE="nvidia"
        elif [[ ${#AMD_GPUS[@]} -eq 1 ]]; then
            export SELECTED_GPU="${AMD_GPUS[0]}"
            export SELECTED_AUDIO="${AMD_AUDIO[0]:-}"
            export SELECTED_GPU_TYPE="amdgpu"
        fi
    else
        echo -e "${yellow}Multiple discrete GPUs found:${no_color}"
        
        local gpu_options=()
        local audio_options=()
        local type_options=()
        
        # Add NVIDIA GPUs to options
        for i in "${!NVIDIA_GPUS[@]}"; do
            gpu_options+=("${NVIDIA_GPUS[$i]}")
            audio_options+=("${NVIDIA_AUDIO[$i]:-}")
            type_options+=("nvidia")
        done
        
        # Add AMD GPUs to options
        for i in "${!AMD_GPUS[@]}"; do
            gpu_options+=("${AMD_GPUS[$i]}")
            audio_options+=("${AMD_AUDIO[$i]:-}")
            type_options+=("amdgpu")
        done
        
        # Display options
        for i in "${!gpu_options[@]}"; do
            echo -e "${blue}[$i]:${no_color} ${gpu_options[$i]}"
            if [[ -n "${audio_options[$i]}" ]]; then
                echo -e "     Audio: ${audio_options[$i]}"
            fi
        done
        
        # Auto-select the first discrete GPU (can be modified for user input)
        local selected_index=0
        export SELECTED_GPU="${gpu_options[$selected_index]}"
        export SELECTED_AUDIO="${audio_options[$selected_index]}"
        export SELECTED_GPU_TYPE="${type_options[$selected_index]}"
        
        echo -e "${green}Auto-selected GPU [$selected_index]:${no_color} $SELECTED_GPU"
    fi
    
    return 0
}

# Function to generate VFIO configuration for selected GPU
generate_vfio_config() {
    if [[ -z "$SELECTED_GPU" ]]; then
        echo -e "${red}No GPU selected for passthrough${no_color}"
        return 1
    fi
    
    echo -e "${green}Generating VFIO configuration...${no_color}"
    
    local gpu_pci_id=$(extract_pci_id "$SELECTED_GPU")
    local gpu_pci_addr=$(extract_pci_address "$SELECTED_GPU")
    
    export GPU_PCI_ID="$gpu_pci_addr"
    export VFIO_IDS="$gpu_pci_id"
    
    echo -e "${yellow}GPU PCI Address:${no_color} $gpu_pci_addr"
    echo -e "${yellow}GPU PCI ID:${no_color} $gpu_pci_id"
    
    if [[ -n "$SELECTED_AUDIO" ]]; then
        local audio_pci_id=$(extract_pci_id "$SELECTED_AUDIO")
        local audio_pci_addr=$(extract_pci_address "$SELECTED_AUDIO")
        
        export AUDIO_PCI_ID="$audio_pci_addr"
        export VFIO_IDS="$VFIO_IDS,$audio_pci_id"
        
        echo -e "${yellow}Audio PCI Address:${no_color} $audio_pci_addr"
        echo -e "${yellow}Audio PCI ID:${no_color} $audio_pci_id"
    fi
    
    echo -e "${green}VFIO IDs:${no_color} $VFIO_IDS"
    
    return 0
}

# Function to verify integrated GPU availability
verify_integrated_gpu() {
    echo -e "${green}Verifying integrated GPU availability...${no_color}"
    
    local integrated_count=${#INTEL_GPUS[@]}
    
    # Check for AMD integrated GPUs
    for gpu in "${AMD_GPUS[@]}"; do
        if [[ $gpu == *"APU"* ]] || [[ $gpu == *"Integrated"* ]]; then
            ((integrated_count++))
        fi
    done
    
    if [[ $integrated_count -gt 0 ]]; then
        echo -e "${green}Integrated GPU available - passthrough should work${no_color}"
        return 0
    else
        echo -e "${red}No integrated GPU found - passthrough may not work without multiple discrete GPUs${no_color}"
        return 1
    fi
}

# Main function to run all detection and configuration
main() {
    echo -e "${green}=== Enhanced GPU Detection and Configuration ===${no_color}"
    echo ""
    
    if ! detect_all_gpus; then
        return 1
    fi
    
    echo ""
    identify_gpu_types
    
    echo ""
    if ! select_gpu_for_passthrough; then
        return 1
    fi
    
    echo ""
    if ! generate_vfio_config; then
        return 1
    fi
    
    echo ""
    verify_integrated_gpu
    
    echo ""
    echo -e "${green}GPU detection and configuration completed${no_color}"
    echo -e "${blue}Selected GPU Type: $SELECTED_GPU_TYPE${no_color}"
    echo -e "${blue}GPU PCI Address: $GPU_PCI_ID${no_color}"
    echo -e "${blue}VFIO IDs: $VFIO_IDS${no_color}"
    
    return 0
}

# If script is run directly, run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi