#!/bin/sh
# ทดสอบ touchpad-recover.sh กับอุปกรณ์ USB จำลอง (ไม่แตะระบบจริง)
set -eu
root="/mnt/c/Users/ondev/Projects/development/lab/linux-driver-lenovo-ideapad-duet-5"
fake=$(mktemp -d /tmp/fake-usb-XXXXXX)
bus="$fake/devices"
mkdir -p "$bus/1-3" "$bus/1-3:1.0" "$bus/1-4" "$bus/1-4:1.0" "$bus/usb1"
# folio จำลอง: HID keyboard+touchpad ภายในเครื่อง
printf '17ef' > "$bus/1-3/idVendor"
printf '60ef' > "$bus/1-3/idProduct"
printf 'Lenovo Folio Keyboard' > "$bus/1-3/product"
printf 'unknown' > "$bus/1-3/removable"
printf '3' > "$bus/1-3:1.0/bInterfaceClass"
# เมาส์ USB ภายนอก (removable=fixed → ต้องไม่ถูกเลือกแบบ auto)
printf '046d' > "$bus/1-4/idVendor"
printf 'c52b' > "$bus/1-4/idProduct"
printf 'Logitech Receiver' > "$bus/1-4/product"
printf 'fixed' > "$bus/1-4/removable"
printf '3' > "$bus/1-4:1.0/bInterfaceClass"

echo "== --list ควรเห็นทั้งสองตัว พร้อม hid/removable =="
DUET5I_USB_SYSFS="$bus" bash "$root/scripts/touchpad-recover.sh" --list
echo
echo "== ทดสอบสัญญาณการเลือกเป้าหมาย (ตามเงื่อนไข pick_targets: removable=unknown + hid=1) =="
list=$(DUET5I_USB_SYSFS="$bus" bash "$root/scripts/touchpad-recover.sh" --list)
if echo "$list" | grep -q '1-3.*17ef:60ef.*removable=unknown.*hid=1'; then
    echo "PASS: folio จำลอง (1-3) มีสัญญาณครบตามเงื่อนไข auto"
else
    echo "FAIL: folio จำลองขาดสัญญาณ"; exit 1
fi
folio_line=$(echo "$list" | grep '1-4' )
if echo "$folio_line" | grep -q 'removable=fixed'; then
    echo "PASS: เมาส์ภายนอก (1-4) เป็น removable=fixed → จะไม่ถูกเลือกแบบ auto"
else
    echo "FAIL: เมาส์ภายนอกถูกระบุสถานะผิด"; exit 1
fi
rm -rf "$fake"
echo "TEST-DONE"
