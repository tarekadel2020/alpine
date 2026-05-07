#!/bin/sh
# Auto Alpine Installer - Semi-interactive
# This script must be run from Alpine Linux live environment as root.

# ========== Static settings (modify as needed) ==========
KEYMAP="us"
TIMEZONE="Asia/Riyadh"
APK_REPO="-1"
HOSTNAME="alpine-box"
SSHD_ENABLE="openssh"
NTP_SERVICE="openntpd"
INTERFACES_CONFIG="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    hostname $HOSTNAME
"
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}INFO: $1${NC}"
}

ask() {
    echo -e "${YELLOW}$1${NC}"
}

# Check root
[ "$(id -u)" -ne 0 ] && error "Please run as root (use sudo or su)."

# Warn about disk erase
echo "WARNING: This script will erase the entire disk and install a new system."
ask "Are you sure you want to continue? [y/N]"
read confirm
[ "$confirm" != "y" ] && error "Aborted."

# Select disk
info "Available disks:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "^loop"
ask "Enter the disk name to install on (e.g., sda or vda):"
read DISK
[ -z "$DISK" ] && error "No disk entered."
DISK="/dev/$DISK"
[ ! -b "$DISK" ] && error "Disk $DISK does not exist."

# Boot mode
ask "Does your system use UEFI? [y/N]"
read uefi
if [ "$uefi" = "y" ] || [ "$uefi" = "Y" ]; then
    BOOT_MODE="uefi"
else
    BOOT_MODE="bios"
fi

# Partitioning
info "Now we will partition $DISK."
ask "Do you want automatic partitioning (single root + swap) or manual? [auto/manual]"
read partition_choice

if [ "$partition_choice" = "manual" ]; then
    info "Running fdisk. Create partitions as needed (root, swap, optionally others)."
    ask "Press Enter to start fdisk..."
    read dummy
    fdisk $DISK
    info "Manual partitioning done. Make sure root partition exists and is formatted ext4."
    ask "Continue with installation? [y/N]"
    read continue_install
    [ "$continue_install" != "y" ] && error "Aborted."
    info "Enter root partition (e.g., ${DISK}1 or ${DISK}2):"
    read ROOT_PART
    [ -z "$ROOT_PART" ] && error "Root partition not entered."
    info "Enter swap partition (if any, leave empty):"
    read SWAP_PART
    mkfs.ext4 -F $ROOT_PART
    mount $ROOT_PART /mnt
    if [ -n "$SWAP_PART" ]; then
        mkswap $SWAP_PART
        swapon $SWAP_PART
    fi
    if [ "$BOOT_MODE" = "uefi" ]; then
        info "You must have an EFI partition (vfat). Enter its name (e.g., ${DISK}1):"
        read EFI_PART
        mkfs.vfat -F32 $EFI_PART
        mkdir -p /mnt/boot
        mount $EFI_PART /mnt/boot
    fi
else
    info "Automatic partitioning: creating single root + swap (and EFI if needed)."
    dd if=/dev/zero of=$DISK bs=1M count=1 2>/dev/null
    if [ "$BOOT_MODE" = "uefi" ]; then
        parted -s $DISK mklabel gpt
        parted -s $DISK mkpart primary fat32 1MiB 513MiB
        parted -s $DISK set 1 esp on
        EFI_PART="${DISK}1"
        parted -s $DISK mkpart primary linux-swap 513MiB 2561MiB
        SWAP_PART="${DISK}2"
        parted -s $DISK mkpart primary ext4 2561MiB 100%
        ROOT_PART="${DISK}3"
        mkfs.vfat -F32 $EFI_PART
        mkswap $SWAP_PART
        swapon $SWAP_PART
        mkfs.ext4 -F $ROOT_PART
        mount $ROOT_PART /mnt
        mkdir -p /mnt/boot
        mount $EFI_PART /mnt/boot
    else
        parted -s $DISK mklabel msdos
        parted -s $DISK mkpart primary ext4 1MiB 2049MiB
        ROOT_PART="${DISK}1"
        parted -s $DISK mkpart primary linux-swap 2049MiB 4098MiB
        SWAP_PART="${DISK}2"
        parted -s $DISK set 1 boot on
        mkfs.ext4 -F $ROOT_PART
        mkswap $SWAP_PART
        swapon $SWAP_PART
        mount $ROOT_PART /mnt
    fi
fi

# Create answer file for setup-alpine
cat > /tmp/answer_file <<EOF
KEYMAPOPTS="$KEYMAP"
HOSTNAMEOPTS="$HOSTNAME"
INTERFACESOPTS="$INTERFACES_CONFIG"
DNSOPTS="8.8.8.8 8.8.4.4"
TIMEZONEOPTS="$TIMEZONE"
PROXYOPTS="none"
APKREPOSOPTS="$APK_REPO"
EOF

# Ask for passwords and user info
ask "Enter root password:"
read -s ROOT_PASSWORD
[ -z "$ROOT_PASSWORD" ] && error "Root password required."

ask "Create a regular user? [y/N]"
read create_user
if [ "$create_user" = "y" ]; then
    ask "Username:"
    read USER_NAME
    ask "User password:"
    read -s USER_PASSWORD
    ask "Add user to groups (wheel,audio,input,video,netdev)? [y/N]"
    read add_groups
    if [ "$add_groups" = "y" ]; then
        USER_GROUPS="wheel,audio,input,video,netdev"
    else
        USER_GROUPS=""
    fi
fi

# Run setup-disk
info "Running setup-disk..."
setup-disk -m sys /mnt || error "setup-disk failed"

cp /tmp/answer_file /mnt/tmp/

# Chroot configuration
info "Configuring system inside chroot..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

chroot /mnt /bin/sh <<EOF
    echo "root:$ROOT_PASSWORD" | chpasswd

    if [ "$create_user" = "y" ]; then
        adduser -D -h /home/$USER_NAME -s /bin/ash $USER_NAME
        echo "$USER_NAME:$USER_PASSWORD" | chpasswd
        if [ -n "$USER_GROUPS" ]; then
            for g in \$(echo $USER_GROUPS | tr ',' ' '); do
                adduser $USER_NAME \$g
            done
        fi
    fi

    if [ "$SSHD_ENABLE" = "openssh" ]; then
        rc-update add sshd default
    fi

    if [ "$NTP_SERVICE" = "openntpd" ]; then
        rc-update add openntpd default
    elif [ "$NTP_SERVICE" = "chrony" ]; then
        rc-update add chronyd default
    fi

    if [ -n "$SWAP_PART" ]; then
        echo "$SWAP_PART swap swap defaults 0 0" >> /etc/fstab
    fi

    if [ "$BOOT_MODE" = "uefi" ] && [ -n "$EFI_PART" ]; then
        echo "$EFI_PART /boot vfat defaults 0 2" >> /etc/fstab
    fi
EOF

# Cleanup
umount /mnt/dev /mnt/proc /mnt/sys
umount /mnt/boot 2>/dev/null
umount /mnt

info "Installation completed successfully."
info "You may now reboot into your new Alpine system."
info "Root password: $ROOT_PASSWORD"
[ -n "$USER_NAME" ] && info "User: $USER_NAME, Password: $USER_PASSWORD"
read -p "Press Enter to reboot..." dummy
reboot
