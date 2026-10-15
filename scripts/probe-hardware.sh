#!/usr/bin/env bash
# probe-hardware.sh — เก็บข้อมูลฮาร์ดแวร์ทั้งเครื่องของ IdeaPad Duet 5i
# เพื่อใช้ยืนยันว่าอุปกรณ์แต่ละชิ้นมี driver ครบหรือไม่
#
# วิธีใช้ (ต้องเป็น root):
#   sudo bash probe-hardware.sh
#
# ผลลัพธ์: tarball ชื่อ duet5i-probe-<วันที่เวลา>.tar.gz ในไดเรกทอรีที่รันสคริปต์
# หมายเหตุ: สคริปต์ "อ่านอย่างเดียว" ไม่แก้ไขค่าอะไรในระบบทั้งสิ้น
#
# เคล็ดลับ: รันตอน "ต่อคีย์บอร์ด folio" ด้วย จะได้ข้อมูลคีย์บอร์ด/ทัชแพตมาด้วย

set -u

if [ "$(id -u)" -ne 0 ]; then
    echo "ต้องรันด้วย sudo (ต้องการสิทธิ์ root เพื่ออ่าน dmesg/dmidecode)" >&2
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
OUTDIR="duet5i-probe-${STAMP}"
mkdir -p "${OUTDIR}"

# ตัวช่วย: รันคำสั่ง + เก็บผล + บันทึกสถานะ ถ้าคำสั่งไหนไม่มีในระบบก็ข้ามไปเลย
run() {
    local name="$1"; shift
    local f="${OUTDIR}/${name}.txt"
    if command -v "$1" >/dev/null 2>&1; then
        "$@" >"${f}" 2>&1
        echo "[ok]   ${name}"
    else
        echo "[skip] ${name} (ไม่มีคำสั่ง $1)" >&2
    fi
}

# ตัวช่วย: อ่านค่าจาก sysfs/proc โดยตรง (ไม่ต้องพึ่งคำสั่งเสริม)
dump_file() {
    local name="$1" path="$2"
    if [ -e "${path}" ]; then
        { echo "--- ${path} ---"; cat "${path}" 2>&1; } >>"${OUTDIR}/${name}.txt"
    fi
}

echo "=== รวบรวมข้อมูลฮาร์ดแวร์ IdeaPad Duet 5i ==="
echo "ผลลัพธ์จะอยู่ใน ${OUTDIR}/"
echo

# ---------- 1. ข้อมูลรุ่นเครื่อง / BIOS ----------
run dmidecode           dmidecode
for f in sys_vendor product_name product_version product_family board_name board_version bios_vendor bios_version bios_date; do
    dump_file dmi-id "/sys/class/dmi/id/${f}"
done

# ---------- 2. เคอร์เนล / ระบบ ----------
run uname               uname -a
run os-release          cat /etc/os-release
run kernel-config       sh -c 'zcat /proc/config.gz 2>/dev/null || echo "ไม่มี /proc/config.gz (ปกติใน distro ทั่วไป)"'
run cmdline             cat /proc/cmdline
run lsmod               lsmod

# ---------- 3. PCI / USB — รายการชิ้นส่วนทั้งเครื่อง ----------
run lspci-nn            lspci -nn
run lspci-verbose       lspci -vvnn          # ต้อง root, เห็นรายละเอียดครบ
run lsusb               lsusb
run lsusb-tree          lsusb -t
# รายละเอียด descriptor เฉพาะอุปกรณ์ HID/คีย์บอร์ด ที่สำคัญต่อการทำ quirk
if command -v lsusb >/dev/null 2>&1; then
    # lsusb บรรทัดละอุปกรณ์ รูปแบบ: "Bus 001 Device 003: ID 046d:c52b ..."
    lsusb | sed -n 's/^Bus \([0-9]*\) Device \([0-9]*\):.*/\1:\2/p' >"${OUTDIR}/.usb-addr-list"
    : >"${OUTDIR}/lsusb-hid-verbose.txt"
    while read -r addr; do
        lsusb -v -s "${addr}" 2>/dev/null | grep -iE 'ID |bInterfaceClass|HID|Vendor|Product|iSerial' \
            >>"${OUTDIR}/lsusb-hid-verbose.txt"
    done <"${OUTDIR}/.usb-addr-list"
    rm -f "${OUTDIR}/.usb-addr-list"
    echo "[ok]   lsusb-hid-verbose"
fi

# ---------- 4. อินพุต: คีย์บอร์ด folio / ทัชแพต / จอสัมผัส ----------
run input-devices       cat /proc/bus/input/devices
if command -v libinput >/dev/null 2>&1; then
    run libinput-list   libinput list-devices
