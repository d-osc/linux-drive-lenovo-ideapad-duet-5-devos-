# 02 — ฮาร์ดแวร์ของ Duet 5i กับ driver ที่เกี่ยวข้อง

เอกสารนี้อธิบาย "ใต้ประทุน" ของแต่ละชิ้น เพื่อให้รู้ว่าเวลามีปัญหาต้องไปดูตรงไหน
(ชื่อ driver อ้างตามที่ปรากฏใน `lsmod` / `dmesg`)

## สายพันธุ์ฮาร์ดแวร์โดยรวม

| ชิ้นส่วน | ฮาร์ดแวร์จริง (ตระกูล) | บัส/เส้นทาง | driver/ส่วนประกอบที่เกี่ยวข้อง |
|---|---|---|---|
| CPU + กราฟิก | Intel Alder Lake-U (i5-1235U) + Iris Xe | PCIe/สอดแทรกใน SoC | `i915` |
| NVMe SSD | (แตกต่างตามรุ่นย่อย) | NVMe | `nvme` |
| Wi-Fi/BT | Intel AX201/AX211 | CNVio/PCIe + USB | `iwlwifi`, `btusb` |
| จอสัมผัส | Elan หรือ Goodix (ตามล็อตการผลิต) | I2C-HID (ACPI) | `i2c-designware`, `i2c-hid-acpi`, `hid-multitouch` |
| คีย์บอร์ด folio | USB HID (ผ่านขั้ว pogo 5 ขา → hub ภายใน) | USB | `usbhid` (ไม่ต้องมีไดรเวอร์พิเศษ) |
| เสียง | Alder Lake-P PCH + codec Realtek/SOF | HDA/SOF | `snd_hda_intel`, `snd_sof_pci_intel_tgl`, `snd_soc_*` + ไฟล์เฟิร์มแวร์ SOF |
| กล้องหน้า/หลัง | เซ็นเซอร์ MIPI ผ่าน Intel IPU6 | MIPI CSI-2 + `ivsc` | `intel-ipu6`, `ivsc_*`, เซ็นเซอร์รายตัว (เช่น `ov01a1s`) + libcamera/PipeWire ฝั่ง userspace |
| เซ็นเซอร์หมุนจอ | accelerometer ตระกูล Kionix/Bosch | I2C + ACPI | `iio` ไดรเวอร์รายตัว + `iio-sensor-proxy` (userspace) |
| โหมดแท็บเล็ต/ปุ่มพิเศษ | ACPI events | ACPI | `intel-vbtn`, `ideapad_laptop` |
| แบตเตอรี่/พลังงาน | — | ACPI | `battery`, `intel_uncore_frequency`, `intel_rapl` |

## หัวใจของงาน "driver" บนเครื่องนี้

ต่างจากอดีตที่ต้อง compile เองทั้งหมด — ปัจจุบันเคอร์เนลหลักมีไดรเวอร์ครบเกือบทุกชิ้น
สิ่งที่เหลือจริงๆ มี 3 กลุ่ม:

### 1) เฟิร์มแวร์ (firmware)
ของแท้ที่ทำให้ "ไดรเวอร์มีอยู่แต่ใช้ไม่ได้" — ต้องติดตั้งแพ็กเกจ `sof-firmware` + `linux-firmware`
(ทั้งคู่อยู่ใน Fedora โดยดีฟอลต์) ตรวจสอบว่าโหลดสำเร็จ:

```bash
dmesg | grep -iE 'sof.*firmware|fw_load'
# บรรทัดที่ต้องเห็นคำว่า "firmware loaded successfully" หรือคล้ายกัน
```

### 2) ส่วนประกอบฝั่ง userspace
- **กล้อง IPU6**: เคอร์เนลเปิดประตูให้แล้ว แต่การประมวลผลภาพอยู่ที่ **libcamera + PipeWire**
  ดังนั้นแอปต้องเป็นแอปยุคใหม่ (GNOME Cheese ล่าสุด, Firefox ผ่าน portal, `qcam`) —
  ไม่ใช่ `cheese` เก่าหรือ Zoom ที่ยังเรียก V4L2 ตรงๆ
- **หมุนจออัตโนมัติ**: เคอร์เนลอ่านค่า accelerometer ผ่าน IIO แต่ผู้แปลงเป็นการหมุนจอคือ
  `iio-sensor-proxy` + GNOME

### 3) การปรับแต่งเล็กน้อย (quirks)
- ทัชแพต folio หลุด → udev rule ปิด autosuspend (ทำแล้วใน repo นี้)
- เสียงลำโพงไม่ครบ → ปรับ UCM (ดู 03-troubleshooting)
- ถ้าพบอุปกรณ์แปลกที่ไม่มีไดรเวอร์เลย → เริ่มจาก `driver-template/`

## วิธีอ่านชื่ออุปกรณ์จริงจากเครื่อง

```bash
# USB — หา VID:PID ของคีย์บอร์ด folio
lsusb

# ACPI — ดูรหัส _HID ของอุปกรณ์ทั้งหมด (ใช้เขียนไดรเวอร์ platform)
grep -H . /sys/bus/acpi/devices/*/hid 2>/dev/null

# IIO — เซ็นเซอร์ที่เคอร์เนลจับได้
cat /sys/bus/iio/devices/iio:device*/name

# อุปกรณ์ HID ทั้งหมด + ไดรเวอร์ที่จับอยู่
grep -A2 Name /proc/bus/input/devices
```

## อ้างอิงสถานะอุปกรณ์กล้อง (สิ่งที่ยักษ์ที่สุดของเครื่องนี้)

- เคอร์เนล ≥ 6.12 มีไดรเวอร์ IPU6 (ฝั่งรับภาพ ISYS) ในต้นไม้หลักแล้ว
- การประมวลผลขั้นสูง (PSYS) ยังต้องพึ่ง libcamera — สถานะล่าสุดอ่านจาก
  [libcamera FAQ](https://libcamera.org/faq.html)
- ชุด out-of-tree ของ Intel (สำหรับ distro เก่า): [intel/ipu6-drivers](https://github.com/intel/ipu6-drivers)
- ประสบการณ์จริงหลายเครื่อง: [กระทู้ Arch](https://bbs.archlinux.org/viewtopic.php?id=297262)
  และ[คู่มือของ Ubuntu](https://discourse.ubuntu.com/t/intel-mipi-laptop-camera-not-working-24-04/63403)
