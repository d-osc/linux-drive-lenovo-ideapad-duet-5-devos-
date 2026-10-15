# Linux บน Lenovo IdeaPad Duet 5i (Intel i5-1235U)

ชุดเครื่องมือทำให้ฮาร์ดแวร์ทุกชิ้นของ **IdeaPad Duet 5i (Alder Lake, i5-1235U, เดิมทีรัน Windows 11)**
ทำงานบน Linux ได้ครบ — ทั้งคีย์บอร์ด folio แบบถอดได้, เสียง, กล้อง, จอสัมผัส และเซ็นเซอร์หมุนจอ

> ชื่อรุ่นในเอกสารนี้ใช้ตามที่ Lenovo เรียกในเฟิร์มแวร์ เช่น `IdeaPad Duet 5 12IAU7`
> (ตรวจสอบรุ่นจริงได้จากสติกเกอร์ล่างเครื่อง หรือคำสั่ง `sudo dmidecode -s system-product-name`)

## สรุปสถานะฮาร์ดแวร์ (ตามข้อมูลชุมชน + สถานะเคอร์เนลปัจจุบัน)

| อุปกรณ์ | สถานะบน Linux | สิ่งที่ต้องทำ |
|---|---|---|
| CPU / กราฟิก Iris Xe | ✅ ทำงานทันที | เคอร์เนล ≥ 6.1 (แนะนำ ≥ 6.12) |
| จอ 2.5K + ความสว่าง | ✅ ทำงานทันที | ไม่ต้องทำอะไร (ไดรเวอร์ `i915`) |
| จอสัมผัส | ✅ ทำงานทันที (โดยทั่วไป) | `hid-multitouch` มีในเคอร์เนลอยู่แล้ว — ยืนยันด้วย probe |
| คีย์บอร์ด folio (ผ่านขั้ว pogo) | ✅ ทำงานทันที | ปรากฏเป็น USB HID — ใช้งานได้เลย |
| ทัชแพตบน folio | ⚠️ ใช้ได้ แต่หลุดเป็นพักๆ | บันได 5 ขั้น: udev 3 ชั้น + `--stable-input` + กู้คืนด่วน + **watchdog กู้คืนอัตโนมัติ** (`--watchdog`) หายเองในไม่กี่วินาที ไม่ต้องรีบูต |
| Wi-Fi / Bluetooth (Intel AX201/AX211) | ✅ ทำงานทันที | เฟิร์มแวร์อยู่ในแพ็กเกจ `linux-firmware` |
| เสียง (SOF Alder Lake) | ⚠️ ต้องมีเฟิร์มแวร์ SOF | มีใน Fedora โดยดีฟอลต์ / Ubuntu ต้องลง `sof-firmware` |
| ลำโพงทุกตัว | ❓ ต้องยืนยัน | ถ้าเสียงออกไม่ครบทุกลำโพง อาจต้องแก้ UCM — ดู docs/03 |
| กล้องหน้า/หลัง (Intel IPU6 + MIPI) | ⚠️ ยากที่สุด | ต้องการ libcamera + PipeWire stack — **Fedora รองรับดีที่สุด** |
| เซ็นเซอร์หมุนจอ (accelerometer) | ⚠️ ต้องมี userspace | ลง `iio-sensor-proxy` → GNOME หมุนจออัตโนมัติ |
| โหมดแท็บเล็ต (ถอดคีย์บอร์ด) | ✅ มักทำงาน | `intel-vbtn` ส่ง event ให้ GNOME เปิดคีย์บอร์ดจอ |

> สถานะที่เป็น ⚠️/❓ คือสิ่งที่ชุดนี้จะช่วยทำให้ครบ — รัน `scripts/probe-hardware.sh`
> บนเครื่องจริงเพื่อยืนยัน แล้วส่งผลกลับมาให้ปรับแก้ได้ตรงจุด

## เริ่มต้นใน 4 ขั้น

1. **เตรียมเครื่องบน Windows** — อัปเดต BIOS, สำรองข้อมูล, เตรียมพื้นที่ดิสก์
   → อ่าน [docs/01-install.md](docs/01-install.md)
2. **ติดตั้ง Fedora Workstation รุ่นล่าสุด** (แนะนำ เพราะชุดกล้อง IPU6 + SOF ครบที่สุด)
   → อ่าน [docs/01-install.md](docs/01-install.md)
3. **รันสคริปต์จัดการหลังติดตั้ง** บนเครื่องใหม่:
   ```bash
   sudo bash scripts/post-install.sh
   ```
4. **เก็บข้อมูลฮาร์ดแวร์จริง** เพื่อยืนยันว่าครบทุกชิ้น (และแนบผลให้ AI/ชุมชนช่วยดูต่อได้):
   ```bash
   sudo bash scripts/probe-hardware.sh
   # ได้ไฟล์ duet5i-probe-<วันที่>.tar.gz ไว้ส่งต่อ
   ```

