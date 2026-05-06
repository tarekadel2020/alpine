#!/bin/sh
set -e

# =================================================================
# 1. إعدادات الأقسام (تأكد من مطابقتها لجهازك)
# =================================================================
DISK="/dev/sda"
PART_ROOT="/dev/sda3"
PART_SWAP="/dev/sda2"
PART_EFI="/dev/sda1"  # سيستخدم فقط إذا كان النظام UEFI

echo "🔎 جاري فحص بيئة النظام ونوع الهارد..."

# اكتشاف هل النظام UEFI أم BIOS
if [ -d "/sys/firmware/efi" ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi

# اكتشاف نوع جدول التقسيم (GPT أو MBR)
PART_TYPE=$(parted -s "$DISK" print | grep "Partition Table" | cut -d: -f2 | xargs)

echo "Your Boot mode : $BOOT_MODE"
echo "Your disk is   : $PART_TYPE"

# =================================================================
# 2. تثبيت الأدوات اللازمة
# =================================================================
apk add e2fsprogs dosfstools parted --no-cache
[ "$BOOT_MODE" = "UEFI" ] && apk add grub-efi efibootmgr --no-cache
[ "$BOOT_MODE" = "BIOS" ] && apk add grub-bios --no-cache

# =================================================================
# 3. تهيئة وتركيب الأقسام
# =================================================================
echo " Preparing Your Partition ..."
mkfs.ext4 -F "$PART_ROOT"
[ -n "$PART_SWAP" ] && mkswap "$PART_SWAP" && swapon "$PART_SWAP"

mount "$PART_ROOT" /mnt

if [ "$BOOT_MODE" = "UEFI" ]; then
    mkfs.vfat -F32 "$PART_EFI"
    mkdir -p /mnt/boot/efi
    mount "$PART_EFI" /mnt/boot/efi
fi

# =================================================================
# 4. التعامل مع حالة GPT + BIOS (المشكلة التي واجهتك)
# =================================================================
if [ "$BOOT_MODE" = "BIOS" ] && [ "$PART_TYPE" = "gpt" ]; then
    echo "We Find your disk is GPT in the BIOS. Searching for the bios_grub partition...."
    # البحث عن قسم صغير (أقل من 10MB) وغير مهيأ لضبطه كـ bios_grub
    BIOS_GRUB_PART=$(parted -s "$DISK" print | grep "bios_grub" | awk '{print $1}')
    
    if [ -z "$BIOS_GRUB_PART" ]; then
        echo "❌ خطأ: نظام BIOS + GPT يتطلب قسم بمساحة 1MB ونوع bios_grub."
        echo "يرجى إنشاء قسم صغير وضبطه عبر: parted $DISK set <رقم> bios_grub on"
        exit 1
    fi
fi

# =================================================================
# 5. التثبيت
# =================================================================
echo " Instaling Alpine Linux..."
setup-apkrepos -1
setup-disk -m sys /mnt

# =================================================================
# 6. إصلاح الإقلاع النهائي
# =================================================================
if [ "$BOOT_MODE" = "BIOS" ]; then
    echo " Instaling The BootLoader on BIOS..."
    grub-install --target=i386-pc "$DISK"
fi

echo "====================================================="
echo "Successfully install"
echo "Disk is : $BOOT_MODE on partion $PART_TYPE"
echo "you can make  reboot"
echo "====================================================="
