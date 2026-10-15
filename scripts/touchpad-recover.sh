#!/usr/bin/env bash
# touchpad-recover.sh — กู้คืนทัชแพต/คีย์บอร์ด folio ที่ "หลุด" โดยไม่ต้องรีบูต
#
# วิธีทำงาน (เรียงตามความแรง):
#   1. unbind → bind อุปกรณ์ USB ของ folio (เท่าถอด-ประกบใหม่แบบซอฟต์แวร์)
#   2. re-enumerate ผ่านไฟล์ authorized (แรงกว่า)
#   3. (--hard) รีเซ็ตคอนโทรลเลอร์ xHCI ทั้งหมด — ใช้เมื่ออุปกรณ์หายจากบัสไปเลย
#
# วิธีใช้:
#   sudo bash touchpad-recover.sh --list            ดูอุปกรณ์ (พร้อม VID:PID)
#   sudo bash touchpad-recover.sh                   กู้คืนแบบ auto
#   sudo bash touchpad-recover.sh 1234:5678         กู้คืนเฉพาะอุปกรณ์ที่ระบุ VID:PID
#   sudo bash touchpad-recover.sh --hard            กู้คืน + รีเซ็ตคอนโทรลเลอร์ USB
#   bash  touchpad-recover.sh --present [id]        แค่ตรวจว่า folio ยังอยู่ (ใช้โดย watchdog)
#
# เคล็ดลับ: ผูกเป็นปุ่มลัดได้ เช่น Super+T (ตั้ง sudo NOPASSWD เฉพาะคำสั่งนี้)

set -u

# ตำแหน่ง sysfs ของอุปกรณ์ USB (override ได้เพื่อการทดสอบ: DUET5I_USB_SYSFS=...)
USB_DEVICES="${DUET5I_USB_SYSFS:-/sys/bus/usb/devices}"
XHCI_DRIVER=/sys/bus/pci/drivers/xhci_hcd

say() { printf '%s\n' "$*"; }

read_attr() { cat "$1" 2>/dev/null; }

# รวมข้อมูลอุปกรณ์ USB แต่ละตัว (เฉพาะที่มี idVendor = เป็นอุปกรณ์จริง ไม่ใช่ hub root)
# ผลลัพธ์ 5 ฟิลด์คั่นด้วย tab: ที่อยู่  vid:pid  ชื่อ  removable  hid(0/1)
list_devices() {
    for dev in "$USB_DEVICES"/*/; do
        dev="${dev%/}"
        [ -f "$dev/idVendor" ] || continue
        vid=$(read_attr "$dev/idVendor"); pid=$(read_attr "$dev/idProduct")
        product=$(read_attr "$dev/product")
        removable=$(read_attr "$dev/removable")
        # มี interface HID (bInterfaceClass=3) หรือไม่
        hid=0
        for iface in "$dev":*/; do
            [ -f "$iface/bInterfaceClass" ] || continue
            [ "$(read_attr "$iface/bInterfaceClass")" = "3" ] && hid=1
        done
        printf '%s\t%s:%s\t%s\t%s\t%s\n' \
            "${dev##*/}" "$vid" "$pid" "${product:-<ไม่มีชื่อ>}" "$removable" "$hid"
    done
}

# เลือกอุปกรณ์เป้าหมาย: ถ้ากำหนด VID:PID ใช้ค่านั้น ไม่งั้นเอา HID ที่เป็นอุปกรณ์ภายใน
pick_targets() {
    wanted=$(printf '%s' "$1" | tr 'A-F' 'a-f')
    list_devices | while IFS=$'\t' read -r addr vidpid product removable hid; do
        if [ -n "$wanted" ] && [ "$wanted" != "auto" ]; then
            [ "$vidpid" = "$wanted" ] && printf '%s\n' "$addr"
        else
            [ "$hid" = "1" ] && [ "$removable" = "unknown" ] && printf '%s\n' "$addr"
        fi
    done
}

