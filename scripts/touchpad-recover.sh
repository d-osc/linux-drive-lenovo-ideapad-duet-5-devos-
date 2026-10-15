#!/usr/bin/env bash
# touchpad-recover.sh — กู้คืนทัชแพต/คีย์บอร์ด folio ที่ "หลุด" โดยไม่ต้องรีบูต
#
# วิธีทำงาน: จับคู่ (unbind → bind) อุปกรณ์ USB ของ folio หรือสั่ง re-enumerate
# ผ่านไฟล์ authorized — เทียบเท่าการถอด-ประกบ folio ใหม่ แต่ทำด้วยซอฟต์แวร์
# ใช้ได้ทั้งแบบกำหนด VID:PID เอง และแบบ auto (อุปกรณ์ HID บน USB ภายในของเครื่อง)
#
# วิธีใช้:
#   sudo bash touchpad-recover.sh --list            ดูอุปกรณ์ที่จะจับคู่ได้ (พร้อม VID:PID)
#   sudo bash touchpad-recover.sh                   กู้คืนแบบ auto
#   sudo bash touchpad-recover.sh 1234:5678         กู้คืนเฉพาะอุปกรณ์ที่ระบุ VID:PID
#
# เคล็ดลับ: ผูกเป็นปุ่มลัดได้ เช่น ใน labwc/GNOME ให้คำสั่งนี้ทำงานเมื่อกด Super+T
# (เรียกผ่าน terminal แบบ pkexec หรือตั้ง sudo rule เฉพาะคำสั่งนี้แบบ NOPASSWD)

set -u

# ตำแหน่ง sysfs ของอุปกรณ์ USB (override ได้เพื่อการทดสอบ: DUET5I_USB_SYSFS=...)
USB_DEVICES="${DUET5I_USB_SYSFS:-/sys/bus/usb/devices}"

say() { printf '%s\n' "$*"; }

read_attr() { cat "$1" 2>/dev/null; }

# รวมข้อมูลอุปกรณ์ USB แต่ละตัว (เฉพาะที่มี idVendor = เป็นอุปกรณ์จริง ไม่ใช่ hub root)
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
        sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
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

selector="${1:-auto}"
targets=$(pick_targets "$selector")
if [ -z "$targets" ]; then
    say "!! ไม่พบอุปกรณ์ที่ตรงเงื่อนไข ($selector)" >&2
    say "   ลอง: sudo bash $0 --list เพื่อดูอุปกรณ์ทั้งหมด แล้วระบุ VID:PID ตรงๆ" >&2
    exit 1
fi

status=0
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
    if [ "$status" -ne 0 ] || [ ! -e /sys/bus/usb/drivers/usb ]; then
        if [ -w "/sys/bus/usb/devices/$addr/authorized" ]; then
            printf '0' > "/sys/bus/usb/devices/$addr/authorized" 2>/dev/null
            sleep 0.5
            printf '1' > "/sys/bus/usb/devices/$addr/authorized" 2>/dev/null \
                && say "   re-enumerate ผ่าน authorized สำเร็จ" || status=1
        fi
    fi
done

if [ "$status" -eq 0 ]; then
    say "เสร็จ — ทัชแพต/คีย์บอร์ดควรกลับมาทำงานทันที"
    say "ถ้ายังไม่กลับมา: ถอด folio แล้วประกบใหม่ หรือดู docs/03-troubleshooting.md"
else
    say "!! มีขั้นตอนบางส่วนไม่สำเร็จ ดูข้อความด้านบน" >&2
fi
exit "$status"
