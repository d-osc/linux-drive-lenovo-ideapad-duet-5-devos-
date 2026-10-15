# 03 — แก้ปัญหาตามอาการ (IdeaPad Duet 5i บน Linux)

จัดเรียงจาก "เจอบ่อยสุด" และจากข้อมูลของเจ้าของเครื่องรุ่นเดียวกันในชุมชน
ก่อนแก้อะไร รัน `sudo bash scripts/probe-hardware.sh` เก็บข้อมูลไว้ก่อนเสมอ

---

## ทัชแพต/คีย์บอร์ด folio หลุดเป็นพักๆ

**อาการ:** ใช้ได้ปกติ แล้วทัชแพตเงียบไปเฉยๆ (บางรายต้องรีบูตถึงกลับมา)
เจ้าของ Duet 5i รายอื่น[รายงานอาการเดียวกัน](https://discussion.fedoraproject.org/t/bluetooth-keyboard-with-touchpad-connected-but-not-working-lenovo-ideapad-duet-5i/78551)

**สาเหตุที่พบบ่อย:** USB autosuspend พักอุปกรณ์ แล้วตื่นไม่สำเร็จ

**แก้:** สคริปต์ `post-install.sh` ติดตั้ง udev rule ไปแล้ว ถ้ายังหลุดอยู่:

1. ดูค่า VID:PID: `lsusb` (ตอนต่อ folio)
2. กรอกค่าจริงแทน `XXXX:XXXX` ใน `/etc/udev/rules.d/99-duet5i-folio.rules`
   (แล้วเปิดบรรทัดเจาะจง ปิดบรรทัด generic ถ้าต้องการ)
3. `sudo udevadm control --reload && sudo udevadm trigger`

**ทางแก้ฉุกเฉิน (ไม่ต้องรีบูต):** ถอด folio แล้วประกบใหม่ มักกลับมาทันที
หรือ `sudo sh -c 'echo on > /sys/bus/usb/devices/X-Y/power/control'` (แทน X-Y ด้วยพอร์ตจริงจาก `lsusb -t`)

**ถ้ายังไม่หาย:** บันทึก log ระหว่างอาการเกิด:
`sudo dmesg -wH` ทิ้งไว้ แล้วส่งบรรทัดที่โผล่ตอนทัชแพตดับให้ชุมชนดู

---

## ไม่มีเสียงจากลำโพง

1. ตรวจว่าเฟิร์มแวร์ SOF โหลด:
   ```bash
   dmesg | grep -i 'sof.*firmware'
   sudo dnf install sof-firmware   # ถ้ายังไม่มี (Ubuntu: sudo apt install sof-firmware)
   ```
2. เลือกเอาต์พุตที่ถูก: Settings → Sound → Output → เลือก "Speaker"
   (มักมีทั้ง HDMI กับ Speaker — เลือกผิดจะเงียบ)
3. ทดสอบระดับ ALSA ตรงๆ:
   ```bash
   aplay -l                 # ต้องเห็นการ์ด
   speaker-test -c 2 -t wav # ควรได้ยินเสียง
   ```

## ลำโพงออกเสียงไม่ครบทุกตัว (เช่น มี 4 ตัว ดัง 2)

เกิดจากการตั้งค่าเส้นทางสัญญาณ (UCM) ไม่ตรงกับตัวเครื่อง:

1. ดูชื่อการ์ด/codec: `cat /proc/asound/cards`
2. หาไฟล์ UCM ที่เกี่ยวข้อง: `ls /usr/share/alsa/ucm2/conf.d/`
3. ถ้าไม่มีของรุ่นเครื่อง — ยังไม่ต้องแก้เอง: เก็บผลจาก probe-hardware.sh
   (มีรายการ UCM + hw_params ครบ) แล้วแจ้งเป็น bug ที่
   [alsa-project/alsa-ucm-conf](https://github.com/alsa-project/alsa-ucm-conf/issues)
   พร้อมรุ่นเครื่อง — เป็นวิธีที่ทำให้รุ่นเครื่องคุณได้รับการแก้ถาวรในทุก distro

---

## กล้องใช้ไม่ได้ / ไม่มี /dev/video*

**ข้อเท็จจริง:** กล้องเครื่องนี้ต่อแบบ MIPI (ไม่ใช่ USB webcam ธรรมดา) ผ่านชิปประมวลผล
Intel IPU6 — เป็นส่วนที่ Linux รองรับช้าที่สุดและต้องพึ่งเคอร์เนลใหม่ + libcamera

**บน Fedora (แนะนำ):** ต้องการเคอร์เนล ≥ 6.12 ซึ่งมีไดรเวอร์ [ตั้งแต่ Fedora 41](https://www.phoronix.com/news/Fedora-41-Intel-IPU6-Webcam)

1. ตรวจว่าโมดูลขึ้น:
   ```bash
   lsmod | grep -E 'ipu6|ivsc'
   media-ctl -p            # ดู pipeline ของกล้อง
   ```
2. ทดสอบด้วยแอปที่รองรับ libcamera:
   ```bash
   sudo dnf install libcamera-tools
   qcam
   ```
3. กล้อง MIPI บางเครื่อง **ยังไม่ขึ้นตอนบูตเย็น (cold boot)** แต่ขึ้นหลังรีบูตหนึ่งครั้ง —
   อาการนี้เป็น [bug ที่รู้จักทั่วไป](https://bugs.launchpad.net/bugs/1921345) ของบางเซ็นเซอร์
4. Firefox/GNOME ต้องเข้าถึงกล้องผ่าน **portal** (xdg-desktop-portal) — ตรวจว่าติดตั้งแล้ว:
   `sudo dnf install xdg-desktop-portal-gnome`

**บน Ubuntu:** ต้องลงชุด intel-ipu6 เพิ่มตาม[คู่มือทางการของ Ubuntu](https://discourse.ubuntu.com/t/intel-mipi-laptop-camera-not-working-24-04/63403)
(สคริปต์ post-install.sh พยายามลงให้อัตโนมัติ) และระวัง DKMS พังตามเคอร์เนลใหม่ —
[ตัวอย่างปัญหาบนเคอร์เนล 6.14](https://github.com/intel/ipu6-drivers/issues/369)

---

## จอไม่หมุนอัตโนมัติตามการถือเครื่อง

1. ตรวจบริการ:
   ```bash
   systemctl status iio-sensor-proxy
   monitor-sensor   # รอไว้ แล้วหมุนเครื่อง — ต้องมีบรรทัด "Accelerometer" เปลี่ยนค่า
   ```
2. ถ้าไม่มีเซ็นเซอร์โผล่เลย → ไดรเวอร์ IIO ของ accelerometer ยังไม่จับ:
   ```bash
   cat /sys/bus/iio/devices/iio:device*/name
   ```
   ถ้าว่างเปล่า ให้ส่งผล `probe-hardware.sh` (ส่วน i2c + acpi) ให้ประเมิน —
   อาจต้องเพิ่มรายชื่อเครื่องในไดรเวอร์ (quirk เล็กๆ ในเคอร์เนล ไม่ใช่ไดรเวอร์ใหม่)

---

## ปุ่มปรับความสว่าง/วอลลุ่ม หรือปุ่มพิเศษไม่ทำงาน

```bash
dmesg | grep -iE 'ideapad|vbtn'
lsmod | grep -E 'ideapad_laptop|intel_vbtn'
```
ถ้าโมดูลขึ้นแต่ปุ่มเฉพาะไม่มา: เก็บ `sudo libinput debug-events` กดปุ่มดู —
ถ้าไม่มี event โผล่เลย แปลว่า ACPI ของรุ่นนี้มีรหัสที่เคอร์เนลยังไม่รู้จัก (แจ้งเป็น
kernel bug ได้ พร้อมผล probe)

---

## แบตเตอรี่หมดเร็วผิดปกติ

```bash
sudo dnf install powertop
sudo powertop          # ดูตัวการกินไฟอันดับหน้า
```
- ฝั่ง Intel ปรับสมดุลเองได้ดีบนเคอร์เนลใหม่ — ถ้าเห็น "PCI Device: ..." กินไฟเยอะ
  ให้เปิด ASPM: `sudo powertop --auto-tune` (ทดสอบก่อนใช้ถาวร เพราะกระทบ folio autosuspend ที่เราเพิ่งปิด)

---

## ถอดคีย์บอร์ดแล้วคีย์บอร์ดจอ (on-screen) ไม่โผล่

GNOME อาศัยสัญญาณ "tablet mode" จาก `intel-vbtn`:
```bash
sudo dmesg | grep -i tablet
```
ทางแลี่ยง: เปิดเองได้ที่ Settings → Accessibility → Screen Keyboard
หรือติดตั้งส่วนขยาย GNOME อย่าง "OSK Toggle"

---

## ยังไม่หาย — แจ้งปัญหาให้ฝั่งที่ดูแลไดรเวอร์จริง

| ปัญหาเกี่ยวกับ | ที่แจ้ง |
|---|---|
| เสียง/UCM | [alsa-project/alsa-ucm-conf](https://github.com/alsa-project/alsa-ucm-conf/issues) |
| กล้อง IPU6 | [intel/ipu6-drivers](https://github.com/intel/ipu6-drivers/issues) |
| เคอร์เนลทั่วไป (input/sensor/ACPI) | [bugzilla.kernel.org](https://bugzilla.kernel.org/) |
| ของ Fedora โดยเฉพาะ | [Fedora Bugzilla](https://bugzilla.redhat.com/) |

แนบไฟล์จาก `probe-hardware.sh` ไปกับทุกฉบับ — ข้อมูลครบ โอกาสถูกแก้เร็วขึ้นมาก
