#!/bin/bash
# ============================================================
# سكريبت التثبيت الكامل لنظام Alpine Linux
# يستخدم 4 متغيرات فقط:
#   DISK     : اسم القرص (مثال: /dev/sda)
#   BOOT_PART: مسار قسم البوت (مثال: /dev/sda1)
#   ROOT_PART: مسار قسم الروت (مثال: /dev/sda2)
#   SWAP_PART: مسار قسم السواب (مثال: /dev/sda3)
# ============================================================

# ----------------------- المتغيرات (قم بتعديلها) -----------------------
DISK="/dev/sda"          # القرص المستهدف
BOOT_PART="/dev/sda1"    # قسم البوت (يجب أن يكون من نوع FAT32 إذا كان UEFI)
ROOT_PART="/dev/sda2"    # قسم النظام الجذر (ext4)
SWAP_PART="/dev/sda3"    # قسم المبادلة (swap)

# ----------------------- دالة للتحقق من البيئة -----------------------
check_environment() {
    if [ "$EUID" -ne 0 ]; then
        echo "الرجاء تشغيل السكريبت كـ 'root' (استخدم sudo أو su)"
        exit 1
    fi
    apk update
    apk add e2fsprogs parted util-linux-misc
    echo "البيئة جاهزة."
}

# ----------------------- دالة لتحضير الأقسام -----------------------
prepare_partitions() {
    echo "=== تجهيز الأقسام ==="
    # التحقق من وجود الأقسام المدخلة
    if [ ! -b "$BOOT_PART" ]; then
        echo "خطأ: قسم البوت $BOOT_PART غير موجود."
        exit 1
    fi
    if [ ! -b "$ROOT_PART" ]; then
        echo "خطأ: قسم الروت $ROOT_PART غير موجود."
        exit 1
    fi
    if [ ! -b "$SWAP_PART" ]; then
        echo "خطأ: قسم السواب $SWAP_PART غير موجود."
        exit 1
    fi

    # تنسيق الأقسام (تحذير: ستمسح البيانات)
    echo "سيتم تنسيق الأقسام التالية:"
    echo "  $BOOT_PART -> FAT32 (إذا كان UEFI) أو ext4 (إذا كان BIOS)"
    echo "  $ROOT_PART -> ext4"
    echo "  $SWAP_PART -> swap"
    read -p "هل تريد المتابعة؟ (اكتب 'yes' للمتابعة): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "تم الإلغاء."
        exit 1
    fi

    # تنسيق قسم البوت حسب نوع النظام
    if [ -d /sys/firmware/efi ]; then
        mkfs.vfat -F32 "$BOOT_PART"
    else
        mkfs.ext4 -F -O ^64bit "$BOOT_PART"
    fi

    # تنسيق قسم الروت
    mkfs.ext4 -F "$ROOT_PART"

    # تنسيق قسم السواب
    mkswap "$SWAP_PART"

    echo "تم تنسيق الأقسام بنجاح."
}

# ----------------------- دالة لتركيب الأقسام -----------------------
mount_partitions() {
    echo "=== تركيب الأقسام ==="
    mount "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
    mount "$BOOT_PART" /mnt/boot
    swapon "$SWAP_PART"
    echo "تم التركيب."
}

# ----------------------- دالة لتثبيت النظام -----------------------
install_system() {
    echo "=== تثبيت النظام الأساسي ==="
    setup-disk -m sys /mnt
}

# ----------------------- دالة لتثبيت مُحمّل الإقلاع -----------------------
install_bootloader() {
    echo "=== تثبيت مُحمّل الإقلاع ==="
    if [ -d /sys/firmware/efi ]; then
        echo "نظام UEFI مكتشف. جاري تثبيت GRUB..."
        chroot /mnt apk add grub efibootmgr
        chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Alpine
        chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    else
        echo "نظام BIOS مكتشف. جاري تثبيت Syslinux..."
        chroot /mnt apk add syslinux
        dd bs=440 count=1 conv=notrunc if=/usr/share/syslinux/mbr.bin of="$DISK"
        extlinux -i /mnt/boot
    fi
    echo "تم تثبيت مُحمّل الإقلاع."
}

# ----------------------- دالة للتحقق من الإقلاع -----------------------
verify_boot() {
    echo "=== التحقق من الإقلاع ==="
    if [ -d /sys/firmware/efi ]; then
        if [ -f /mnt/boot/EFI/BOOT/BOOTX64.EFI ]; then
            echo "✓ ملف الإقلاع موجود."
        else
            echo "⚠ لم يتم العثور على ملف الإقلاع، لكن قد يكون GRUB مثبتاً في مكان آخر."
        fi
    else
        if [ -f /mnt/boot/syslinux/syslinux.cfg ]; then
            echo "✓ ملف syslinux.cfg موجود."
        else
            echo "⚠ لم يتم العثور على syslinux.cfg."
        fi
    fi
}

# ----------------------- الدالة الرئيسية -----------------------
main() {
    check_environment
    prepare_partitions
    mount_partitions
    install_system
    install_bootloader
    verify_boot
    echo ""
    echo "=================================================="
    echo "اكتمل تثبيت Alpine Linux بنجاح."
    echo "يمكنك الآن إعادة التشغيل باستخدام: reboot"
    echo "لا تنسَ إزالة وسيط التثبيت."
    echo "=================================================="
}

main
