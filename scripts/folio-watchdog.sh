#!/usr/bin/env bash
# folio-watchdog.sh — เฝ้าคีย์บอร์ด/ทัชแพต folio และกู้คืนให้เองโดยอัตโนมัติ
#
# หลักการ: ทุก N วินาที ตรวจว่าอุปกรณ์ folio ยังอยู่บนบัส USB หรือไม่
# ถ้าหาย (อาการ "ทัชแพตหลุด" ในรูปแบบที่อุปกรณ์ดรอปออกจากบัส) จะเรียก
# touchpad-recover.sh --hard ทันที — กู้คืนโดยผู้ใช้ไม่ต้องทำอะไร ไม่ต้องรีบูต
#
# ตั้งค่าผ่านตัวแปรสภาพแวดล้อม (override ได้ใน systemd unit หรือตอนรัน):
#   DUET5I_FOLIO_ID          VID:PID ของ folio เช่น 17ef:60ef (ค่า auto = อุปกรณ์
#                            HID ภายในทั้งหมด แนะนำให้กรอกค่าจริงเมื่อรู้แล้ว)
#   DUET5I_WATCHDOG_INTERVAL รอย่างห่างการตรวจ วินาที (default 5)
#
# ใช้คู่กับ systemd/duet5i-folio-watchdog.service (ติดตั้งผ่าน post-install.sh --watchdog)
# ทดสอบ: bash folio-watchdog.sh --once   (รันหนึ่งรอบแล้วออก)

set -u

interval="${DUET5I_WATCHDOG_INTERVAL:-5}"
folio_id="${DUET5I_FOLIO_ID:-auto}"
# ตำแหน่งตัวกู้คืน: เมื่อติดตั้งผ่าน post-install.sh อยู่ที่ /usr/local/sbin
# หรือถัดจากไฟล์นี้ใน source tree (สำหรับรัน/ทดสอบจาก repo)
recover="/usr/local/sbin/duet5i-touchpad-recover.sh"
if ! [ -f "$recover" ]; then
    sibling="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/touchpad-recover.sh"
    [ -f "$sibling" ] && recover="$sibling"
fi

log() { printf '%s\n' "$*"; command -v logger >/dev/null 2>&1 && logger -t duet5i-folio -- "$*" || true; }

once=0
[ "${1:-}" = "--once" ] && once=1

while :; do
    if bash "$recover" --present "$folio_id" >/dev/null 2>&1; then
        [ "$once" = "1" ] && log "folio ปกติ" && exit 0
    else
        log "folio หายจากบัส — กู้คืนอัตโนมัติ"
        bash "$recover" --hard "$folio_id" >/dev/null 2>&1
        log "คำสั่งกู้คืนทำงานแล้ว รอการตรวจพบรอบถัดไป"
        [ "$once" = "1" ] && exit 0
    fi
    sleep "$interval"
done