fi
# hid device tree — เห็นชื่อไดรเวอร์ที่จับอุปกรณ์ HID แต่ละตัว
if [ -d /sys/bus/hid/devices ]; then
    : >"${OUTDIR}/hid-devices.txt"
    for d in /sys/bus/hid/devices/*; do
        {
            echo "=== $(basename "${d}") ==="
            for attr in name idVendor idProduct modalias drivers; do
                dump_file hid-devices "${d}/${attr}"
            done
        } >>"${OUTDIR}/hid-devices.txt"
    done
    echo "[ok]   hid-devices"
fi
# i2c bus — จอสัมผัส/ทัชแพต i2c-hid มักอยู่ที่นี่
if [ -d /sys/bus/i2c/devices ]; then
    : >"${OUTDIR}/i2c-devices.txt"
    for d in /sys/bus/i2c/devices/*; do
        { echo "=== $(basename "${d}") ==="; cat "${d}/name" 2>/dev/null; } >>"${OUTDIR}/i2c-devices.txt"
    done
    echo "[ok]   i2c-devices"
fi

# ---------- 5. เสียง / SOF ----------
run aplay-devices       aplay -l
run proc-asound-cards   cat /proc/asound/cards
for card in /proc/asound/card[0-9]*; do
    [ -d "${card}" ] || continue
    dump_file proc-asound-detail "${card}/pcm0p/info"
    dump_file proc-asound-detail "${card}/pcm0c/info"
done
run hw-params           sh -c 'for f in /proc/asound/card*/pcm*/sub0/hw_params; do echo "--- $f"; cat "$f"; done'
# สถานะการโหลดเฟิร์มแวร์ SOF — จุดที่พังบ่อยที่สุดของเครื่อง Alder Lake
dmesg >"${OUTDIR}/dmesg-full.txt" 2>&1
grep -iE 'sof|snd_hda|audio|hdaudio|firmware.*fw_base|DSP' "${OUTDIR}/dmesg-full.txt" \
    >"${OUTDIR}/dmesg-audio.txt" || true
echo "[ok]   dmesg-full + dmesg-audio"
ls /lib/firmware/intel/sof* /lib/firmware/intel/sof-*/* 2>/dev/null \
    >"${OUTDIR}/sof-firmware-files.txt" || echo "ไม่พบเฟิร์มแวร์ SOF ใน /lib/firmware/intel" \
    >"${OUTDIR}/sof-firmware-files.txt"
echo "[ok]   sof-firmware-files"
# UCM (การตั้งค่า routing ลำโพง/ไมค์)
if [ -d /usr/share/alsa/ucm2 ]; then
    ls -R /usr/share/alsa/ucm2 >"${OUTDIR}/alsa-ucm2-list.txt" 2>&1
    echo "[ok]   alsa-ucm2-list"
fi

# ---------- 6. กล้อง / Intel IPU6 ----------
run video-devices       sh -c 'ls -l /dev/video* 2>/dev/null; ls -l /dev/media* 2>/dev/null'
if command -v media-ctl >/dev/null 2>&1; then
    : >"${OUTDIR}/media-ctl-p.txt"
    for m in /dev/media[0-9]*; do
        [ -e "${m}" ] || continue
        { echo "=== ${m} ==="; media-ctl -d "${m}" -p; } >>"${OUTDIR}/media-ctl-p.txt" 2>&1
    done
    echo "[ok]   media-ctl-p"
fi
if command -v v4l2-ctl >/dev/null 2>&1; then
    run v4l2-list         v4l2-ctl --list-devices
fi
grep -iE 'ipu|ivsc|ov01|ov02|hi556|hm11|camera|cis|dell|intel.*cam' "${OUTDIR}/dmesg-full.txt" \
    >"${OUTDIR}/dmesg-camera.txt" || true
echo "[ok]   dmesg-camera"
# sysfs ของ sensor MIPI และ ivsc (ลูกเล่น AI/privacy ของกล้อง Intel)
find /sys/devices -maxdepth 6 \( -name '*ov01*' -o -name '*hi556*' -o -name '*hm11*' -o -name '*ipu6*' -o -name '*ivsc*' \) \
    >"${OUTDIR}/mipi-sensor-sysfs.txt" 2>/dev/null
echo "[ok]   mipi-sensor-sysfs"

# ---------- 7. เซ็นเซอร์ / IIO (หมุนจออัตโนมัติ) ----------
: >"${OUTDIR}/iio-sensors.txt"
for d in /sys/bus/iio/devices/iio:device*; do
    [ -d "${d}" ] || continue
    {
        echo "=== $(basename "${d}") — $(cat "${d}/name" 2>/dev/null) ==="
        ls "${d}" 2>/dev/null
        for f in "${d}"/in_*raw "${d}"/in_*input "${d}"/in_*sampling_frequency "${d}"/mount_matrix; do
            [ -e "$f" ] && { echo "$f = $(cat "$f" 2>/dev/null)"; }
        done
    } >>"${OUTDIR}/iio-sensors.txt"
done
echo "[ok]   iio-sensors"
run iio-service         systemctl status iio-sensor-proxy --no-pager

# ---------- 8. กราฟิก / จอ / ความสว่าง ----------
run drm-cards           sh -c 'for c in /sys/class/drm/card*; do echo "=== $c ==="; cat "$c/device/uevent" 2>/dev/null; done'
if [ -d /sys/class/backlight ]; then
    : >"${OUTDIR}/backlight.txt"
    for b in /sys/class/backlight/*; do
        { echo "=== $(basename "${b}") ==="
          for attr in brightness max_brightness actual_brightness; do
              echo "$attr = $(cat "${b}/${attr}" 2>/dev/null)"
          done; } >>"${OUTDIR}/backlight.txt"
    done
    echo "[ok]   backlight"
fi

# ---------- 9. พลังงาน USB (สาเหตุทัชแพตหลุด) ----------
: >"${OUTDIR}/usb-power.txt"
for u in /sys/bus/usb/devices/*/; do
    [ -f "${u}idVendor" ] || continue
    {
        vid=$(cat "${u}idVendor"); pid=$(cat "${u}idProduct")
        echo "=== ${u} (${vid}:${pid}) — $(cat "${u}/product" 2>/dev/null)"
        echo "  autosuspend_delay_ms = $(cat "${u}power/autosuspend_delay_ms" 2>/dev/null)"
        echo "  control = $(cat "${u}power/control" 2>/dev/null)"
    } >>"${OUTDIR}/usb-power.txt"
