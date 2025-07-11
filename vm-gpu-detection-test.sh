#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
no_color='\033[0m' # No Color

SWITCH_SCRIPT="/usr/local/bin/gpu-switch.sh"
COMMAND="\$1"
EVENT="\$2"

# Function to extract PCI devices from VM XML using xmllint (more robust)
get_vm_pci_devices_xmllint() {
    local vm_name="$1"
    
    # Get the VM XML configuration
    local vm_xml=$(sudo virsh dumpxml "$vm_name" 2>/dev/null)
    
    if [ -z "$vm_xml" ]; then
        echo "Failed to get XML for VM: $vm_name" >&2
        return 1
    fi
    
    # Use xmllint to extract PCI hostdev addresses
    echo "$vm_xml" | xmllint --xpath "//hostdev[@mode='subsystem' and @type='pci']/source/address/@domain | //hostdev[@mode='subsystem' and @type='pci']/source/address/@bus | //hostdev[@mode='subsystem' and @type='pci']/source/address/@slot | //hostdev[@mode='subsystem' and @type='pci']/source/address/@function" - 2>/dev/null | \
    sed 's/domain="\([^"]*\)"/\1/g; s/bus="\([^"]*\)"/\1/g; s/slot="\([^"]*\)"/\1/g; s/function="\([^"]*\)"/\1/g' | \
    paste -d' ' - - - - | \
    while read -r domain bus slot function; do
        # Convert hex to decimal and format as PCI address
        domain_dec=$(printf "%04x" $domain)
        bus_dec=$(printf "%02x" $bus)
        slot_dec=$(printf "%02x" $slot)
        func_dec=$(printf "%01x" $function)
        
        echo "${domain_dec}:${bus_dec}:${slot_dec}.${func_dec}"
    done
}

# Function to check if a PCI device is a GPU
is_gpu_device() {
    local pci_id="$1"
    # Convert format from domain:bus:slot.function to bus:slot.function
    local pci_addr=$(echo "$pci_id" | sed 's/^0000://')
    
    # Check if this PCI device is a VGA controller or 3D controller
    if lspci -s "$pci_addr" 2>/dev/null | grep -qE "(VGA|3D controller)"; then
        echo -e "${green}GPU found: $pci_addr${no_color}"
        return 0
    else
        echo -e "${blue}Not a GPU: $pci_addr${no_color}"
        return 1
    fi
}

# Test function
test_vm_detection() {
    local vm_name="$1"
    
    if [ -z "$vm_name" ]; then
        echo -e "${red}Usage: $0 <vm-name>${no_color}"
        echo "Available VMs:"
        sudo virsh list --all --name
        return 1
    fi
    
    echo -e "${green}Testing VM: $vm_name${no_color}"
    echo ""
    
    echo -e "${yellow}Method (xmllint):${no_color}"
    if command -v xmllint &> /dev/null; then
        pci_devices_xmllint=$(get_vm_pci_devices_xmllint "$vm_name")
        if [ -n "$pci_devices_xmllint" ]; then
            echo "$pci_devices_xmllint"
            while IFS= read -r pci_device; do
                if [ -n "$pci_device" ]; then
                    is_gpu_device "$pci_device"
                fi
            done <<< "$pci_devices_xmllint"
        else
            echo "No PCI devices found"
        fi
    else
        echo "xmllint not available"
    fi
}

# Main execution
is_gpu_passed_to_vm=$(test_vm_detection "\$COMMAND")
echo "is_gpu_passed_to_vm: $is_gpu_passed_to_vm"

if [ "$is_gpu_passed_to_vm" = "0" ]; then
    echo "GPU is passed to VM"
    if [ "\$EVENT" = "prepare" ]; then
        $SWITCH_SCRIPT vm
    elif [ "\$EVENT" = "release" ]; then
        $SWITCH_SCRIPT host
    fi
else
    echo "GPU is not passed to VM"
fi
