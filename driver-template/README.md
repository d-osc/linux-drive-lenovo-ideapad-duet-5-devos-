# แม่แบบไดรเวอร์เคอร์เนลสำหรับ Duet 5i

ใช้เมื่อผลจาก `scripts/probe-hardware.sh` พบอุปกรณ์ที่เคอร์เนล Linux **ยังไม่มีไดรเวอร์ให้เลย**
(ปกติของเครื่องนี้แทบทุกชิ้นมีไดรเวอร์อยู่แล้ว — อย่าเขียนใหม่โดยไม่จำเป็น)

## เตรียมเครื่อง build

build บนเครื่อง Duet 5i เอง (ง่ายที่สุด) โดยติดตั้ง headers ก่อน:

```bash
# Fedora
sudo dnf install kernel-devel kernel-headers make gcc
# Ubuntu
sudo apt install linux-headers-$(uname -r) build-essential
```

## ทดสอบโมดูลตั้งต้น

```bash
cd driver-template
make load                 # build + insmod
cat /dev/duet5i0          # ควรพิมพ์: duet5i skeleton driver alive
dmesg | tail              # ดู log ของโมดูล
make unload
```

## ติดตั้งแบบ DKMS (rebuild อัตโนมัติเมื่อเคอร์เนลอัปเดต)

คำสั่งอยู่ใน comment ของ [dkms.conf](dkms.conf)

## ต่อยอดเป็นไดรเวอร์จริง

1. เปิด `duet5i_template.c` — เลือกประเภทไดรเวอร์ตามบัสที่อุปกรณ์ใช้ (มีตัวอย่าง
   platform/ACPI และ USB คอมเมนต์ไว้ในไฟล์แล้ว)
2. เปลี่ยนชื่อไฟล์/โมดูล `duet5i_template` เป็นชื่อจริง (อย่าลืมแก้ Makefile + dkms.conf ให้ตรง)
3. อ้างอิงรหัสอุปกรณ์จริงจากผล probe:
   - USB: `VID:PID` จาก `lsusb`
   - ACPI: `_HID` จาก `ls /sys/bus/acpi/devices/` (ดูไฟล์ `hid` ในแต่ละอุปกรณ์)
   - I2C: ที่อยู่ + compatible จาก `i2cdetect` และ `/sys/bus/i2c/devices/`
4. ศึกษาไดรเวอร์ที่ใกล้เคียงในซอร์สเคอร์เนลก่อนเสมอ:
   `drivers/hid/`, `drivers/input/touchscreen/`, `drivers/iio/accel/`

## Secure Boot

ถ้าเปิด Secure Boot ไว้ โมดูลที่เขียนเองจะโหลดไม่ได้จนกว่าจะลงนามเสียก่อน
(เหตุผลที่แนะนำให้เริ่มบน Fedora: แพ็กเกจของ distro ลงนามให้อยู่แล้ว)

```bash
# สร้างคีย์ + ลงทะเบียน MOK (ระบบจะถามรหัสผ่านตอนรีบูตครั้งถัดไป)
sudo kmodgenca -a
sudo mokutil --import /etc/pki/kernel/module-signing-ca.crt   # ใส่รหัสผ่านที่ตั้งไว้
# รีบูต → เลือก Enroll MOK → หลังจากนี้ dkms จะลงนามให้อัตโนมัติ
```

ทางเลือกง่ายกว่า: ปิด Secure Boot ใน BIOS ระหว่างพัฒนา แล้วค่อยเปิดคืนเมื่อเสร็จ
