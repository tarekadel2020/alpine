#!/bin/sh
# auto_install_alpine.sh
# Automated Alpine Linux Installation Script (for BIOS/Legacy or UEFI)
# Run as root from Alpine live environment

# ==================== START OF CONFIGURATION ====================
# متغيرات التثبيت - عدلها كما تريد
DISK="/dev/sda"                # القرص المستهدف (حذر: سيتم مسح كل البيانات)
BOOT_MODE="bios"               # bios أو uefi
HOSTNAME="alpine-box"
ROOT_PASSWORD="strongpassword"  # كلمة مرور المستخدم root
USER_NAME="user"
USER_PASSWORD="userpass"
USER_GROUPS="wheel,audio,input,video,netdev"
TIMEZONE="Asia/Riyadh"         # المنطقة الزمنية
KEYMAP="us"                    # تخطيط لوحة المفاتيح
SSHD_ENABLE="openssh"          # تثبيت وتمكين openssh
NTP_SERVICE="openntpd"         # chrony أو openntpd أو none
APK_MIRROR="-1"                # -1 لأقرب سيرفر، أو رابط يدوي مثلاً "http://mirror.example.com/alpine/v3.20/main"
INTERFACES_CONFIG="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    hostname $HOSTNAME
"
# أقسام القرص (بالنسبة لـ UEFI: قسم EFI 512M، swap 2G، root باقي)
SWAP_SIZE="+2G"                # حجم swap (مثال: +2G أو +512M)
# ==================== END OF CONFIGURATION ====================

# ألوان للإخراج (اختياري)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}INFO: $1${NC}"
}

# التحقق من وجود أدوات ضرورية
command -v parted >/dev/null 2>&1 || { info "Installing parted..."; apk add parted || error "Failed to install parted"; }
command -v sfdisk >/dev/null 2>&1 || { info "Installing sfdisk..."; apk add util-linux || error "Failed to install util-linux"; }

# إذا لم يكن النظام حياً، لا نستمر
#[ -z "$(mount | grep 'on / ')" ] || error "This script must be run from Alpine live environment (not from installed system)."
echo "WARNING: This script must be run from Alpine live environment."
echo "If you are not currently booted from Alpine live CD/USB, this will destroy your system."
read -p "Continue? [y/N]: " ans
[ "$ans" = "y" -o "$ans" = "Y" ] || exit 1

# تأكيد الكتابة على القرص (سؤال واحد فقط)
printf "\nWARNING: This will erase ALL data on $DISK. Continue? [y/N]: "
read answer
case "$answer" in
    y|Y|yes|Yes) ;;
    *) error "Aborted by user." ;;
esac

info "Creating partitions on $DISK..."

# مسح جدول الأقسام
dd if=/dev/zero of=$DISK bs=1M count=1 2>/dev/null

if [ "$BOOT_MODE" = "uefi" ]; then
    # جدول GPT
    parted -s $DISK mklabel gpt
    # قسم EFI (512 MiB)
    parted -s $DISK mkpart primary fat32 1MiB 513MiB
    parted -s $DISK set 1 esp on
    BOOT_PART="${DISK}1"
    # قسم swap
    parted -s $DISK mkpart primary linux-swap 513MiB $SWAP_SIZE
    SWAP_PART="${DISK}2"
    # قسم root (باقي المساحة)
    parted -s $DISK mkpart primary ext4 $SWAP_SIZE 100%
    ROOT_PART="${DISK}3"
    # تنسيق القسم EFI
    mkfs.vfat -F32 $BOOT_PART
else
    # BIOS - جدول MBR
    parted -s $DISK mklabel msdos
    # قسم boot (بدون نظام ملفات منفصل، سنستخدم القسم نفسه)
    # لكن ننشئ قسم root أولاً ثم قسم swap
    # نخصص 1MiB للبدء
    parted -s $DISK mkpart primary ext4 1MiB ${SWAP_SIZE}
    ROOT_PART="${DISK}1"
    parted -s $DISK mkpart primary linux-swap ${SWAP_SIZE} 100%
    SWAP_PART="${DISK}2"
    # جعل القسم الأول bootable
    parted -s $DISK set 1 boot on
fi

# تنسيق القسم الجذر
info "Formatting root partition..."
mkfs.ext4 -F $ROOT_PART
info "Formatting swap partition..."
mkswap $SWAP_PART
swapon $SWAP_PART

# تركيب الأقسام
info "Mounting partitions..."
mount $ROOT_PART /mnt
if [ "$BOOT_MODE" = "uefi" ]; then
    mkdir -p /mnt/boot
    mount $BOOT_PART /mnt/boot
fi

# إنشاء ملف إجابة لـ setup-alpine
cat > /tmp/answer_file <<EOF
KEYMAPOPTS="$KEYMAP"
HOSTNAMEOPTS="$HOSTNAME"
INTERFACESOPTS="$INTERFACES_CONFIG"
DNSOPTS="8.8.8.8 8.8.4.4"
TIMEZONEOPTS="$TIMEZONE"
PROXYOPTS="none"
APKREPOSOPTS="$APK_MIRROR"
USEROPTS="-a -u -g $USER_GROUPS $USER_NAME"
SSHDOPTS="$SSHD_ENABLE"
NTPOPTS="$NTP_SERVICE"
LBUOPTS="none"
APKCACHEOPTS="none"
empty_root_password=1
EOF

# تثبيت النظام الأساسي
info "Running setup-disk..."
setup-disk -m sys /mnt || error "setup-disk failed"

# نسخ ملف الإجابة إلى النظام الجديد
cp /tmp/answer_file /mnt/tmp/

# إجراء تعديلات في chroot
info "Configuring system inside chroot..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

chroot /mnt /bin/sh <<EOF
    # تعيين كلمة مرور root
    echo "root:$ROOT_PASSWORD" | chpasswd
    # التأكد من وجود المستخدم وتعيين كلمة المرور
    adduser -D -h /home/$USER_NAME -s /bin/ash $USER_NAME || true
    echo "$USER_NAME:$USER_PASSWORD" | chpasswd
    for group in \$(echo $USER_GROUPS | tr ',' ' '); do
        adduser $USER_NAME \$group
    done
    # إعداد hostname بشكل نهائي
    echo "$HOSTNAME" > /etc/hostname
    # إعداد sshd
    rc-update add sshd default
    # إعداد NTP
    case "$NTP_SERVICE" in
        openntpd) rc-update add openntpd default ;;
        chrony) rc-update add chronyd default ;;
    esac
    # إعداد swapon على قسم swap في fstab
    echo "$SWAP_PART swap swap defaults 0 0" >> /etc/fstab
    # إذا كان boot_mode = bios، قد يحتاج إلى grub أو syslinux (لكن setup-disk قام بتثبيت syslinux)
    # التعديل الإضافي: جعل النظام يبدأ بشكل صحيح (غير مطلوب عادة)
EOF

# إنهاء التثبيت
umount /mnt/dev /mnt/proc /mnt/sys
umount /mnt/boot 2>/dev/null
umount /mnt

info "Installation completed successfully."
info "You can now reboot into your new Alpine system."
info "Root password: $ROOT_PASSWORD, User: $USER_NAME / $USER_PASSWORD"

read -p "Press Enter to reboot, or Ctrl+C to cancel." dummy