## โครงสร้างโปรเจกต์

```
├── README.md                  ← ไฟล์นี้
├── docs/
│   ├── 01-install.md          ← เตรียมเครื่อง + ติดตั้ง Fedora ทีละขั้น (ไทย)
│   ├── 02-hardware.md         ← รายละเอียดฮาร์ดแวร์แต่ละชิ้น + driver ที่เกี่ยวข้อง
│   └── 03-troubleshooting.md  ← อาการที่พบบ่อย + วิธีแก้ทีละอาการ
├── scripts/
│   ├── probe-hardware.sh      ← เก็บข้อมูลฮาร์ดแวร์ทั้งเครื่องเป็น tarball
│   ├── post-install.sh        ← ลงแพ็กเกจ + เปิดบริการ + ใส่ udev rule (--stable-input / --watchdog)
│   ├── touchpad-recover.sh    ← กู้คืนทัชแพต/คีย์บอร์ด folio ที่หลุด โดยไม่ต้องรีบูต (มี --hard รีเซ็ต xHCI)
│   └── folio-watchdog.sh      ← เฝ้า folio ตลอดเวลา หายจากบัสก็กู้คืนให้เองอัตโนมัติ
├── systemd/
│   └── duet5i-folio-watchdog.service ← service unit ของ watchdog (ติดตั้งผ่าน --watchdog)
├── tests/
│   └── test-recover.sh        ← ทดสอบ logic กู้คืน/watchdog ด้วยอุปกรณ์ USB จำลอง
├── udev/
│   └── 99-duet5i-folio.rules  ← แก้ทัชแพต folio หลุดเป็นพักๆ (ปิด autosuspend)
├── driver-template/           ← แม่แบบโมดูลเคอร์เนล (DKMS) สำหรับกรณีมีอุปกรณ์ที่ยังไม่รองรับ
├── DevOs/                     ← desktop environment (labwc+React/GJS) พร้อม extension ฮาร์ดแวร์ Duet 5i ที่เราเขียนเพิ่ม
└── docs/04-devos-desktop.md   ← คู่มือติดตั้ง DevOs + ส่วนเสริมแสงจอ/หมุนจอ/OSK/ปุ่มฟังก์ชัน
```

## ทำไมต้องเขียน driver เอง — และเมื่อไหร่?

อุปกรณ์ส่วนใหญ่บนเครื่องนี้ใช้ไดรเวอร์มาตรฐานในเคอร์เนลอยู่แล้ว งานจริงคือ:
**เลือก distro/แพ็กเกจให้ถูก + เฟิร์มแวร์ + กฎ udev** ดังนั้นชุดนี้ออกแบบให้ "แก้ที่ต้นทาง" ก่อน

จะต้องเขียนโมดูลเคอร์เนลเองจริงๆ เฉพาะกรณีที่ผล probe พบอุปกรณ์ที่เคอร์เนลไม่มีไดรเวอร์ให้เลย
(เช่น เซ็นเซอร์ตัวใดตัวหนึ่งไม่มีใน `iio`, หรือ touchscreen แปลกปลอม) — กรณีนั้นให้เริ่มจาก
`driver-template/` ซึ่งเตรียม Makefile + dkms.conf + โครงโค้ดไว้ให้แล้ว

## อยากใช้ desktop สำหรับแท็บเล็ตโดยเฉพาะ?

เราทำส่วนเสริมฮาร์ดแวร์ให้ [DevOs](https://github.com/d-osc/DevOs) (desktop environment
บน labwc) แล้ว — แสงจอ, หมุนจออัตโนมัติ, คีย์บอร์ดจอเมื่อถอด folio, ปุ่มฟังก์ชันทำงานครบ
ดูรายละเอียดที่ [docs/04-devos-desktop.md](docs/04-devos-desktop.md)

## แหล่งข้อมูลอ้างอิง

- [Fedora Forum — Duet 5i folio keyboard/touchpad ใช้งานผ่าน pogo ได้](https://discussion.fedoraproject.org/t/bluetooth-keyboard-with-touchpad-connected-but-not-working-lenovo-ideapad-duet-5i/78551)
- [Phoronix — Fedora 41 เปิดใช้งานกล้อง Intel IPU6](https://www.phoronix.com/news/Fedora-41-Intel-IPU6-Webcam)
- [libcamera FAQ — สถานะการรองรับ IPU6](https://libcamera.org/faq.html)
- [intel/ipu6-drivers — ไดรเวอร์กล้อง IPU6 แบบ out-of-tree](https://github.com/intel/ipu6-drivers)
- [Arch BBS — ประสบการณ์ใช้กล้อง IPU6 บนเคอร์เนล 6.10+](https://bbs.archlinux.org/viewtopic.php?id=297262)
- [Ubuntu Discourse — คู่มือแก้กล้อง MIPI บน 24.04](https://discourse.ubuntu.com/t/intel-mipi-laptop-camera-not-working-24-04/63403)
