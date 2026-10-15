#!/usr/bin/env bash
# post-install.sh — ติดตั้งส่วนประกอบที่ Duet 5i ต้องใช้ หลังติดตั้ง Linux เสร็จ
#
# สิ่งที่สคริปต์นี้ทำ:
#   1. ลงเฟิร์มแวร์/แพ็กเกจ: SOF (เสียง), libcamera + v4l-utils (กล้อง), iio-sensor-proxy (หมุนจอ)
#   2. ติดตั้ง udev rule ปิด USB autosuspend ของคีย์บอร์ด folio (แก้ทัชแพตหลุดเป็นพักๆ)
#   3. เปิดบริการ iio-sensor-proxy
#   4. รายงานสถานะแต่ละส่วนว่าติดตั้งสำเร็จหรือไม่
#
# รองรับ: Fedora (dnf) / Ubuntu-Debian (apt) — รันได้ซ้ำ (idempotent)
#   sudo bash post-install.sh

set -u

if [ "$(id -u)" -ne 0 ]; then
    echo "ต้องรันด้วย sudo" >&2
    exit 1
fi

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
