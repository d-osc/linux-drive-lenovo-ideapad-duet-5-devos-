# 03 — แก้ปัญหาตามอาการ (IdeaPad Duet 5i บน Linux)

จัดเรียงจาก "เจอบ่อยสุด" และจากข้อมูลของเจ้าของเครื่องรุ่นเดียวกันในชุมชน
ก่อนแก้อะไร รัน `sudo bash scripts/probe-hardware.sh` เก็บข้อมูลไว้ก่อนเสมอ

---

## ทัชแพต/คีย์บอร์ด folio หลุดเป็นพักๆ — บันไดความเสถียร 5 ขั้น

**อาการ:** ใช้ได้ปกติ แล้วทัชแพตเงียบไปเฉยๆ (บางรายต้องรีบูตถึงกลับมา)
เจ้าของ Duet 5i รายอื่น[รายงานอาการเดียวกัน](https://discussion.fedoraproject.org/t/bluetooth-keyboard-with-touchpad-connected-but-not-working-lenovo-ideapad-duet-5i/78551)

**สาเหตุหลัก:** เคอร์เนลพักอุปกรณ์ USB (autosuspend) หลังไม่ได้ใช้ ~2 วินาที
แล้ว folio ตื่นจากโหมดพักไม่สำเร็จ แก้เป็นขั้นๆ ตามลำดับนี้ (ทำขั้นแรกก่อน แล้วค่อยขึ้น):

**ขั้น 1 — udev rule (ทำให้โดย post-install.sh แล้ว):** ปิด autosuspend กับอุปกรณ์ USB
ภายในทั้งหมด + interface ที่ usbhid ถือ ครอบคลุม folio ทันทีโดยไม่ต้องตั้งค่า

**ขั้น 2 — เจาะจง folio ด้วย VID:PID (แม่นกว่า):**
```bash
sudo bash scripts/touchpad-recover.sh --list   # ดู VID:PID ของ folio พร้อมผู้สมัครทั้งหมด
```
กรอกค่าจริงแทน `XXXX:XXXX` ใน `/etc/udev/rules.d/99-duet5i-folio.rules` (ชั้นที่ 1 ในไฟล์)
แล้ว `sudo udevadm control --reload && sudo udevadm trigger`

**ขั้น 3 — ปิด autosuspend ทั้งระบบ (มักจบที่นี่):**
```bash
sudo bash scripts/post-install.sh --stable-input
# แล้วรีบูตหนึ่งครั้ง (เพิ่ม usbcore.autosuspend=-1 ให้ และเตรียม
# /etc/modprobe.d/duet5i-folio.conf พร้อมตัวเลือก mousepoll ไว้ลองถ้าจำเป็น)
```

**ขั้น 4 — กู้คืนด่วนเมื่อเกิดขึ้นระหว่างใช้งาน (ไม่ต้องรีบูตอีกต่อไป):**
```bash
sudo bash scripts/touchpad-recover.sh            # auto: จับคู่ unbind/bind อุปกรณ์ HID ภายใน
sudo bash scripts/touchpad-recover.sh 1234:5678  # หรือระบุ VID:PID ตรงๆ
sudo bash scripts/touchpad-recover.sh --hard     # รุนแรงสุด: รีเซ็ตคอนโทรลเลอร์ xHCI
```
สคริปต์ทำ unbind → bind (เท่าถอด-ประกบ folio ใหม่แบบซอฟต์แวร์) มีวิธีสำรอง
ที่แรงกว่า (re-enumerate ผ่าน authorized) และระดับสุดท้าย `--hard` คือรีเซ็ต
คอนโทรลเลอร์ xHCI สำหรับกรณีอุปกรณ์หายจากบัสไปเลย — **ผูกกับปุ่มลัดไว้ได้**
เช่น Super+T (ดูคำแนะนำ sudo NOPASSWD ในหัวสคริปต์)

**ขั้น 5 — ให้มันหายเองโดยไม่ต้องทำอะไร (watchdog อัตโนมัติ):**
```bash
sudo bash scripts/post-install.sh --watchdog
```
ติดตั้ง+เปิด service `duet5i-folio-watchdog` ที่เฝ้า folio ทุก 5 วินาที:
ถ้าอุปกรณ์หายจากบัส มันจะเรียกขั้น 4 (ถึงระดับ `--hard`) ให้เองทันที
ผลคือแม้อาการจะเกิด มันก็หายเองในไม่กี่วินาทีโดยไม่ต้องรีบูตหรือกดอะไร
ปรับตั้งค่าได้ด้วย `systemctl edit duet5i-folio-watchdog`
(เช่น กรอก `DUET5I_FOLIO_ID=17ef:60ef` เมื่อรู้ VID:PID จริง)

**ถ้าทั้ง 5 ขั้นแล้วยังหลุด:** บันทึก log ระหว่างอาการเกิด:
`sudo dmesg -wH` ทิ้งไว้ แล้วส่งบรรทัดที่โผล่ตอนทัชแพตดับให้ชุมชนดู —
ถ้า dmesg แสดง error ของ USB controller ซ้ำๆ (เช่น `xhci ... reset`) แปลว่าเป็น
ที่ระดับคอนโทรลเลอร์ ค่อยพิจารณา quirk เฉพาะรุ่นต่อไป

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

### เครื่องมือของชุดนี้ (ใช้ก่อนอ่านอย่างอื่น)

```bash
# 1) ติดตั้งชุดส่วนประกอบให้ครบตาม distro (Fedora ลงจาก repo หลัก,
#    Ubuntu ลง DKMS+HAL แล้วเตือนเรื่อง Secure Boot/MOK ให้)
sudo bash scripts/camera-setup.sh

# 2) วินิจฉัยเชิงลึก 7 ชั้น: เคอร์เนล → โมดูล → media devices → เซ็นเซอร์
#    ใน topology → /dev/video* → libcamera → dmesg (พร้อมวิธีแก้ทุกข้อ ❌)
sudo bash scripts/camera-check.sh

# 3) ถ้าเช็คแล้วเจอปัญหา — กู้คืนด้วยการ rebind คอนโทรลเลอร์ IPU6/IVSC
#    (แก้อาการ "cold boot แล้วกล้องไม่ init" โดยไม่ต้องรีบูต)
sudo bash scripts/camera-check.sh --fix
```

### อาการที่พบบ่อยและทางออก

- **บูตเย็น (เปิดเครื่องจากดับสนิท) แล้วกล้องไม่ขึ้น แต่รีสตาร์ตแล้วขึ้น** —
  [bug ที่รู้จัก](https://bugs.launchpad.net/bugs/1921345)ของบางเซ็นเซอร์:
  รัน `camera-check.sh --fix` ก่อน ถ้าไม่หายค่อยรีสตาร์ต (warm) หนึ่งครั้ง
- **แอปไหนใช้ได้บ้าง?** ต้องเป็นแอปที่รองรับ libcamera: `qcam` (ทดสอบ),
  GNOME Snapshot, Firefox ผ่าน portal — แอป V4L2 เก่า (cheese รุ่นเก่า) ไม่เห็นกล้อง MIPI
- **Ubuntu: กล้องหายหลังอัปเดตเคอร์เนล** — DKMS พังตามเคอร์เนลใหม่
  ([ตัวอย่างบน 6.14](https://github.com/intel/ipu6-drivers/issues/369)):
  รัน `camera-setup.sh` ซ้ำเพื่อ build ใหม่ + ตรวจ `dkms status`
- **Ubuntu + Secure Boot:** โมดูล DKMS โหลดไม่ได้จนกว่าจะลงนาม MOK —
  `camera-setup.sh` ตรวจและพิมพ์คำสั่งลงนามให้ หรือปิด Secure Boot ใน BIOS
- **อ่านเพิ่ม:** [คู่มือทางการของ Ubuntu](https://discourse.ubuntu.com/t/intel-mipi-laptop-camera-not-working-24-04/63403),
  [สถานะ libcamera](https://libcamera.org/faq.html), [ipu6-drivers ของ Intel](https://github.com/intel/ipu6-drivers)

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
