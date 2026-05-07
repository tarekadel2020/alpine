#!/bin/sh
set -e

# =================================================================
# 1. إعدادات المستخدم
# =================================================================
DISK="/dev/sda"
PART_BOOT="/dev/sda1"
PART_ROOT="/dev/sda3"
PART_SWAP="/dev/sda2"

HOSTNAME="alpine-pro"
TIMEZONE="Asia/Riyadh"
KEYMAP="us us"

echo "--- Advanced Alpine Installation with BIOS-GPT Auto-Fix ---"

# طلب الباسورد مرة واحدة
printf "Enter Root Password: "
stty -echo
read ROOT_PASS
stty echo
printf "\n"

# =================================================================
# 2. اكتشاف النظام ومعالجة حالة BIOS + GPT
# =================================================================
apk add parted --no-cache > /dev/null

[ -d "/sys/firmware/efi" ] && BOOT_MODE="UEFI" || BOOT_MODE="BIOS"
PART_TYPE=$(parted -s "$DISK" print | grep "Partition Table" | cut -d: -f2 | xargs)

echo "✅ Mode: $BOOT_MODE | Disk: $PART_TYPE"

if [ "$BOOT_MODE" = "BIOS" ] && [ "$PART_TYPE" = "gpt" ]; then
    echo "🛠️ Checking for BIOS Boot Partition..."
    if ! parted -s "$DISK" print | grep -q "bios_grub"; then
        echo "⚠️ BIOS Boot Partition not found! Attempting to create one..."
        # محاولة إنشاء قسم 1MB في أول مساحة فارغة (عادة بين 34 و 2047 قطاع)
        parted -s "$DISK" mkpart primary 1MiB 2MiB
        # تحديد رقم القسم الجديد (غالباً سيكون الأخير) وضبط العلم عليه
        NEW_PART=$(parted -s "$DISK" print | grep "1049kB" | awk '{print $1}')
        parted -s "$DISK" set "$NEW_PART" bios_grub on
        echo "✅ BIOS Boot Partition created successfully on part $NEW_PART"
    else
        echo "✅ BIOS Boot Partition already exists."
    fi
fi

# =================================================================
# 3. إعداد ملف الإجابات (تجاوز كل الأسئلة)
# =================================================================
cat << EOF > /tmp/answers
KEYMAPOPTS="$KEYMAP"
HOSTNAMEOPTS="-n $HOSTNAME"
INTERFACESOPTS="auto lo\niface lo inet loopback\nauto eth0\niface eth0 inet dhcp\n"
TIMEZONEOPTS="-z $TIMEZONE"
APKREPOSOPTS="-1"
PASSWORDOPTS="none"
DISKOPTS="none"
EOF

echo "⚙️ Setting up system environment..."
setup-alpine -f /tmp/answers

# =================================================================
# 4. التثبيت والإقلاع
# =================================================================
apk add e2fsprogs dosfstools --no-cache

echo "🛠️ Formatting and Mounting..."
mkfs.ext4 -F "$PART_ROOT"
[ "$BOOT_MODE" = "UEFI" ] && mkfs.vfat -F32 "$PART_BOOT" || mkfs.ext4 -F "$PART_BOOT"

mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_BOOT" /mnt/boot
[ -n "$PART_SWAP" ] && mkswap "$PART_SWAP" && swapon "$PART_SWAP"

export BOOTLOADER=none
setup-disk -m sys /mnt

echo "🔗 Binding directories and fixing GRUB..."
for dir in /dev /proc /sys /run; do
    mkdir -p /mnt$dir
    mount --bind $dir /mnt$dir
done

cat << CHROOT_SCRIPT > /mnt/final_setup.sh
#!/bin/sh
echo "root:$ROOT_PASS" | chpasswd
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

echo "====================================================="
echo "✅ DONE! GPT-BIOS blocklist error avoided."
echo "====================================================="
