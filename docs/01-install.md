# 01 — เตรียมเครื่องและติดตั้ง Linux (IdeaPad Duet 5i)

คู่มือนี้เขียนสำหรับเครื่อง **IdeaPad Duet 5i (Intel i5-1235U, Alder Lake)** ที่ยังรัน
Windows 11 อยู่ แนะนำ **Fedora Workstation รุ่นล่าสุด** เพราะ:

- เคอร์เนลใหม่ → รองรับ Alder Lake ครบ (กราฟิก/เสียง/พลังงาน)
- ชุดกล้อง Intel IPU6 + SOF เสียง ถูกเตรียมไว้ให้ดีที่สุดในบรรดา distro หลัก
- ลงนาม Secure Boot ให้ทุกอย่างใน repo แล้ว ไม่ต้องจัดการใบรับรองเอง

(ทางเลือก: Ubuntu 24.04+ ก็ใช้ได้ แต่กล้อง IPU6 ต้องลงแพ็กเกจเสริม และ kernel
เก่ากว่า — ดู [03-troubleshooting.md](03-troubleshooting.md))

## ขั้นที่ 1 — เตรียมงานบน Windows (สำคัญ อย่าข้าม)

1. **สำรองข้อมูลทั้งหมด** ที่อยู่บนเครื่อง (ถ้าจะล้างเครื่อง) — ย้ำอีกครั้ง: สำรองก่อนเสมอ
2. **อัปเดต BIOS ให้ล่าสุด** ผ่านแอป **Lenovo Vantage**
   (เมนู Device → System Update) — เฟิร์มแวร์เก่าเป็นสาเหตุของปัญหา input/พลังงานหลายอย่าง
3. **BitLocker:** ถ้าเปิดไว้และจะติดตั้งแบบ dual-boot ให้พิมพ์ recovery key เก็บไว้ก่อน
   (Settings → Privacy & Security → Device encryption → Back up your recovery key)
   ถ้าจะล้างเครื่องทั้งหมด ให้ decrypt ก่อนเพื่อความราบรื่น
4. **เช็ครุ่นเครื่องจริง** จดไว้ใช้ตอนหา driver:
   - สติกเกอร์ใต้เครื่อง: บรรทัด "Machine Type Model" (รูปแบบ `83DFxxxxxx`)
   - หรือบน Windows: เปิด PowerShell แล้วรัน `Get-CimInstance Win32_ComputerSystem | Select Manufacturer, Model`
5. **เตรียม USB ติดตั้ง:** เครื่องนี้มีพอร์ต **USB-C** พอร์ตเดียว ต้องใช้แฟลชไดรฟ์ USB-C
   (หรือ USB-A + ฮับแปลง) ความจุ ≥ 8 GB
   - ดาวน์โหลด [Fedora Workstation](https://fedoraproject.org/workstation/download)
   - เขียนลงแฟลชไดรฟ์ด้วย [Fedora Media Writer](https://flathub.org/apps/org.fedoraproject.MediaWriter)
     (มีเวอร์ชัน Windows) — เลือก "Custom image" ถ้าโหลด ISO ไว้แล้ว

## ขั้นที่ 2 — ติดตั้ง

1. ปิดเครื่อง → ต่อแฟลชไดรฟ์ → กดปุ่มเปิด **ค้างไว้** (หรือกดปุ่ม Novo ถ้ามี)
   จนขึ้นเมนูบูต → เลือก Boot Menu → เลือกแฟลชไดรฟ์ (ตัวที่เขียน UEFI ไว้)
2. ในหน้าจอ Fedora installer (GNOME Initial Setup / Anaconda):
   - เลือกภาษา แล้วเข้าสู่หน้า "Installation Destination"
   - **แบบล้างเครื่อง (แนะนำถ้าไม่ต้องการ Windows):** เลือก Automatic storage
     configuration ให้ตัวติดตั้งจัดพาร์ติชันเอง
   - **แบบ dual-boot:** เลือก Custom → ย่อพาร์ติชัน Windows ให้เหลือว่าง ≥ 80 GB
     แล้วสร้างพาร์ติชันใหม่ให้ Fedora
   - ตั้ง user/รหัสผ่าน — แนะนำติ๊ก "administrator" เพื่อใช้ sudo ได้
3. ระหว่างรอ สามารถทดสอบฮาร์ดแวร์ในหน้าจอ live ได้เลย: จอสัมผัส, เสียง, Wi-Fi
   (ถ้าขั้นตอนไหนพัง บันทึกอาการไว้ — มีผลต่อขั้นถัดไป)

> เคล็ดลับตอนติดตั้งบนเครื่องแท็บเล็ต: ถ้าหน้าจอหมุนผิดทิศ ให้ถอดคีย์บอร์ด folio
> แล้วหมุนเครื่อง หรือใช้ปุ่มพลังงาน + volume ช่วยเลือกเมนู

## ขั้นที่ 3 — หลังติดตั้ง

1. เชื่อมต่ออินเทอร์เน็ต แล้วอัปเดตทุกอย่าง:
   ```bash
   sudo dnf upgrade --refresh
   ```
   รีบูตหากมีอัปเดตเคอร์เนล — อยู่บนเคอร์เนลล่าสุดเสมอเวลาแก้ปัญหาฮาร์ดแวร์
2. คัดลอกโปรเจกต์นี้เข้าเครื่อง แล้วรัน:
   ```bash
   sudo bash scripts/post-install.sh
   ```
3. รีบูต 1 ครั้ง แล้วตรวจสอบทีละอย่างตามตารางใน [README](../README.md)
4. รันเก็บข้อมูลจริงเพื่อยืนยันว่าครบ:
   ```bash
   sudo bash scripts/probe-hardware.sh
   ```
   เปิดไฟล์ `duet5i-probe-*/SUMMARY.txt` ดู — ถ้ามีอะไรไม่ได้ตามตาราง
   ให้เปิด [03-troubleshooting.md](03-troubleshooting.md) ตามอาการ
