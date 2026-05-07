#!/bin/sh
set -e

# =================================================================
# 1. إعدادات المستخدم (User Config)
# =================================================================
DISK="/dev/sda"
PART_BOOT="/dev/sda1"
PART_ROOT="/dev/sda3"
PART_SWAP="/dev/sda2"

HOSTNAME="alpine-pro"
TIMEZONE="Asia/Riyadh"
KEYMAP="us us"  # لغة لوحة المفاتيح

echo "--- Full Alpine Installation Starting ---"

# --- طلب كلمة المرور من المستخدم ---
printf "Enter Root Password: "
stty -echo
read ROOT_PASS
stty echo
printf "\n"

# =================================================================
# 2. اكتشاف النظام (Auto-Discovery)
# =================================================================
if [ -d "/sys/firmware/efi" ]; then
    BOOT_MODE="UEFI"
    FS_TYPE="vfat"
else
    BOOT_MODE="BIOS"
    FS_TYPE="ext4"
fi
echo "✅ Mode: $BOOT_MODE"

# =================================================================
# 3. إعداد ملف الإجابات (Answers File)
# =================================================================
# هذا الجزء يعوض عن تشغيل setup-alpine يدوياً
cat << EOF > /tmp/answers
KEYMAPOPTS="$KEYMAP"
HOSTNAMEOPTS="-n $HOSTNAME"
INTERFACESOPTS="auto lo\niface lo inet loopback\nauto eth0\niface eth0 inet dhcp\n"
TIMEZONEOPTS="-z $TIMEZONE"
APKREPOSOPTS="-1"   # اختيار أسرع مستودع تلقائياً
SSHDOPTS="-c openssh"
NTPOPTS="-c chrony"
EOF

echo "🛠️ Applying System Settings (Language, Repos, Network)..."
setup-alpine -f /tmp/answers

# =================================================================
# 4. تهيئة وتركيب الأقسام
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
# 5. التثبيت النهائي (System & Bootloader)
# =================================================================
export BOOTLOADER=none
setup-disk -m sys /mnt

echo "🔗 Binding directories and installing Bootloader..."
for dir in /dev /proc /sys /run; do
    mkdir -p /mnt$dir
    mount --bind $dir /mnt$dir
done

cat << CHROOT_SCRIPT > /mnt/final_setup.sh
#!/bin/sh
# ضبط كلمة المرور داخل النظام
echo "root:$ROOT_PASS" | chpasswd

# تثبيت محمل الإقلاع
if [ "$BOOT_MODE" = "UEFI" ]; then
    apk add grub-efi efibootmgr --no-cache
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ALPINE
else
    apk add grub-bios --no-cache
    grub-install --target=i386-pc "$DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_SCRIPT

chmod +x /mnt/final_setup.sh
chroot /mnt /bin/sh /final_setup.sh
rm /mnt/final_setup.sh

echo "✅ DONE! You can now reboot."
