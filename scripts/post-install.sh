#!/usr/bin/env bash
# post-install.sh — ติดตั้งส่วนประกอบที่ Duet 5i ต้องใช้ หลังติดตั้ง Linux เสร็จ
#
# สิ่งที่สคริปต์นี้ทำ:
#   1. ลงเฟิร์มแวร์/แพ็กเกจ: SOF (เสียง), libcamera + v4l-utils (กล้อง), iio-sensor-proxy (หมุนจอ)
#   2. ติดตั้ง udev rule ปิด USB autosuspend ของคีย์บอร์ด folio (แก้ทัชแพตหลุดเป็นพักๆ)
#   3. เปิดบริการ iio-sensor-proxy
#   4. รายงานสถานะแต่ละส่วนว่าติดตั้งสำเร็จหรือไม่
#
# ตัวเลือก:
#   --stable-input   เพิ่มชั้นความเสถียรสูงสุดของอินพุต: ปิด USB autosuspend ทั้งระบบ
#                    ผ่าน kernel parameter (usbcore.autosuspend=-1) + สร้าง grub config ใหม่
#                    ใช้เมื่อ udev rule อย่างเดียวยังไม่พอ — ต้องรีบูตหนึ่งครั้งหลังใช้
#   --watchdog       ติดตั้ง+เปิด duet5i-folio-watchdog: service เฝ้า folio ตลอดเวลา
#                    ถ้าอุปกรณ์หายจากบัส กู้คืนให้เองอัตโนมัติ (unbind/bind ถึงระดับ xHCI)
#                    ทำให้อาการ "ทัชแพตหลุด" หายเองในไม่กี่วินาทีโดยไม่ต้องรีบูต
#
# รองรับ: Fedora (dnf) / Ubuntu-Debian (apt) — รันได้ซ้ำ (idempotent)
#   sudo bash post-install.sh [--stable-input] [--watchdog]

set -u

if [ "$(id -u)" -ne 0 ]; then
    echo "ต้องรันด้วย sudo" >&2
    exit 1
fi

# ---------- ตัวเลือก: ปิด USB autosuspend ทั้งระบบ (--stable-input) ----------
apply_stable_input() {
    echo "== ปิด usbcore.autosuspend ทั้งระบบ (ชั้นความเสถียรสูงสุดของอินพุต) =="
    if grep -qr 'usbcore.autosuspend' /proc/cmdline 2>/dev/null; then
        echo "เปิดใช้แล้วในพารามิเตอร์เคอร์เนลปัจจุบัน — ไม่ต้องทำซ้ำ"
        return 0
    fi
    if command -v dnf >/dev/null 2>&1; then
        # Fedora: แก้ /etc/default/grub ตรงๆ แล้ว regenerate
        if [ -f /etc/default/grub ] && grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
            sed -i 's/^GRUB_CMDLINE_LINUX="\([^"]*\)"/GRUB_CMDLINE_LINUX="\1 usbcore.autosuspend=-1"/' /etc/default/grub
            grub2-mkconfig -o /boot/grub2/grub.cfg 2>/dev/null \
                || grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg 2>/dev/null \
                || echo "!! รัน grub2-mkconfig ไม่สำเร็จ — ดูคู่มือของ distro" >&2
        else
            echo "!! ไม่พบ /etc/default/grub ตามรูปแบบที่คาด — แก้ GRUB_CMDLINE_LINUX ด้วยตัวเอง" >&2
        fi
    elif command -v apt >/dev/null 2>&1; then
        # Ubuntu/Debian: ใช้ drop-in ที่ update-grub รวมให้อัตโนมัติ
        mkdir -p /etc/default/grub.d
        printf 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT usbcore.autosuspend=-1"\n' \
            > /etc/default/grub.d/duet5i-folio.cfg
        update-grub 2>/dev/null || echo "!! รัน update-grub ไม่สำเร็จ — ดูคู่มือของ distro" >&2
    else
        echo "!! ไม่รู้จัก distro นี้ — เพิ่ม usbcore.autosuspend=-1 ใน bootloader ด้วยตัวเอง" >&2
        return 1
    fi
    # ทางเลือกสำหรับกรณีฮาร์ดแวร์ยังหนึ่ย (แก้ปัญหา HID หลุด/กระตุกในอีกรูปแบบ):
    #  แก้ไฟล์นี้แล้วเอา '#' หน้าบรรทัด options ออก แล้วรีบูต
    mkdir -p /etc/modprobe.d
    printf '# ตัวเลือกเสริมความเสถียรอินพุต (เปิดใช้โดยเอา comment ออก):\n# options usbhid mousepoll=8\n' \
        > /etc/modprobe.d/duet5i-folio.conf
    echo "เสร็จ — รีบูตหนึ่งครั้งเพื่อให้พารามิเตอร์มีผล"
}

