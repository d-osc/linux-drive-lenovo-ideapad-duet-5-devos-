#!/bin/sh
# ทดสอบ touchpad-recover.sh + folio-watchdog.sh กับอุปกรณ์ USB จำลอง (ไม่แตะระบบจริง)
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

pass=0; fail=0
report() { if [ "$1" = "PASS" ]; then echo "$1: $2"; pass=$((pass+1)); else echo "$1: $2"; fail=$((fail+1)); fi; }

echo "== --list =="
DUET5I_USB_SYSFS="$bus" bash "$root/scripts/touchpad-recover.sh" --list
list=$(DUET5I_USB_SYSFS="$bus" bash "$root/scripts/touchpad-recover.sh" --list)
echo "$list" | grep -q '1-3.*17ef:60ef.*removable=unknown.*hid=1' \
    && report PASS "folio จำลอง (1-3) มีสัญญาณครบตามเงื่อนไข auto" \
    || report FAIL "folio จำลองขาดสัญญาณ"
echo "$list" | grep '1-4' | grep -q 'removable=fixed' \
    && report PASS "เมาส์ภายนอก (1-4) removable=fixed → ไม่ถูกเลือกแบบ auto" \
    || report FAIL "เมาส์ภายนอกถูกระบุสถานะผิด"

echo
echo "== --present (ใช้โดย watchdog) =="
# กรณีไม่มี folio: มีแต่เมาส์ภายนอก
only_external=$(mktemp -d /tmp/fake-usb-ext-XXXXXX)
mkdir -p "$only_external/devices"
cp -r "$bus/1-4" "$bus/1-4:1.0" "$only_external/devices/"

DUET5I_USB_SYSFS="$bus" bash "$root/scripts/touchpad-recover.sh" --present >/dev/null 2>&1 \
    && report PASS "present: auto เจอ folio" || report FAIL "present: auto ต้องเจอ folio"
DUET5I_USB_SYSFS="$bus" bash "$root/scripts/touchpad-recover.sh" --present 17ef:60ef >/dev/null 2>&1 \
    && report PASS "present: VID:PID ตรงเจอ" || report FAIL "present: VID:PID ตรงต้องเจอ"
if DUET5I_USB_SYSFS="$only_external/devices" bash "$root/scripts/touchpad-recover.sh" --present >/dev/null 2>&1; then
    report FAIL "present ต้องไม่เจอเมื่อมีแต่อุปกรณ์ภายนอก"
else
    report PASS "present ไม่เจอเมื่อมีแต่อุปกรณ์ภายนอก"
fi

echo
echo "== watchdog --once =="
out=$(DUET5I_USB_SYSFS="$bus" bash "$root/scripts/folio-watchdog.sh" --once); echo "$out"
case "$out" in *"folio ปกติ"*) report PASS "watchdog เห็น folio ปกติ";; *) report FAIL "watchdog ต้องรายงาน folio ปกติ";; esac
out=$(DUET5I_USB_SYSFS="$only_external/devices" bash "$root/scripts/folio-watchdog.sh" --once); echo "$out"
case "$out" in *"กู้คืนอัตโนมัติ"*) report PASS "watchdog สั่งกู้คืนเมื่อ folio หาย";; *) report FAIL "watchdog ต้องสั่งกู้คืนเมื่อ folio หาย";; esac

rm -rf "$fake" "$only_external"
echo
echo "ผลรวม: ผ่าน $pass / ไม่ผ่าน $fail"
[ "$fail" -eq 0 ]
