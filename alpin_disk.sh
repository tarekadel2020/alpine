#!/bin/bash
# ============================================================
# Full Alpine Linux installation script
# Uses only 4 variables:
#   DISK     : target disk (e.g., /dev/sda)
#   BOOT_PART: boot partition path (e.g., /dev/sda1)
#   ROOT_PART: root partition path (e.g., /dev/sda2)
#   SWAP_PART: swap partition path (e.g., /dev/sda3)
# ============================================================

# ----------------------- Variables (edit as needed) -----------------------
DISK="/dev/sda"          # target disk
BOOT_PART="/dev/sda1"    # boot partition (must be FAT32 if UEFI)
ROOT_PART="/dev/sda2"    # root partition (ext4)
SWAP_PART="/dev/sda3"    # swap partition

# ----------------------- Check environment -----------------------
check_environment() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run this script as 'root' (use sudo or su)"
        exit 1
    fi
    apk update
    apk add e2fsprogs parted util-linux-misc
    echo "Environment ready."
}

# ----------------------- Prepare partitions -----------------------
prepare_partitions() {
    echo "=== Preparing partitions ==="
    # Verify existence of partitions
    if [ ! -b "$BOOT_PART" ]; then
        echo "ERROR: Boot partition $BOOT_PART does not exist."
        exit 1
    fi
    if [ ! -b "$ROOT_PART" ]; then
        echo "ERROR: Root partition $ROOT_PART does not exist."
        exit 1
    fi
    if [ ! -b "$SWAP_PART" ]; then
        echo "ERROR: Swap partition $SWAP_PART does not exist."
        exit 1
    fi

    # Format partitions (warning: data will be erased)
    echo "The following partitions will be formatted:"
    echo "  $BOOT_PART -> FAT32 (if UEFI) or ext4 (if BIOS)"
    echo "  $ROOT_PART -> ext4"
    echo "  $SWAP_PART -> swap"
    read -p "Do you want to continue? (type 'yes' to proceed): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi

    # Format boot partition according to system type
    if [ -d /sys/firmware/efi ]; then
        mkfs.vfat -F32 "$BOOT_PART"
    else
        mkfs.ext4 -F -O ^64bit "$BOOT_PART"
    fi

    # Format root partition
    mkfs.ext4 -F "$ROOT_PART"

    # Format swap partition
    mkswap "$SWAP_PART"

    echo "Partitions formatted successfully."
}

# ----------------------- Mount partitions -----------------------
mount_partitions() {
    echo "=== Mounting partitions ==="
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot
    swapon "$SWAP_PART"
    echo "Mounting done."
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
        extlinux -i /mnt/boot
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
    prepare_partitions
    mount_partitions
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
