#!/bin/sh
# ทดสอบ auto-tune.sh กับอุปกรณ์ USB จำลอง (ไม่แตะระบบจริง)
set -eu
root="/mnt/c/Users/ondev/Projects/development/lab/linux-driver-lenovo-ideapad-duet-5"
fake=$(mktemp -d /tmp/fake-tune-XXXXXX)
bus="$fake/devices"
mkdir -p "$bus/1-3" "$bus/1-3:1.0" "$bus/usb1"
printf '17ef' > "$bus/1-3/idVendor"
printf '60ef' > "$bus/1-3/idProduct"
printf 'Lenovo Folio Keyboard' > "$bus/1-3/product"
printf 'unknown' > "$bus/1-3/removable"
printf '3' > "$bus/1-3:1.0/bInterfaceClass"

out=$(DUET5I_USB_SYSFS="$bus" bash "$root/scripts/auto-tune.sh" --check-only 2>&1)
echo "$out" | head -6
case "$out" in
    *"พบ folio: VID:PID = 17ef:60ef"*) echo "PASS: ตรวจจับ folio ได้ถูกตัว (17ef:60ef)";;
    *) echo "FAIL: ตรวจจับ folio ผิด"; echo "$out" | grep 'พบ folio'; exit 1;;
esac
if echo "$out" | grep -q 'VID:PID = ค่า'; then
    echo "FAIL: ยัง match บรรทัดเคล็ดลับเป็น VID:PID"; exit 1
else
    echo "PASS: ไม่ match บรรทัดเคล็ดลับเป็น VID:PID อีก"
fi

# กรณีไม่มี folio เลย ต้องแจ้งไม่พบอย่างสุภาพ
empty=$(mktemp -d /tmp/fake-tune-empty-XXXXXX)
mkdir -p "$empty/devices"
out2=$(DUET5I_USB_SYSFS="$empty/devices" bash "$root/scripts/auto-tune.sh" --check-only 2>&1)
case "$out2" in
    *"ยังไม่พบ folio"*) echo "PASS: รายงาน 'ยังไม่พบ folio' เมื่อไม่มีอุปกรณ์";;
    *) echo "FAIL: ต้องรายงานไม่พบ"; exit 1;;
esac
rm -rf "$fake" "$empty"
echo "TEST-DONE"