# รีเซ็ตคอนโทรลเลอร์ xHCI ทุกตัว: อุปกรณ์ USB ทั้งหมดจะถูกตรวจพบใหม่
# (สำหรับกรณี folio หายจากบัสไปเลย จนไม่มีตัวให้ unbind/bind)
reset_xhci() {
    found=0
    for ctrl in "$XHCI_DRIVER"/*/; do
        [ -d "$ctrl" ] || continue
        found=1
        addr="${ctrl%/}"; addr="${addr##*/}"
        say "== รีเซ็ตคอนโทรลเลอร์ USB: $addr =="
        printf '%s' "$addr" > "$XHCI_DRIVER/unbind" 2>/dev/null || true
        sleep 1
        if printf '%s' "$addr" > "$XHCI_DRIVER/bind" 2>/dev/null; then
            say "   รีเซ็ตสำเร็จ — อุปกรณ์ USB จะกลับมาใน 1-2 วินาที"
        else
            say "   bind ไม่สำเร็จ" >&2
            status=1
        fi
    done
    [ "$found" = "0" ] && say "   (ไม่พบคอนโทรลเลอร์ xHCI ในระบบนี้)"
}

case "${1:-auto}" in
    -l|--list)
        say "อุปกรณ์ USB ทั้งหมด (รูปแบบ: ที่อยู่  VID:PID  ชื่อ  removable  hid):"
        list_devices | while IFS=$'\t' read -r addr vidpid product removable hid; do
            say "  $addr  $vidpid  $product  removable=$removable  hid=$hid"
        done
        say "เคล็ดลับ: ค่า removable=unknown + hid=1 คือผู้สมัครตัวจริงของ folio"
        exit 0
        ;;
    -h|--help)
        sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
    --present)
        # โหมดตรวจสถานะ (ไม่ต้องเป็น root) — ใช้โดย folio-watchdog
        pick_targets "${2:-auto}" | grep -q . && exit 0 || exit 1
        ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    say "ต้องรันด้วย sudo" >&2
    exit 1
fi

if ! [ -d "$USB_DEVICES" ]; then
    say "!! ไม่พบ $USB_DEVICES (ต้องรันบนเครื่องที่มีบัส USB)" >&2
    exit 1
fi

HARD=0
selector="${1:-auto}"
if [ "$selector" = "--hard" ]; then
    HARD=1
    selector="${2:-auto}"
fi

status=0
targets=$(pick_targets "$selector")
if [ -z "$targets" ]; then
    say "!! ไม่พบอุปกรณ์ที่ตรงเงื่อนไข ($selector)"
    if [ "$HARD" = "1" ]; then
        say "   อุปกรณ์หายจากบัส — รีเซ็ตคอนโทรลเลอร์เพื่อให้ตรวจพบใหม่"
        reset_xhci
    else
        say "   ถ้า folio หายไปเลย ให้ลอง: sudo bash $0 --hard" >&2
        say "   หรือดูอุปกรณ์ทั้งหมด: sudo bash $0 --list แล้วระบุ VID:PID" >&2
        status=1
    fi
else
    for addr in $targets; do
        say "== กู้คืน $addr =="
        # วิธีที่ 1: unbind → bind ผ่านไดรเวอร์ usb (พอ 90% ของกรณี)
        if [ -w /sys/bus/usb/drivers/usb/unbind ]; then
            if printf '%s' "$addr" > /sys/bus/usb/drivers/usb/unbind 2>/dev/null; then
                sleep 0.3
                printf '%s' "$addr" > /sys/bus/usb/drivers/usb/bind 2>/dev/null \
                    && say "   unbind/bind สำเร็จ" || { say "   bind ไม่สำเร็จ ลองวิธีถัดไป"; status=1; }
            fi
        fi
        # วิธีที่ 2 (แรงกว่า): ตัด-ต่อ authorized = re-enumerate เหมือนถอด-ประกบใหม่
        if [ "$status" -ne 0 ] && [ -w "$USB_DEVICES/$addr/authorized" ]; then
            printf '0' > "$USB_DEVICES/$addr/authorized" 2>/dev/null
            sleep 0.5
            printf '1' > "$USB_DEVICES/$addr/authorized" 2>/dev/null \
                && say "   re-enumerate ผ่าน authorized สำเร็จ" || status=1
        fi
    done
    # วิธีที่ 3 (--hard): ยังไม่สำเร็จหรือขอแบบชัวร์ → รีเซ็ตคอนโทรลเลอร์
    if [ "$HARD" = "1" ]; then
        reset_xhci
    fi
fi

if [ "$status" -eq 0 ]; then
    say "เสร็จ — ทัชแพต/คีย์บอร์ดควรกลับมาทำงานทันที"
    say "ถ้ายังไม่กลับมา: ถอด folio แล้วประกบใหม่ หรือดู docs/03-troubleshooting.md"
else
    say "!! มีขั้นตอนบางส่วนไม่สำเร็จ ดูข้อความด้านบน" >&2
fi
exit "$status"
