# Duet 5i Driver Toolkit v0.1.0

ชุดเครื่องมือทำให้ **Lenovo IdeaPad Duet 5i** (Intel Alder Lake, i5-1235U,
คีย์บอร์ด folio แบบถอดได้, เดิมทีรัน Windows 11) ใช้งาน Linux ได้ครบทุกส่วน

## อะไรอยู่ในนี้

| ส่วน | หน้าที่ |
|---|---|
| `docs/01-install.md` | เตรียมเครื่องบน Windows (BIOS, BitLocker) + ติดตั้ง Fedora ทีละขั้น |
| `docs/02-hardware.md` | รายละเอียดฮาร์ดแวร์ทุกชิ้น + driver/บริการที่เกี่ยวข้อง |
| `docs/03-troubleshooting.md` | แก้ตามอาการ: ทัชแพต folio หลุด, ไม่มีเสียง, กล้อง IPU6, จอไม่หมุน |
| `scripts/post-install.sh` | ลง SOF/libcamera/iio-sensor-proxy + udev rule หลังติดตั้ง (Fedora/Ubuntu) |
| `scripts/probe-hardware.sh` | เก็บข้อมูลฮาร์ดแวร์ทั้งเครื่องเป็น tarball เพื่อวินิจฉัย/แจ้ง bug |
| `udev/99-duet5i-folio.rules` | แก้ทัชแพต folio หลุดเป็นพักๆ (ปิด USB autosuspend) |
| `driver-template/` | แม่แบบโมดูลเคอร์เนล DKMS-ready สำหรับอุปกรณ์ที่เคอร์เนลยังไม่รองรับ |

## ใช้ยังไง (สรุปย่อ)

```bash
# หลังติดตั้ง Fedora ตาม docs/01-install.md
sudo bash scripts/post-install.sh
sudo bash scripts/probe-hardware.sh   # เก็บข้อมูลจริงของเครื่องเพื่อยืนยัน/แจ้งปัญหา
```

## สถานะการรองรับที่คาดหมาย (Fedora ล่าสุด)

- ✅ CPU/กราฟิก/จอ/จอสัมผัส/Wi-Fi/BT/NVMe/คีย์บอร์ด folio — ใช้ได้ทันที
- ⚠️ เสียง (ต้องมี sof-firmware), เซ็นเซอร์หมุนจอ (iio-sensor-proxy), กล้อง Intel IPU6 — ต้องมีส่วนเสริมตามคู่มือ
- ทัชแพตหลุดเป็นพักๆ แก้ด้วย udev rule ในชุดนี้

## แพ็กเกจ

| ไฟล์ | SHA-256 |
|---|---|
| `duet5i-driver-toolkit-0.1.0.tar.gz` | `0ed2abc489a5b8d08d117d927b63569d19eef0aa4887781b08023967848edd3d` |

## แผนต่อไป

ผลจาก `probe-hardware.sh` บนเครื่องจริงจะใช้ปรับ quirk เฉพาะรุ่น (UCM เสียง, เซ็นเซอร์ IIO)
และเป็นข้อมูลสำหรับเขียนโมดูลเคอร์เนลจริงจาก `driver-template/` หากพบอุปกรณ์ที่ยังไม่รองรับ
