#!/bin/sh
set -e

# =================================================================
# 1. إعدادات الأقسام (تأكد من مطابقة المسارات لجهازك)
# =================================================================
DISK="/dev/sda"
PART_BOOT="/dev/sda1"  # المساحة الموصى بها: 512MB
PART_ROOT="/dev/sda3"
PART_SWAP="/dev/sda2"

echo "🔎 Starting Intelligent System Discovery..."

# --- التحقق من وضع الإقلاع ---
if [ -d "/sys/firmware/efi" ]; then
    BOOT_MODE="UEFI"
    FS_TYPE="vfat"
    echo "✅ [Detected]: UEFI Mode. (Using FAT32 for Boot Partition)"
else
    BOOT_MODE="BIOS"
    FS_TYPE="ext4"
    echo "✅ [Detected]: BIOS/Legacy Mode. (Using EXT4 for Boot Partition)"
fi

# --- التحقق من نوع الهارد ---
apk add parted --no-cache > /dev/null
PART_TYPE=$(parted -s "$DISK" print | grep "Partition Table" | cut -d: -f2 | xargs)
echo "✅ [Disk Type]: $PART_TYPE"

# --- التحقق من حالة BIOS + GPT الحرجة ---
if [ "$BOOT_MODE" = "BIOS" ] && [ "$PART_TYPE" = "gpt" ]; then
    echo "⚠️  [Warning]: BIOS on GPT disk detected."
    # البحث عن قسم bios_grub
    if ! parted -s "$DISK" print | grep -q "bios_grub"; then
        echo "❌ [Error]: You need a 1MB partition with 'bios_grub' flag for this to work!"
        echo "Please run: parted $DISK set <part_number> bios_grub on"
        exit 1
    fi
    echo "✅ [Status]: bios_grub partition found."
fi

# =================================================================
# 2. تهيئة وتركيب الأقسام
# =================================================================
echo "🛠️ Formatting and Mounting..."
apk add e2fsprogs dosfstools --no-cache

mkfs.ext4 -F "$PART_ROOT"

if [ "$BOOT_MODE" = "UEFI" ]; then
    mkfs.vfat -F32 "$PART_BOOT"
else
    mkfs.ext4 -F "$PART_BOOT"
fi

mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_BOOT" /mnt/boot

[ -n "$PART_SWAP" ] && mkswap "$PART_SWAP" && swapon "$PART_SWAP"

# =================================================================
# 3. التثبيت الأساسي وحل مشكلة الـ Canonical Path
# =================================================================
setup-apkrepos -1
export BOOTLOADER=none
setup-disk -m sys /mnt

echo "🔗 Binding system directories for Chroot..."
for dir in /dev /proc /sys /run; do
    mkdir -p /mnt$dir
    mount --bind $dir /mnt$dir
done

# =================================================================
# 4. تثبيت محمل الإقلاع المناسب من الداخل
# =================================================================
cat << CHROOT_SCRIPT > /mnt/setup_boot.sh
#!/bin/sh
if [ "$BOOT_MODE" = "UEFI" ]; then
    apk add grub-efi efibootmgr --no-cache
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ALPINE
else
    apk add grub-bios --no-cache
    grub-install --target=i386-pc "$DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_SCRIPT

chmod +x /mnt/setup_boot.sh
chroot /mnt /bin/sh /setup_boot.sh
rm /mnt/setup_boot.sh

# =================================================================
# 5. إنهاء المهمة
# =================================================================
umount /mnt/dev /mnt/proc /mnt/sys /mnt/run || true
echo "====================================================="
echo "🎊 Done! System configured for $BOOT_MODE on $PART_TYPE."
echo "You can now safely reboot."
echo "====================================================="