# ---------- ตัวเลือก: watchdog กู้คืนอุปกรณ์อินพุตอัตโนมัติ (--watchdog) ----------
install_watchdog() {
    echo "== ติดตั้ง folio watchdog (กู้คืนทัชแพต/คีย์บอร์ดอัตโนมัติ) =="
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "!! ไม่พบ systemctl — watchdog รองรับเฉพาะระบบที่ใช้ systemd" >&2
        return 1
    fi
    install -m 0755 "$SCRIPT_DIR/touchpad-recover.sh" /usr/local/sbin/duet5i-touchpad-recover.sh
    install -m 0755 "$SCRIPT_DIR/folio-watchdog.sh" /usr/local/sbin/duet5i-folio-watchdog.sh
    install -m 0644 "$SCRIPT_DIR/../systemd/duet5i-folio-watchdog.service" /etc/systemd/system/duet5i-folio-watchdog.service
    systemctl daemon-reload
    systemctl enable --now duet5i-folio-watchdog 2>/dev/null \
        && echo "เปิด duet5i-folio-watchdog แล้ว (ตรวจทุก 5 วินาที — แก้ค่าได้ด้วย systemctl edit)" \
        || echo "!! เปิด service ไม่สำเร็จ (ลอง: systemctl status duet5i-folio-watchdog)"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UDEV_SRC="${SCRIPT_DIR}/../udev/99-duet5i-folio.rules"
UDEV_DST="/etc/udev/rules.d/99-duet5i-folio.rules"

# ---------- ตรวจ package manager ----------
PKG=""
if   command -v dnf >/dev/null 2>&1; then PKG=dnf
elif command -v apt >/dev/null 2>&1; then PKG=apt
elif command -v zypper >/dev/null 2>&1; then PKG=zypper
elif command -v pacman >/dev/null 2>&1; then PKG=pacman
else
    echo "!! ไม่พบ package manager ที่รองรับ (dnf/apt/zypper/pacman)" >&2
    exit 1
fi
echo "== ตรวจพบ distro แบบ: ${PKG} =="

for argument in "$@"; do
    case "$argument" in
        --stable-input) apply_stable_input ;;
        --watchdog) install_watchdog ;;
        *) echo "!! ไม่รู้จักตัวเลือก: $argument (ที่รองรับ: --stable-input, --watchdog)" >&2 ;;
    esac
done

# ---------- 1. ติดตั้งแพ็กเกจ ----------
# หมายเหตุ: บางแพ็กเกจอาจชื่อต่างกันตาม distro — ตัวไหนลงไม่ได้จะข้ามและเตือน
install_pkgs() {
    case "${PKG}" in
        dnf)
            # บน Fedora: sof-firmware มักติดตั้งมาอยู่แล้ว ลงซ้ำไม่เป็นไร
            dnf install -y sof-firmware iio-sensor-proxy \
                           libcamera libcamera-tools libcamera-gstreamer \
                           v4l-utils || true
            ;;
        apt)
            apt update
            apt install -y sof-firmware iio-sensor-proxy \
                           libcamera-tools libcamera-gstreamer \
                           v4l-utils || true
            # กล้อง IPU6 บน Ubuntu 24.04+ ต้องใช้ชุดเสริมของ Intel (อยู่ระหว่างขยายการรองรับ)
            # ถ้าลงไม่สำเร็จ ให้อ่าน docs/03-troubleshooting.md หัวข้อกล้อง
            apt install -y intel-ipu6-dkms intel-ivsc-dkms \
                           intel-ipu6-camera-bins intel-ipu6-camera-hal || \
                echo "!! (ไม่เป็นอันตราย) แพ็กเกจกล้อง intel-ipu6 ยังไม่พร้อมใน repo นี้"
            ;;
        zypper)
            zypper --non-interactive install sof-firmware iio-sensor-proxy \
                    libcamera-tools v4l-utils || true
            ;;
        pacman)
            pacman -Sy --needed --noconfirm sof-firmware iio-sensor-proxy \
                    libcamera libcamera-tools libcamera-gstreamer v4l-utils || true
            ;;
    esac
}
echo
echo "== [1/3] ติดตั้งแพ็กเกจ (เสียง/กล้อง/เซ็นเซอร์) =="
install_pkgs

