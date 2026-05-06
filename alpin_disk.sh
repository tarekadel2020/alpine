#!/bin/sh
set -e

# =================================================================
# 1. إدخال مسارات الأقسام الجاهزة (تأكد من كتابتها بدقة)
# =================================================================
# قسم الإقلاع (EFI) الموجود مسبقاً
PART_EFI="/dev/sda1"

# قسم النظام (Root) الذي تريد التثبيت عليه
PART_ROOT="/dev/sda3"

# قسم الذاكرة الافتراضية (Swap) إن وجد (اتركه فارغاً "" إذا لم ترغب به)
PART_SWAP="/dev/sda2"

# إعدادات النظام الأساسية
HOSTNAME="alpine-desktop"
TIMEZONE="Asia/Riyadh"
KEYMAP="us us"

echo "=== [1/5] تثبيت الأدوات اللازمة ==="
apk add e2fsprogs dosfstools --no-cache

echo "=== [2/5] عمل فورمات للأقسام المحددة فقط ==="
# تهيئة قسم الـ EFI (تنبيه: إذا كان لديك نظام آخر مثل Windows، احذف هذا السطر لتجنب مسح ملفات إقلاعه)
mkfs.vfat -F32 "$PART_EFI"

# تهيئة وتفعيل الـ Swap إذا تم تحديده
if [ -n "$PART_SWAP" ]; then
    mkswap "$PART_SWAP"
    swapon "$PART_SWAP"
fi

# تهيئة قسم الـ Root الأساسي (سيمسح أي بيانات قديمة عليه فقط)
mkfs.ext4 -F "$PART_ROOT"

echo "=== [3/5] تركيب الأقسام داخل المجلد /mnt ==="
# تركيب قسم الـ Root
mount -t ext4 "$PART_ROOT" /mnt

# إنشاء مجلد الـ EFI وتركيبه
mkdir -p /mnt/boot/efi
mount -t vfat "$PART_EFI" /mnt/boot/efi

echo "=== [4/5] إنشاء ملف الإجابات للإعدادات التلقائية ==="
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

echo "=== [5/5] تثبيت Alpine Linux على الأقسام المحددة ==="
# تثبيت النظام والـ Bootloader مباشرة على الأقسام المركبة في /mnt
setup-disk -m sys /mnt

echo "====================================================="
echo "✅ تم تثبيت Alpine Linux بنجاح على الأقسام المحددة!"
echo "يمكنك الآن كتابة 'reboot' لإعادة التشغيل."
echo "====================================================="
