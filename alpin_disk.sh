#!/bin/sh
set -e

# =================================================================
# 1. CONFIGURATION (Adjust paths to match your partitions)
# =================================================================
DISK="/dev/sda"
PART_EFI="/dev/sda1"  # Used for UEFI mode only
PART_SWAP="/dev/sda2" # Leave as "" if not using swap
PART_ROOT="/dev/sda3"

echo "🔎 Checking System Environment and Disk Type..."

# Detect Boot Mode (UEFI vs BIOS)
if [ -d "/sys/firmware/efi" ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi

# Detect Partition Table Type (GPT vs MBR)
PART_TYPE=$(parted -s "$DISK" print | grep "Partition Table" | cut -d: -f2 | xargs)

echo "✅ Boot Mode Detected: $BOOT_MODE"
echo "✅ Partition Table Detected: $PART_TYPE"

# =================================================================
# 2. GPT + BIOS CASE CHECK
# =================================================================
if [ "$BOOT_MODE" = "BIOS" ] && [ "$PART_TYPE" = "gpt" ]; then
    if ! parted -s "$DISK" print | grep -q "bios_grub"; then
        echo "❌ ERROR: GPT on BIOS requires a 1MB partition with 'bios_grub' flag."
        echo "Please create a 1MB partition and set: parted $DISK set <num> bios_grub on"
        exit 1
    fi
fi

# =================================================================
# 3. PREPARATION AND MOUNTING
# =================================================================
echo "🛠️ Preparing and Mounting Partitions..."
apk add e2fsprogs dosfstools parted --no-cache

mkfs.ext4 -F "$PART_ROOT"
mount "$PART_ROOT" /mnt

if [ "$BOOT_MODE" = "UEFI" ]; then
    mkfs.vfat -F32 "$PART_EFI"
    mkdir -p /mnt/boot/efi
    mount "$PART_EFI" /mnt/boot/efi
fi

# =================================================================
# 4. BASE SYSTEM INSTALLATION
# =================================================================
echo "📦 Installing Alpine Base System..."
setup-apkrepos -1
export BOOTLOADER=none  # Disable default extlinux to avoid boot errors
setup-disk -m sys /mnt

# =================================================================
# 5. FIXING CANONICAL PATH & TMPFS (BIND MOUNTING)
# =================================================================
echo "🔗 Binding System Directories (Fixing Canonical Path)..."
for dir in /dev /proc /sys /run; do
    mkdir -p /mnt$dir
    mount --bind $dir /mnt$dir
done

# =================================================================
# 6. INTERNAL GRUB INSTALLATION (CHROOT)
# =================================================================
echo "🏗️ Installing Bootloader inside Chroot..."

cat << CHROOT_SCRIPT > /mnt/final_install.sh
#!/bin/sh
# Install required packages inside the new system
if [ -d "/sys/firmware/efi" ]; then
    apk add grub-efi efibootmgr --no-cache
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ALPINE --recheck
else
    apk add grub-bios --no-cache
    grub-install --target=i386-pc "$DISK" --recheck
fi
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_SCRIPT

chmod +x /mnt/final_install.sh
chroot /mnt /bin/sh /final_install.sh
rm /mnt/final_install.sh

# =================================================================
# 7. CLEANUP
# =================================================================
echo "🧹 Cleaning up mount points..."
umount /mnt/dev /mnt/proc /mnt/sys /mnt/run || true
[ "$BOOT_MODE" = "UEFI" ] && umount /mnt/boot/efi || true

echo "====================================================="
echo "✅ Installation successfully finished!"
echo "System: $BOOT_MODE | Disk: $PART_TYPE"
echo "You can now type: reboot"
echo "====================================================="
