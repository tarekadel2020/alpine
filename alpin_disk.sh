#!/bin/bash
# ============================================================
# Full Alpine Linux installation script with automatic partitioning
# Uses 4 variables:
#   DISK      : target disk (e.g., /dev/sda)
#   BOOT_SIZE : size of boot partition (e.g., 256M)
#   SWAP_SIZE : size of swap partition (e.g., 2G)
#   ROOT_SIZE : size of root partition (e.g., 30G) - remaining space goes to /home
# ============================================================

# ----------------------- Variables (edit as needed) -----------------------
DISK="/dev/sda"          # target disk (WILL BE COMPLETELY WIPED)
BOOT_SIZE="256M"         # boot partition size (FAT32 if UEFI)
SWAP_SIZE="2G"           # swap partition size
ROOT_SIZE="30G"          # root partition size (remaining space will be /home)

# ----------------------- Check environment -----------------------
check_environment() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run this script as 'root' (use sudo or su)"
        exit 1
    fi
    apk update
    apk add e2fsprogs parted util-linux-misc gptfdisk
    echo "Environment ready."
}

# ----------------------- Automatic partitioning -----------------------
auto_partition() {
    echo "=== Partitioning $DISK automatically ==="
    echo "WARNING: All data on $DISK will be erased!"
    read -p "Type 'yes' to continue: " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi

    # Wipe disk and create new GPT label (works for both BIOS and UEFI)
    wipefs -a "$DISK"
    parted -s "$DISK" mklabel gpt

    # Detect boot mode
    if [ -d /sys/firmware/efi ]; then
        # UEFI: create ESP (boot partition)
        parted -s "$DISK" mkpart primary fat32 1MiB "$BOOT_SIZE"
        parted -s "$DISK" set 1 esp on
        # Create root partition
        parted -s "$DISK" mkpart primary ext4 "$BOOT_SIZE" "$ROOT_SIZE"
        # Create swap partition
        parted -s "$DISK" mkpart primary linux-swap "$ROOT_SIZE" "$SWAP_SIZE"
        # Create home partition with remaining space
        parted -s "$DISK" mkpart primary ext4 "$SWAP_SIZE" 100%
        
        # Set partition variables
        BOOT_PART="${DISK}1"
        ROOT_PART="${DISK}2"
        SWAP_PART="${DISK}3"
        HOME_PART="${DISK}4"
        
        # Format partitions
        mkfs.vfat -F32 "$BOOT_PART"
        mkfs.ext4 -F "$ROOT_PART"
        mkswap "$SWAP_PART"
        mkfs.ext4 -F "$HOME_PART"
        
        # Mount
        mount "$ROOT_PART" /mnt
        mkdir -p /mnt/boot
        mount "$BOOT_PART" /mnt/boot
        mkdir -p /mnt/home
        mount "$HOME_PART" /mnt/home
        swapon "$SWAP_PART"
    else
        # BIOS: create single root partition (or separate boot if needed)
        parted -s "$DISK" mkpart primary ext4 1MiB "$ROOT_SIZE"
        parted -s "$DISK" set 1 boot on
        # Create swap
        parted -s "$DISK" mkpart primary linux-swap "$ROOT_SIZE" "$SWAP_SIZE"
        # Create home with remaining space
        parted -s "$DISK" mkpart primary ext4 "$SWAP_SIZE" 100%
        
        ROOT_PART="${DISK}1"
        SWAP_PART="${DISK}2"
        HOME_PART="${DISK}3"
        
        # Format
        mkfs.ext4 -F -O ^64bit "$ROOT_PART"
        mkswap "$SWAP_PART"
        mkfs.ext4 -F "$HOME_PART"
        
        # Mount
        mount "$ROOT_PART" /mnt
        mkdir -p /mnt/home
        mount "$HOME_PART" /mnt/home
        swapon "$SWAP_PART"
        # For BIOS, bootloader will be installed to /boot inside root partition
    fi
    echo "Partitioning and formatting completed."
}

# ----------------------- Install base system -----------------------
install_system() {
    echo "=== Installing base system ==="
    setup-disk -m sys /mnt
}

# ----------------------- Install bootloader -----------------------
install_bootloader() {
    echo "=== Installing bootloader ==="
    if [ -d /sys/firmware/efi ]; then
        echo "UEFI system detected. Installing GRUB..."
        chroot /mnt apk add grub efibootmgr
        chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Alpine
        chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    else
        echo "BIOS system detected. Installing Syslinux..."
        chroot /mnt apk add syslinux
        dd bs=440 count=1 conv=notrunc if=/usr/share/syslinux/mbr.bin of="$DISK"
        # For BIOS, /boot is inside root partition, so we need to install extlinux there
        mkdir -p /mnt/boot/syslinux
        extlinux -i /mnt/boot/syslinux
        # Create syslinux.cfg
        cat > /mnt/boot/syslinux/syslinux.cfg << EOF
DEFAULT linux
LABEL linux
    KERNEL /boot/vmlinuz-lts
    APPEND root=${ROOT_PART} ro quiet
EOF
    fi
    echo "Bootloader installed."
}

# ----------------------- Verify boot -----------------------
verify_boot() {
    echo "=== Verifying boot ==="
    if [ -d /sys/firmware/efi ]; then
        if [ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]; then
            echo "✓ Boot file found."
        else
            echo "⚠ Boot file not found, but GRUB may be installed elsewhere."
        fi
    else
        if [ -f /mnt/boot/syslinux/syslinux.cfg ]; then
            echo "✓ syslinux.cfg found."
        else
            echo "⚠ syslinux.cfg not found."
        fi
    fi
}

# ----------------------- Main function -----------------------
main() {
    check_environment
    auto_partition
    install_system
    install_bootloader
    verify_boot
    echo ""
    echo "=================================================="
    echo "Alpine Linux installation completed successfully."
    echo "You can now reboot using: reboot"
    echo "Don't forget to remove the installation media."
    echo "=================================================="
}

main
