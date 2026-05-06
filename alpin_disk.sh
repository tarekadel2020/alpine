#!/bin/sh
set -e

# =================================================================
# 1. إدخال مسارات الأقسام الجاهزة (BIOS/Legacy)
# =================================================================
# الهارد الأساسي (بدون رقم) لتثبيت محمل الإقلاع عليه
BOOT_DISK="/dev/sda"

#PART_EFI="/dev/sda1"
PART_SWAP="/dev/sda2"
PART_ROOT="/dev/sda3"

# إعدادات النظام الأساسية
HOSTNAME="alpine-legacy"
TIMEZONE="Asia/Riyadh"
KEYMAP="us us"

echo "=== [1/5] Install APPS ==="
apk add e2fsprogs dosfstools --no-cache

echo "=== [2/5] عمل فورمات للأقسام المحددة فقط ==="
if [ -n "$PART_EFI" ]; then
    mkfs.vfat -F32 "$PART_EFI"
fi

# تهيئة وتفعيل الـ Swap إذا تم تحديده
if [ -n "$PART_SWAP" ]; then
    mkswap "$PART_SWAP"
    swapon "$PART_SWAP"
fi

# تهيئة قسم الـ Root الأساسي (سيمسح أي بيانات قديمة عليه)
mkfs.ext4 -F "$PART_ROOT"

echo "=== [3/5] Mount  /mnt ==="
# في نظام BIOS لا نحتاج لتركيب قسم EFI، نكتفي بالـ Root
mount -t ext4 "$PART_ROOT" /mnt
if [ -n "$PART_EFI" ]; then
    mkdir -p /mnt/boot/efi
    mount -t vfat "$PART_EFI" /mnt/boot/efi
fi

echo "=== [4/5] Create Answer File ==="
cat << EOF > /tmp/answers
KEYMAPOPTS="$KEYMAP"
HOSTNAMEOPTS="-n $HOSTNAME"
INTERFACESOPTS="auto lo\niface lo inet loopback\nauto eth0\niface eth0 inet dhcp\n"
TIMEZONEOPTS="-z $TIMEZONE"
APKREPOSOPTS="-1"
SSHDOPTS="-c openssh"
NTPOPTS="-c chrony"
EOF

# تطبيق الإعدادات المبدئية
setup-alpine -f /tmp/answers

echo "=== [5/5] تثبيت Alpine Linux (نظام BIOS) ==="
# الخيار -m sys سيقوم تلقائياً باكتشاف أن الجهاز BIOS وتثبيت Grub على الـ MBR
setup-disk -m sys /mnt

echo "====================================================="
echo "✅ تم التثبيت بنجاح بنظام BIOS/Legacy!"
echo "يمكنك الآن إعادة التشغيل عبر أمر: reboot"
echo "====================================================="
