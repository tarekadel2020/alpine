#!/bin/sh
# Auto Alpine Installer - Semi-interactive
# يجب تشغيل هذا السكريبت من بيئة Alpine الحية (مثل USB) كـ root.

# ========== الإعدادات الثابتة (غيّرها حسب رغبتك) ==========
KEYMAP="us"                 # تخطيط لوحة المفاتيح (مثل: us, de, fr...)
TIMEZONE="Asia/Riyadh"      # المنطقة الزمنية (مثل: Asia/Riyadh, Europe/London)
APK_REPO="-1"               # -1 يعني أقرب مرآة، أو ضع رابط المرآة كاملاً (مثل http://dl-cdn.alpinelinux.org/alpine/v3.20/main)
HOSTNAME="alpine-box"       # اسم الجهاز (يمكن تغييره لاحقاً)
SSHD_ENABLE="openssh"       # تثبيت وتمكين SSH (openssh أو none)
NTP_SERVICE="openntpd"      # ضبط الوقت (openntpd أو chrony أو none)
INTERFACES_CONFIG="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    hostname $HOSTNAME
"
# ====================================================

# ألوان للعرض
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() {
    echo -e "${RED}خطأ: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}معلومات: $1${NC}"
}

ask() {
    echo -e "${YELLOW}$1${NC}"
}

# التحقق من صلاحيات الجذر
[ "$(id -u)" -ne 0 ] && error "يجب تشغيل السكريبت كـ root (استخدم sudo أو su)."

# التحقق من أننا في بيئة حية (اختياري، لكن يمكن تعطيله إذا أردت)
echo "تحذير: هذا السكريبت يمسح القرص بالكامل ويقوم بتثبيت نظام جديد."
ask "هل أنت متأكد أنك تريد المتابعة؟ [y/N]"
read confirm
[ "$confirm" != "y" ] && error "تم الإلغاء."

# ========== اختيار القرص ==========
info "الأقراص المتوفرة:"
lsblk -d -o NAME,SIZE,MODEL | grep -v "^loop"
ask "أدخل اسم القرص المراد التثبيت عليه (مثل sda أو vda):"
read DISK
[ -z "$DISK" ] && error "لم تدخل قرصاً."
DISK="/dev/$DISK"
[ ! -b "$DISK" ] && error "القرص $DISK غير موجود."

# ========== تحديد نمط التمهيد (BIOS أو UEFI) ==========
ask "هل نظامك يستخدم UEFI؟ [y/N]"
read uefi
if [ "$uefi" = "y" ] || [ "$uefi" = "Y" ]; then
    BOOT_MODE="uefi"
else
    BOOT_MODE="bios"
fi

# ========== تقسيم القرص (دليل كامل) ==========
info "سنساعدك الآن في تقسيم القرص $DISK."
ask "هل تريد إنشاء الأقسام تلقائياً (قسم جذر واحد + swap) أم تريد تقسيماً يدوياً؟ [auto/manual]"
read partition_choice

if [ "$partition_choice" = "manual" ]; then
    info "سيتم فتح أداة fdisk. أنشئ الأقسام كما تريد (جذر، swap، وأقسام إضافية)."
    ask "بعد الانتهاء، احفظ التغييرات واخرج. اضغط Enter لبدء fdisk..."
    read dummy
    fdisk $DISK
    info "تم التقسيم اليدوي. تأكد من أن القسم الجذر (/) موجود وقم بتهيئته بنظام ext4 أو غيره."
    ask "هل تريد متابعة التثبيت الآن؟ [y/N]"
    read continue_install
    [ "$continue_install" != "y" ] && error "تم الإلغاء."
    # بعد التقسيم اليدوي، سنطلب من المستخدم تحديد القسم الجذر وقسم swap (إن وجد)
    info "أدخل اسم القسم الجذر (مثل ${DISK}1 أو ${DISK}2):"
    read ROOT_PART
    [ -z "$ROOT_PART" ] && error "لم تدخل القسم الجذر."
    info "أدخل اسم قسم swap (إذا وجد، وإلا اتركه فارغاً):"
    read SWAP_PART
    # تهيئة القسم الجذر
    mkfs.ext4 -F $ROOT_PART
    mount $ROOT_PART /mnt
    if [ -n "$SWAP_PART" ]; then
        mkswap $SWAP_PART
        swapon $SWAP_PART
    fi
    # إذا كان UEFI، نحتاج للتأكد من وجود قسم EFI
    if [ "$BOOT_MODE" = "uefi" ]; then
        info "يجب أن يكون لديك قسم EFI (نوع vfat). أدخل اسمه (مثل ${DISK}1):"
        read EFI_PART
        mkfs.vfat -F32 $EFI_PART
        mkdir -p /mnt/boot
        mount $EFI_PART /mnt/boot
    fi
