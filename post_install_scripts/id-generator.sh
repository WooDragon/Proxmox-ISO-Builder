#!/bin/bash

# Script Version: v2.6

# Function to generate the device ID based on serial or MAC
generate_device_id() {
    # Step 1: Check if dmidecode is available
    if ! command -v dmidecode &> /dev/null; then
        echo "dmidecode could not be found. Please install it to proceed."
        exit 1
    fi

    # Step 2: Get Serial Number or MAC Address
    serial=$(dmidecode -s system-serial-number 2>/dev/null)
    if [ -z "$serial" ]; then
        serial=$(dmidecode -s baseboard-serial-number 2>/dev/null)
    fi
    if [ -z "$serial" ]; then
        serial=$(dmidecode -s chassis-serial-number 2>/dev/null)
    fi
    if [ -z "$serial" ]; then
        mac_address=$(ip -o link show | awk '$2 ~ /^e/{print $2, $19}' | grep -v "@" | head -n 1 | awk '{print $2}')
        if [[ -n "$mac_address" && ! "$mac_address" =~ ^(ff:ff:ff:ff:ff:ff|00:00:00:00:00:00)$ ]]; then
            serial="$mac_address"
        fi
    fi

    # Step 3: Generate Hostnames
    if [ -n "$serial" ]; then
        device_id=$(echo -n "$serial" | sha256sum | cut -c1-8)
        hostname_4g="4g-mgmt.$device_id"
        hostname_mgmt="mgmt.$device_id"
    else
        echo "No valid Serial Number or MAC address found."
        exit 1
    fi
}

# Function to update /etc/issue with device ID, ASCII QR code, IP addresses, and interfaces
update_issue() {
    ascii_qr=$(echo -n "$device_id" | qrencode -t ASCIIi -l H)

    # Step 1: Get IP Addresses and Network Interfaces (excluding loopback and fe80::)
    ipv4_info=$(ip -4 addr show | grep -v '127.0.0.1' | awk '/inet / {print $2, $NF}' | cut -d/ -f1)
    ipv6_info=$(ip -6 addr show | grep -v '::1' | grep -v 'fe80' | awk '/inet6 / {print $2, $NF}' | cut -d/ -f1)

    # Step 2: Format IP addresses and interfaces into a readable format
    ip_info=""
    if [ -n "$ipv4_info" ]; then
        ip_info="IPv4 Addresses and Interfaces:\n$ipv4_info"
    fi
    if [ -n "$ipv6_info" ]; then
        ip_info="$ip_info\nIPv6 Addresses and Interfaces:\n$ipv6_info"
    fi

    # Step 3: Unlock /etc/issue before modification
    chattr -i /etc/issue

    # Step 4: Update /etc/issue
    echo -e "Device ID: $device_id\n\n$ascii_qr\n\n$ip_info" > /etc/issue
    echo "Updated /etc/issue with Device ID, ASCII QR code, IP addresses, and interfaces."

    # Step 5: Lock /etc/issue after modification
    chattr +i /etc/issue
}

# Function to rename and reboot VMs
rename_vms() {
    # Step 4: Find VM IDs for VMs starting with '4g-mgmt' or 'mgmt'
    vms=$(qm list | awk '/^ *[0-9]+ +(4g-mgmt|mgmt)/ {print $1, $2}')
    if [ -z "$vms" ]; then
        echo "No VMs with names starting with '4g-mgmt' or 'mgmt' found."
        exit 1
    fi

    # Step 5: Loop through each matching VM and rename if needed
    while IFS= read -r vm;
    do
        vmid=$(echo "$vm" | awk '{print $1}')
        current_name=$(echo "$vm" | awk '{print $2}')

        # Determine the correct hostname based on the prefix
        if [[ "$current_name" == 4g-mgmt* ]]; then
            target_hostname="$hostname_4g"
        elif [[ "$current_name" == mgmt* ]]; then
            target_hostname="$hostname_mgmt"
        else
            echo "Skipping VM ID $vmid with unexpected name format: $current_name"
            continue
        fi

        # Skip if the current name already matches the target hostname
        if [ "$current_name" == "$target_hostname" ]; then
            echo "VM ID $vmid already has the correct hostname: $target_hostname"
            continue
        fi

        # Update the VM name
        echo "Updating VM ID $vmid from '$current_name' to '$target_hostname'..."
        qm set "$vmid" --name "$target_hostname"

        # Reboot the VM to apply changes
        qm reboot "$vmid"
        if [ $? -ne 0 ]; then
            echo "Reboot failed for VM ID $vmid, attempting forced reboot..."
            qm stop "$vmid"
            qm start "$vmid"
        fi

        echo "Cloud-Init parameters have been set for VM ID $vmid, with hostname '$target_hostname'."
    done <<< "$vms"

    echo "All matching VMs have been processed."
}

# Main script entry point
if [ $# -eq 0 ]; then
    echo "Usage: $0 {qm|issue|getid}"
    exit 1
fi

# Check for provided option
case "$1" in
    qm)
        generate_device_id
        rename_vms
        ;;
    issue)
        generate_device_id
        update_issue
        ;;
    getid)
        generate_device_id
        echo "$device_id"
        ;;
    *)
        echo "Invalid option. Use 'qm' to rename VMs, 'issue' to update /etc/issue, or 'getid' to output the generated Device ID."
        exit 1
        ;;
esac