done
echo "[ok]   usb-power"

# ---------- 10. สถานะโหมดแท็บเล็ต ----------
for f in /sys/class/input/input*/tablet_mode; do
    [ -e "$f" ] && dump_file tablet-mode "$f"
done
grep -iE 'intel.vbtn|tablet' "${OUTDIR}/dmesg-full.txt" >"${OUTDIR}/dmesg-tablet.txt" || true
echo "[ok]   dmesg-tablet"

# ---------- 11. สรุปสั้นๆ ให้อ่านง่าย ----------
{
    echo "=== สรุปอย่างย่อ IdeaPad Duet 5i probe (${STAMP}) ==="
    echo "รุ่น:        $(cat /sys/class/dmi/id/product_name 2>/dev/null) ($(cat /sys/class/dmi/id/product_family 2>/dev/null))"
    echo "BIOS:        $(cat /sys/class/dmi/id/bios_version 2>/dev/null) ($(cat /sys/class/dmi/id/bios_date 2>/dev/null))"
    echo "เคอร์เนล:    $(uname -r)"
    echo
    echo "-- อุปกรณ์อินพุต (ต้องมีคีย์บอร์ด folio ต่ออยู่) --"
    grep -E 'Name=|Handlers=' /proc/bus/input/devices 2>/dev/null
    echo
    echo "-- การ์ดเสียง --"
    cat /proc/asound/cards 2>/dev/null
    echo
    echo "-- กล้อง /dev/video* --"
    ls /dev/video* 2>/dev/null || echo "!! ไม่พบอุปกรณ์กล้อง"
    echo
    echo "-- เซ็นเซอร์ IIO --"
    for d in /sys/bus/iio/devices/iio:device*; do
        [ -d "$d" ] && cat "${d}/name" 2>/dev/null
    done
    echo
    echo "-- คำเตือนใน dmesg (error/warn/fail) --"
    grep -iE 'error|warn|fail|timeout' "${OUTDIR}/dmesg-full.txt" | tail -40 || true
} >"${OUTDIR}/SUMMARY.txt"
echo "[ok]   SUMMARY.txt"

# ---------- บรรจุเป็น tarball ----------
tar -czf "${OUTDIR}.tar.gz" "${OUTDIR}"
echo
echo "=== เสร็จแล้ว ==="
echo "ไฟล์สรุปอ่านง่าย:  ${OUTDIR}/SUMMARY.txt"
echo "ไฟล์ส่งต่อ (tarball): ${OUTDIR}.tar.gz"
echo
echo "เคล็ดลับ: ถ้ายังไม่ได้ต่อคีย์บอร์ด folio ตอนรัน ให้ต่อแล้วรันซ้ำอีกครั้ง"