# ---------- 2. udev rule ปิด autosuspend ของ folio ----------
echo
echo "== [2/3] ติดตั้ง udev rule คีย์บอร์ด folio =="
if [ -f "${UDEV_SRC}" ]; then
    install -m 0644 "${UDEV_SRC}" "${UDEV_DST}"
    echo "ติดตั้ง ${UDEV_DST} แล้ว"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    # เตือนถ้า rule ยังเป็นเวอร์ชัน placeholder ที่ต้องกรอก VID:PID
    if grep -q 'XXXX' "${UDEV_DST}" 2>/dev/null; then
        echo "!! โปรดทำตามขั้นตอนนี้ให้ครบ:"
        echo "   1) ต่อคีย์บอร์ด folio แล้วรัน: lsusb"
        echo "   2) หาบรรทัดคีย์บอร์ด Lenovo แล้วจด VID:PID (รูปแบบ 1234:5678)"
        echo "   3) แก้ไข ${UDEV_DST} เปลี่ยน XXXX:XXXX เป็นค่าจริง แล้วรัน:"
        echo "      sudo udevadm control --reload && sudo udevadm trigger"
    fi
else
    echo "!! ไม่พบ ${UDEV_SRC} — ข้ามขั้นตอนนี้"
fi

# ---------- 3. เปิดบริการเซ็นเซอร์ ----------
echo
echo "== [3/3] เปิดบริการ iio-sensor-proxy (หมุนจออัตโนมัติ) =="
systemctl enable --now iio-sensor-proxy 2>/dev/null \
    && echo "เปิด iio-sensor-proxy แล้ว" \
    || echo "!! เปิด iio-sensor-proxy ไม่สำเร็จ (ลอง: systemctl status iio-sensor-proxy)"

# ---------- รายงานผล ----------
echo
echo "================ รายงานสถานะ ================"
echo "-- เสียง (SOF) --"
if grep -q sof /proc/asound/cards 2>/dev/null; then
    echo "พบการ์ดเสียง SOF — เสียงพร้อมใช้งาน"
    cat /proc/asound/cards
else
    echo "ยังไม่พบการ์ด SOF — รีบูตหนึ่งครั้งแล้วดูผลจาก: aplay -l"
fi
echo
echo "-- กล้อง --"
n_cam=$(ls /dev/video* 2>/dev/null | wc -l)
if [ "${n_cam}" -gt 0 ]; then
    echo "พบอุปกรณ์ video ${n_cam} ตัว: $(ls /dev/video* 2>/dev/null | tr '\n' ' ')"
    echo "ทดสอบ: qcam  (หรือ cheese บน GNOME — กล้อง MIPI ต้องใช้แอปที่รองรับ libcamera)"
else
    echo "ยังไม่พบ /dev/video* — รีบูตแล้วรัน: sudo bash ${SCRIPT_DIR}/probe-hardware.sh"
fi
echo
echo "-- เซ็นเซอร์หมุนจอ --"
if systemctl is-active --quiet iio-sensor-proxy; then
    echo "iio-sensor-proxy ทำงานอยู่ — ลองหมุนเครื่องจริง หน้าจอควรหมุนตาม"
    echo "ทดสอบด้วยคำสั่ง: monitor-sensor"
else
    echo "iio-sensor-proxy ยังไม่ทำงาน — อาจยังไม่มีไดรเวอร์เซ็นเซอร์ ดูผลจาก probe-hardware.sh"
fi
echo
echo "เสร็จแล้ว — แนะนำให้รีบูตหนึ่งครั้งเพื่อให้เฟิร์มแวร์/บริการทุกตัวเริ่มทำงานสมบูรณ์"
