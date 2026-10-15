#!/usr/bin/env bash
# auto-tune.sh — คำสั่งเดียวพา Duet 5i ไปให้สุดทางที่ทำได้โดยอัตโนมัติ
#
# สิ่งที่สคริปต์นี้ทำ (ตามลำดับ):
#   1. ติดตั้งฐานทั้งหมด (แพ็กเกจ + udev + iio-sensor-proxy + watchdog)
#      โดยเรียก post-install.sh --watchdog ให้เอง
#   2. ตรวจจับ VID:PID จริงของ folio แล้ว "กรอกค่าให้อัตโนมัติ":
#      เขียน udev rule เฉพาะตัว + สอน watchdog ให้จ้อง folio ตัวจริง
#   3. ตรวจทุกระบบ (เสียง/เซ็นเซอร์/กล้อง/แสงจอ/แบต/Wi-Fi/จอสัมผัส/โหมดแท็บเล็ต)
#      พิมพ์รายงาน ✅/❌ พร้อมวิธีแก้ย่อของทุกข้อ ❌
#   4. เก็บข้อมูลฮาร์ดแวร์ทั้งเครื่อง (probe) เป็น tarball ไว้ส่งต่อ
#
# วิธีใช้ (บนเครื่อง Duet 5i ที่ลง Fedora แล้ว):
#   sudo bash scripts/auto-tune.sh
#   sudo bash scripts/auto-tune.sh --check-only   ← ตรวจอย่างเดียว ไม่แตะอะไร (ใช้ซ้ำได้)
#
# ถ้ามีข้อ ❌ หลังรัน: ส่งไฟล์ duet5i-probe-*.tar.gz กลับได้เลย
# ข้อมูลครบทุกเครื่อง = แก้จุดที่เหลือได้ถูกตัว

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ONLY=0
[ "${1:-}" = "--check-only" ] && CHECK_ONLY=1

if [ "$(id -u)" -ne 0 ] && [ "$CHECK_ONLY" -eq 0 ]; then
    echo "ต้องรันด้วย sudo (--check-only ใช้ได้โดยไม่ต้องเป็น root)" >&2
    exit 1
fi

say() { printf '%s\n' "$*"; }

# ---------- 1) ฐานทั้งหมด ----------
if [ "$CHECK_ONLY" -eq 0 ]; then
    say "=================================================="
    say "ขั้นที่ 1/4 — ติดตั้งฐาน (แพ็กเกจ + udev + watchdog)"
    say "=================================================="
    bash "$ROOT/scripts/post-install.sh" --watchdog || true
fi

# ---------- 2) ตรวจจับ folio แล้วกรอกค่าให้อัตโนมัติ ----------
say ""
say "=================================================="
say "ขั้นที่ 2/4 — ตรวจจับ folio และกรอกค่าให้อัตโนมัติ"
say "=================================================="
# ผู้สมัคร folio = อุปกรณ์ HID ภายใน (แถวอุปกรณ์จริงเท่านั้น: field 2 เป็น vid:pid)
# ถ้าเจอหลายตัว ให้ prefer ของ Lenovo (vendor 17ef) ก่อน
folio_id=$(bash "$ROOT/scripts/touchpad-recover.sh" --list 2>/dev/null \
    | awk '$2 ~ /^[0-9a-f]{4}:[0-9a-f]{4}$/ && /removable=unknown/ && /hid=1/ {print $2}' \
    | { grep -m1 '^17ef:' || true; } 2>/dev/null)
if [ -z "$folio_id" ]; then
    folio_id=$(bash "$ROOT/scripts/touchpad-recover.sh" --list 2>/dev/null \
        | awk '$2 ~ /^[0-9a-f]{4}:[0-9a-f]{4}$/ && /removable=unknown/ && /hid=1/ {print $2; exit}')
fi

if [ -n "$folio_id" ]; then
    say "พบ folio: VID:PID = $folio_id"
    if [ "$CHECK_ONLY" -eq 0 ]; then
        vid="${folio_id%%:*}"; pid="${folio_id##*:}"
        printf '# สร้างอัตโนมัติโดย auto-tune.sh (folio ที่ตรวจพบ: %s)\n' "$folio_id" \
            > /etc/udev/rules.d/98-duet5i-folio-detected.rules
        printf 'SUBSYSTEM=="usb", ATTR{idVendor}=="%s", ATTR{idProduct}=="%s", TEST=="power/control", ATTR{power/control}="on"\n' "$vid" "$pid" \
            >> /etc/udev/rules.d/98-duet5i-folio-detected.rules
        printf 'SUBSYSTEM=="usb", ATTR{idVendor}=="%s", ATTR{idProduct}=="%s", TEST=="power/autosuspend_delay_ms", ATTR{power/autosuspend_delay_ms}="-1"\n' "$vid" "$pid" \
            >> /etc/udev/rules.d/98-duet5i-folio-detected.rules
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger 2>/dev/null || true
        say "เขียน udev rule เฉพาะ folio แล้ว (/etc/udev/rules.d/98-duet5i-folio-detected.rules)"
        mkdir -p /etc/systemd/system/duet5i-folio-watchdog.service.d
        printf '[Service]\nEnvironment=DUET5I_FOLIO_ID=%s\n' "$folio_id" \
            > /etc/systemd/system/duet5i-folio-watchdog.service.d/override.conf
        systemctl daemon-reload 2>/dev/null || true
        systemctl restart duet5i-folio-watchdog 2>/dev/null || true
        say "ตั้ง watchdog ให้จ้อง folio ตัวจริงแล้ว"
    else
        say "(โหมดตรวจอย่างเดียว — ยังไม่กรอกค่า รันโดยไม่มี --check-only เพื่อกรอก)"
    fi
