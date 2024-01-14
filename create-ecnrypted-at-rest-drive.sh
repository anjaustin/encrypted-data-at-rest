#!/bin/bash

### Functions ###

# Check if cryptsetup is installed
cryptsetup_installed() {
    if ! command -v cryptsetup &> /dev/null; then
        echo "Error: cryptsetup is not installed. Please install it before running this script."
        exit 1
    fi
    echo "$(cryptsetup -V) is currently installed."
}

# Select the drive to format and encrypt
select_drive() {
    drives_list=$(lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT,RO,MODEL --noheadings | cat -n)

    if [ -z "$drives_list" ]; then
        echo "Error: No drives detected. Exiting."
        exit 1
    fi

    echo -e "Available drives:\n$drives_list"

    read -p "Enter the number of the drive you want to use: " drive_number

    if ! [[ "$drive_number" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid input. Please enter a number. Exiting."
        exit 1
    fi

    total_drives=$(echo "$drives_list" | wc -l)

    if ! (( drive_number >= 1 && drive_number <= total_drives )); then
        echo "Error: Invalid drive number. Please enter a number between 1 and $total_drives. Exiting."
        exit 1
    fi

    selected_drive_info=$(echo "$drives_list" | awk -v num="$drive_number" '$1 == num { print $2, $NF }')

    read -p "You selected drive $selected_drive_info. Is this correct? (y/n): " confirm_choice

    if ! [[ "$confirm_choice" =~ [yY] ]]; then
        echo "Selection canceled. Exiting."
        exit 1
    fi

    echo "Drive $selected_drive_info confirmed."
}

# Function to format the selected drive
format_drive() {
    drive_info=$(echo "$selected_drive_info" | awk '{print $1, $2}')
    drive_name=$(echo "$drive_info" | awk '{print $1}')

    if [ -z "$drive_name" ]; then
        echo "Error: Unable to extract drive information. Exiting."
        exit 1
    fi

    drive_model=$(echo "$selected_drive_info" | awk '{$1=""; print $0}' | sed 's/^[[:space:]]*//')
    drive_model_underscored=$(echo "$drive_model" | tr ' ' '_')

    drive_size=$(lsblk -b -d -n -o SIZE "/dev/$drive_name")

    if [ -z "$drive_size" ]; then
        echo "Error: Unable to determine drive size. Exiting."
        exit 1
    fi

    drive_size_human=$(numfmt --to=iec-i --suffix=B "$drive_size")

    default_encrypted_drive_name="${drive_name}-EAR-${drive_model_underscored}"
    [ -n "$drive_size" ] && default_encrypted_drive_name="${default_encrypted_drive_name}-${drive_size_human}"

    read -p "Enter a name for the encrypted drive (default: $default_encrypted_drive_name): " encrypted_drive_name

    encrypted_drive_name=${encrypted_drive_name:-$default_encrypted_drive_name}

    echo -e "Selected Drive Information:\nDrive Name: $drive_name\nDrive Model: $drive_model\nDrive Size: $drive_size_human"
    echo -e "Encrypted Drive Name: $encrypted_drive_name"

    read -p "Do you want to proceed with formatting this drive? (y/n): " confirm_format

    if ! [[ "$confirm_format" =~ [yY] ]]; then
        echo "Formatting canceled. Exiting."
        exit 1
    fi

    sudo cryptsetup luksFormat "/dev/$drive_name"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to format the drive. Exiting."
        exit 1
    fi

    sudo cryptsetup luksOpen "/dev/$drive_name" "$encrypted_drive_name"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to open the LUKS device. Exiting."
        exit 1
    fi

    sudo mkfs.ext4 "/dev/mapper/$encrypted_drive_name"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to create ext4 filesystem. Exiting."
        exit 1
    fi

    sudo mkdir -vp "/mnt/$encrypted_drive_name"
    sudo mount "/dev/mapper/$encrypted_drive_name" "/mnt/$encrypted_drive_name"

    if [ $? -ne 0 ]; then
        echo "Error: Failed to mount the LUKS device. Exiting."
        exit 1
    fi

    echo "Drive formatting and encryption completed successfully."
}

# Function to update user's '~/.bashrc' and '~/.bash_logout'
update_user_bash() {
    read -p "Do you want to update your ~/.bashrc and ~/.bash_logout to unlock the drive on login and lock on logout? (y/n): " update_bashrc

    if [[ "$update_bashrc" =~ [yY] ]]; then
        echo "Updating your ~/.bashrc and ~/.bash_logout"
        echo -e "\n# Mount encrypted drives\nsudo cryptsetup luksOpen '/dev/$drive_name' '$encrypted_drive_name'" >> ~/.bashrc
        echo "sudo mount '/dev/mapper/$encrypted_drive_name' '/mnt/$encrypted_drive_name'" >> ~/.bashrc
        echo -e "\n# Unmount encrypted drives\nsudo umount '/mnt/$encrypted_drive_name' && sudo cryptsetup luksClose '$encrypted_drive_name'" >> ~/.bash_logout
        echo "Updates, complete."
    else
        echo "Skipping update of ~/.bashrc and ~/.bash_logout."
    fi
}

### Start Script ###

cryptsetup_installed
select_drive
format_drive
update_user_bash
# EOF >>>
