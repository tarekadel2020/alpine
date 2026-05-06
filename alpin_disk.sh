#!/bin/sh
set -e

# =================================================================
# 1. إعداد المتغيرات (قم بتغييرها حسب رغبتك)
# =================================================================
# مسار القرص الأساسي
DISK="/dev/sda"

# مسارات الأقسام المخصصة
PART_EFI="${DISK}1"
PART_SWAP="${DISK}2"
PART_ROOT="${DISK}3"

# حجم الأقسام
SIZE_EFI="512MiB"
SIZE_SWAP="4GiB"

# إعدادات النظام الأساسية
HOSTNAME="alpine-desktop"
TIMEZONE="Asia/Riyadh"
KEYMAP="us us"

echo "=== [1/6] تثبيت الأدوات اللازمة للتقسيم ==="
apk add parted e2fsprogs dosfstools --no-cache

echo "=== [2/6] مسح القرص وإنشاء جدول التقسيم الجديد ==="
# مسح جدول التقسيم القديم وصنع جدول GPT جديد
parted -s "$DISK" mklabel gpt

# إنشاء قسم الـ EFI
parted -s "$DISK" mkpart primary fat32 1MiB "$SIZE_EFI"
parted -s "$DISK" set 1 esp on

# إنشاء قسم الـ Swap
parted -s "$DISK" mkpart primary linux-swap "$SIZE_EFI" "$SIZE_SWAP"

# إنشاء قسم الـ Root (باقي مساحة الهارد)
parted -s "$DISK" mkpart primary ext4 "$SIZE_SWAP" 100%

echo "=== [3/6] عمل فورمات للأقسام وتفعيلها ==="
# فورمات قسم الـ EFI
mkfs.vfat -F32 "$PART_EFI"

# إعداد وتفعيل قسم الـ Swap
mkswap "$PART_SWAP"
swapon "$PART_SWAP"

# فورمات قسم الـ Root
mkfs.ext4 -F "$PART_ROOT"

echo "=== [4/6] تركيب الأقسام داخل المجلد /mnt ==="
# تركيب القرص الرئيسي
mount -t ext4 "$PART_ROOT" /mnt

# تركيب قسم الـ EFI
mkdir -p /mnt/boot/efi
mount -t vfat "$PART_EFI" /mnt/boot/efi

echo "=== [5/6] إنشاء ملف الإجابات لتثبيت النظام تلقائياً ==="
cat << EOF > /tmp/answers
KEYMAPOPTS="$KEYMAP"
HOSTNAMEOPTS="-n $HOSTNAME"
INTERFACESOPTS="auto lo\niface lo inet loopback\nauto eth0\niface eth0 inet dhcp\n"
TIMEZONEOPTS="-z $TIMEZONE"
APKREPOSOPTS="-1"
SSHDOPTS="-c openssh"
NTPOPTS="-c chrony"
EOF

# تشغيل إعدادات Alpine المبدئية بناءً على ملف الإجابات
setup-alpine -f /tmp/answers

echo "=== [6/6] تثبيت Alpine Linux على الهارد المخصص ==="
# تثبيت النظام والـ Bootloader داخل المسار /mnt
setup-disk -m sys /mnt

echo "====================================================="
echo "✅ تم تثبيت Alpine Linux بنجاح على التقسيم المخصص!"
echo "يمكنك الآن كتابة 'reboot' لإعادة تشغيل الجهاز."
echo "====================================================="