else
    say "!! ยังไม่พบ folio — ต่อคีย์บอร์ด folio ให้แน่นแล้วรันด้วย sudo อีกครั้ง"
    say "   (watchdog ยังทำงานแบบ auto อยู่ แค่ไม่ได้จ้องเฉพาะตัว)"
fi

# ---------- 3) ตรวจทุกระบบ ----------
say ""
say "=================================================="
say "ขั้นที่ 3/4 — ตรวจสอบทุกระบบ"
say "=================================================="
ok=0; bad=0
report() { # report <ชื่อระบบ> <ผ่าน:0/1> <วิธีแก้ถ้าไม่ผ่าน>
    if [ "$2" -eq 0 ]; then say "  ✅ $1"; ok=$((ok+1))
    else say "  ❌ $1"; say "     → แก้: $3"; bad=$((bad+1)); fi
}

# เสียง (SOF)
grep -q 'sof' /proc/asound/cards 2>/dev/null \
    && report "เสียง (SOF โหลดแล้ว)" 0 "" \
    || report "เสียง (SOF)" 1 "dnf install sof-firmware แล้วรีบูต — ดู docs/03-troubleshooting.md"

# เซ็นเซอร์หมุนจอ
if ls /sys/bus/iio/devices/iio:device*/name >/dev/null 2>&1 \
   && systemctl is-active --quiet iio-sensor-proxy 2>/dev/null; then
    report "เซ็นเซอร์หมุนจอ (IIO + proxy)" 0 ""
else
    report "เซ็นเซอร์หมุนจอ" 1 "systemctl enable --now iio-sensor-proxy; ถ้าไม่มี iio:device* ส่งผล probe ให้วิเคราะห์"
fi

# กล้อง
n_video=$(ls /dev/video* 2>/dev/null | wc -l | tr -d ' ')
[ "$n_video" -gt 0 ] \
    && report "กล้อง (/dev/video* มี $n_video ตัว — ทดสอบด้วย qcam)" 0 "" \
    || report "กล้อง (IPU6)" 1 "รีบูต 1 ครั้ง (อาการ cold boot) ถ้ายังไม่มี ดูหัวข้อกล้องใน docs/03"

# แสงจอ
backlight=$(ls /sys/class/backlight 2>/dev/null | head -1)
[ -n "$backlight" ] \
    && report "แสงจอ (backlight: $backlight)" 0 "" \
    || report "แสงจอ (backlight)" 1 "ปกติ i915 ควรสร้างให้ — ส่งผล probe ให้วิเคราะห์"

# แบตเตอรี่
ls /sys/class/power_supply/*/type >/dev/null 2>&1 \
    && report "แบตเตอรี่" 0 "" \
    || report "แบตเตอรี่" 1 "ส่งผล probe ให้วิเคราะห์"

# Wi-Fi
ls /sys/class/ieee80211 >/dev/null 2>&1 \
    && report "Wi-Fi" 0 "" \
    || report "Wi-Fi" 1 "ตรวจ iwlwifi: dmesg | grep iwl — ปกติมีมาให้"

# จอสัมผัส
grep -qiE 'touch' /proc/bus/input/devices 2>/dev/null \
    && report "จอสัมผัส" 0 "" \
    || report "จอสัมผัส" 1 "ส่งผล probe (ส่วน i2c/hid) ให้วิเคราะห์"

# คีย์บอร์ด folio
if [ -n "$folio_id" ]; then
    report "คีย์บอร์ด folio (VID:PID $folio_id)" 0 ""
else
    report "คีย์บอร์ด folio" 1 "ต่อ folio ให้แน่นแล้วรัน sudo bash $0 ซ้ำ"
fi

# โหมดแท็บเล็ต (tablet_mode switch)
found_switch=""
for f in /sys/class/input/input*/tablet_mode; do
    [ -e "$f" ] && found_switch="$f" && break
done
[ -n "$found_switch" ] \
    && report "โหมดแท็บเล็ต (พบ tablet_mode switch)" 0 "" \
    || report "โหมดแท็บเล็ต" 1 "ไม่มี switch — DevOs จะใช้การหายของ USB folio แทนได้ (กรอก folioId ใน Settings)"

# watchdog
systemctl is-active --quiet duet5i-folio-watchdog 2>/dev/null \
    && report "watchdog ทัชแพต (กำลังทำงาน)" 0 "" \
    || report "watchdog ทัชแพต" 1 "systemctl status duet5i-folio-watchdog — ติดตั้งด้วย post-install.sh --watchdog"

say ""
say "ผลรวม: ผ่าน $ok / ไม่ผ่าน $bad"

# ---------- 4) เก็บข้อมูลเพื่อส่งต่อ ----------
say ""
say "=================================================="
say "ขั้นที่ 4/4 — เก็บข้อมูลฮาร์ดแวร์เพื่อส่งต่อ"
say "=================================================="
if [ "$CHECK_ONLY" -eq 0 ]; then
    bash "$ROOT/scripts/probe-hardware.sh" || true
else
    say "(โหมดตรวจอย่างเดียว — รันปกติเพื่อเก็บ probe)"
fi

say ""
if [ "$bad" -eq 0 ]; then
    say "🎉 ทุกระบบผ่าน — เครื่องนี้พร้อมใช้งานเต็มรูปแบบ"
else
    say "มี $bad ระบบที่ยังไม่ผ่าน — ทำตามคำแนะนำ \"→ แก้:\" ด้านบน"
    say "แก้แล้วรันซ้ำได้: sudo bash $0 --check-only"
    say "ส่งไฟล์ duet5i-probe-*.tar.gz ในโฟลเดอร์นี้กลับให้ผู้พัฒนาได้เลย จะได้แก้ให้ตรงจุด"
fi
exit 0