else
    # تقسيم تلقائي (بسيط)
    info "تقسيم تلقائي: سيتم إنشاء قسم جذر واحد + swap (وEFI إن لزم)."
    # مسح جدول الأقسام الحالي
    dd if=/dev/zero of=$DISK bs=1M count=1 2>/dev/null
    if [ "$BOOT_MODE" = "uefi" ]; then
        parted -s $DISK mklabel gpt
        # قسم EFI 512M
        parted -s $DISK mkpart primary fat32 1MiB 513MiB
        parted -s $DISK set 1 esp on
        EFI_PART="${DISK}1"
        # قسم swap 2G
        parted -s $DISK mkpart primary linux-swap 513MiB 2561MiB
        SWAP_PART="${DISK}2"
        # قسم الجذر الباقي
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
        # قسم الجذر (متبوعاً بـ swap)
        parted -s $DISK mkpart primary ext4 1MiB 2049MiB
        ROOT_PART="${DISK}1"
        parted -s $DISK mkpart primary linux-swap 2049MiB 4098MiB
        SWAP_PART="${DISK}2"
        # جعل القسم الأول قابل للتمهيد
        parted -s $DISK set 1 boot on
        mkfs.ext4 -F $ROOT_PART
        mkswap $SWAP_PART
        swapon $SWAP_PART
        mount $ROOT_PART /mnt
    fi
fi

# ========== إعداد ملف الإجابة لـ setup-alpine ==========
cat > /tmp/answer_file <<EOF
KEYMAPOPTS="$KEYMAP"
HOSTNAMEOPTS="$HOSTNAME"
INTERFACESOPTS="$INTERFACES_CONFIG"
DNSOPTS="8.8.8.8 8.8.4.4"
TIMEZONEOPTS="$TIMEZONE"
PROXYOPTS="none"
APKREPOSOPTS="$APK_REPO"
EOF

# ========== طلب بيانات المستخدم ==========
ask "أدخل كلمة مرور الجذر (root):"
read -s ROOT_PASSWORD
[ -z "$ROOT_PASSWORD" ] && error "كلمة مرور الجذر مطلوبة."

ask "هل تريد إنشاء مستخدم عادي؟ [y/N]"
read create_user
if [ "$create_user" = "y" ]; then
    ask "اسم المستخدم العادي:"
    read USER_NAME
    ask "كلمة مرور المستخدم:"
    read -s USER_PASSWORD
    ask "هل تريد إضافة المستخدم إلى مجموعات إضافية (مثل wheel,audio,input,video,netdev)؟ [y/N]"
    read add_groups
    if [ "$add_groups" = "y" ]; then
        USER_GROUPS="wheel,audio,input,video,netdev"
    else
        USER_GROUPS=""
    fi
    USER_OPTS="-a -u $USER_NAME"
    [ -n "$USER_PASSWORD" ] && USER_PASS_OPT="-p $(openssl passwd -6 $USER_PASSWORD)"
    [ -n "$USER_GROUPS" ] && USER_GROUPS_OPT="-g $USER_GROUPS"
fi

# ========== تشغيل setup-disk لتثبيت النظام الأساسي ==========
info "تثبيت النظام الأساسي..."
setup-disk -m sys /mnt || error "فشل setup-disk"

# نسخ ملف الإجابة إلى النظام الجديد
cp /tmp/answer_file /mnt/tmp/

# ========== التعديلات داخل chroot ==========
info "تهيئة النظام داخل chroot..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

chroot /mnt /bin/sh <<EOF
    # تعيين كلمة مرور الجذر
    echo "root:$ROOT_PASSWORD" | chpasswd

    # إنشاء مستخدم عادي إذا طلب
    if [ "$create_user" = "y" ]; then
        adduser -D -h /home/$USER_NAME -s /bin/ash $USER_NAME
        echo "$USER_NAME:$USER_PASSWORD" | chpasswd
        if [ -n "$USER_GROUPS" ]; then
            for g in \$(echo $USER_GROUPS | tr ',' ' '); do
                adduser $USER_NAME \$g
            done
        fi
    fi

    # تمكين SSH
    if [ "$SSHD_ENABLE" = "openssh" ]; then
        rc-update add sshd default
    fi

    # ضبط الوقت
    if [ "$NTP_SERVICE" = "openntpd" ]; then
        rc-update add openntpd default
    elif [ "$NTP_SERVICE" = "chrony" ]; then
        rc-update add chronyd default
    fi

    # إضافة قسم swap إلى fstab (إذا كان موجوداً)
    if [ -n "$SWAP_PART" ]; then
        echo "$SWAP_PART swap swap defaults 0 0" >> /etc/fstab
    fi

    # إضافة قسم EFI إلى fstab (لمنع فقدانه بعد إعادة التشغيل)
    if [ "$BOOT_MODE" = "uefi" ] && [ -n "$EFI_PART" ]; then
        echo "$EFI_PART /boot vfat defaults 0 2" >> /etc/fstab
    fi
EOF

# إنهاء التثبيت
umount /mnt/dev /mnt/proc /mnt/sys
umount /mnt/boot 2>/dev/null
umount /mnt

info "اكتمل التثبيت بنجاح!"
info "يمكنك الآن إعادة التشغيل والدخول إلى النظام الجديد."
info "كلمة مرور الجذر: $ROOT_PASSWORD"
[ -n "$USER_NAME" ] && info "المستخدم: $USER_NAME، كلمة المرور: $USER_PASSWORD"
read -p "اضغط Enter لإعادة التشغيل..." dummy
reboot
