# 04 — ติดตั้ง DevOs (desktop environment) บน Duet 5i + ส่วนเสริมฮาร์ดแวร์

[DevOs](https://github.com/d-osc/DevOs) คือ desktop environment บน Wayland ที่ใช้
**labwc** เป็น compositor และเขียน shell ด้วย TypeScript/GJS + React → GTK
โปรเจกต์ของเราได้เพิ่ม "driver support" ให้ DevOs สำหรับฮาร์ดแวร์ของ Duet 5i แล้ว
(อยู่ในโฟลเดอร์ `DevOs/` ข้างใน repo นี้ — clone มาพร้อมแก้ไข)

## DevOs ใช้อะไร (สรุปจากการอ่าน repo)

| ส่วน | เทคโนโลยี |
|---|---|
| Compositor | labwc (wlroots) + gtk-layer-shell |
| Shell/Extension | TypeScript + React 19 (render ไปที่ widget ของ GTK3 จริง ไม่ใช่ HTML) |
| Runtime | GJS (GNOME JavaScript) — Node.js ใช้ตอน build เท่านั้น |
| ระบบ | D-Bus, PipeWire (`wpctl`), NetworkManager (`nmcli`), BlueZ (`bluetoothctl`) |

ส่วนที่ต้อง "ทำเพิ่ม" สำหรับแท็บเล็ต Duet 5i คือชั้นเชื่อมฮาร์ดแวร์
(devOs ต้นฉบับมีเสียง/Wi-Fi/แบตอยู่แล้ว แต่ไม่มีแสงจอ, หมุนจอ, OSK, ปุ่มฟังก์ชัน)

## สิ่งที่เราเพิ่มให้ (โฟลเดอร์ `DevOs/`)

| ไฟล์ | เนื้อหา |
|---|---|
| `extensions/org.devos.duet5i/extension.json` | manifest + หน้าตั้งค่า (ขั้นแสงจอ, หมุนจอ, OSK) |
| `extensions/org.devos.duet5i/extension.ts` | lifecycle: อ่านค่าตั้งค่า, ต่อบริการ, ลงทะเบียนคำสั่ง |
| `extensions/org.devos.duet5i/hardware.ts` | บริการหลัก: แสงจอผ่าน logind, iio-sensor-proxy → wlr-randr, ตรวจถอด folio, จัดการ OSK, ปุ่มเสียง |
| `config/labwc/rc.xml` | เพิ่ม keybind ปุ่ม XF86 แสงจอ/เสียง + `W-o` (OSK) + `W-d` (ล็อกหมุนจอ) |
| `docs/duet5i-hardware.md` | เอกสารภาษาไทยของ extension นี้ (ตามรูปแบบเอกสารของ DevOs) |

คำสั่งที่ได้เพิ่ม (เรียกจาก labwc หรือ terminal ผ่าน `dev-os-shell <คำสั่ง>`):
`brightness-up`, `brightness-down`, `volume-up`, `volume-down`, `volume-mute`,
`osk-toggle`, `rotate-lock`

## ขั้นตอนติดตั้งบนเครื่อง Duet 5i

> สมมติว่าติดตั้ง Fedora ตาม [01-install.md](01-install.md) แล้ว (หรือ distro ที่มี
> labwc + GJS รุ่นใหม่) — DevOs ไม่จำเป็นต้องแทน GNOME ทั้งเครื่อง เลือกใช้ session
> ได้ตอนล็อกอิน

1. ติดตั้ง dependency ของระบบ:
   ```bash
   sudo dnf install labwc gjs nodejs npm iio-sensor-proxy wlr-randr wvkbd \
                    gtk-layer-shell gtk3 vte291 webkit2gtk4.1
   systemctl --user enable --now pipewire wireplumber   # เสียง (มักเปิดอยู่แล้ว)
   ```
2. คัดลอก DevOs ที่แก้แล้วเข้าเครื่อง (โฟลเดอร์ `DevOs/` ใน repo นี้) แล้ว build:
   ```bash
   cd DevOs
   npm ci
   npm run build
   ```
   ตรวจว่าได้ `dist/org.devos.duet5i.js` แล้ว (build บนเครื่องจริงจะ validate manifest ให้อัตโนมัติ)
3. ติดตั้งเข้าระบบ (ดีฟอลต์ติดตั้งไปที่ `~/.local` ของผู้ใช้ ไม่ต้อง sudo —
   `make install` จะ build ให้อีกครั้งแล้วเรียกสคริปต์ติดตั้ง):
   ```bash
   make install            # หรือ make install PREFIX=/usr/local ถ้าต้องการทั้งระบบ
   ```
   หรือรันแบบไม่ติดตั้งจากโฟลเดอร์ build: `sh bin/dev-os-session`
4. เข้า session "Dev OS" จากหน้าจอล็อกอิน (หรือรัน labwc ด้วย `dev-os-session`)

## ทดสอบทีละอย่าง

> **หมายเหตุจอ 2.5K:** เครื่องจริงมีจอ 2560×1600 ที่ 12.3 นิ้ว (~213 PPI) — เปิด scale
> ใน `config/labwc/rc.xml` (มีตัวอย่าง `<output><scale>2</scale></output>` คอมเมนต์ไว้ให้
> เอาคอมเมนต์ออกแล้วปรับชื่อ output ตามผล `wlr-randr` ให้ตรงกับจอของเครื่อง)
> ไม่งั้นทุกอย่างจะเล็กจิ๋วมากบนจอความละเอียดสูง

## รันทดลองบน WSLg (บนเครื่อง Windows นี้ได้เลย)

สภาพแวดล้อมทดสอบทั้งหมดอยู่ใน `DevOs/build/wsl/` (rootless ไม่ต้อง sudo) — เรียกใช้ผ่าน
WSL Ubuntu ที่มีอยู่แล้ว:

```bash
# สตาร์ท DevOs เป็นหน้าต่างบนจอ Windows (WSLg) — จะได้หน้าต่าง "wlroots - WL-1"
MSYS_NO_PATHCONV=1 wsl -d Ubuntu -- bash /mnt/c/<path>/DevOs/build/wsl/run-nested-duet5i.sh

# ส่งคำสั่งเข้า session ที่กำลังรันอยู่ (เปิดแอป/คำสั่งของ extension เรา)
MSYS_NO_PATHCONV=1 wsl -d Ubuntu -- bash /mnt/c/<path>/DevOs/build/wsl/demo-command.sh settings
MSYS_NO_PATHCONV=1 wsl -d Ubuntu -- bash /mnt/c/<path>/DevOs/build/wsl/demo-command.sh terminal
MSYS_NO_PATHCONV=1 wsl -d Ubuntu -- bash /mnt/c/<path>/DevOs/build/wsl/demo-command.sh rotate-lock
```

สิ่งที่พิสูจน์แล้วด้วยวิธีนี้ (จับภาพหน้าจอจริงยืนยัน): desktop + wallpaper เรนเดอร์,
launcher, หน้าต่าง Settings ที่แสดงหมวด "Duet 5i hardware" ใน sidebar,
หน้าต่าง Terminal (VTE) พร้อม shell prompt — ทั้งหมดรันบน labwc 0.7.1
ที่ build เองพร้อม patch ของโปรเจกต์

ข้อจำกัดบน WSLg: แสงจอ/เซ็นเซอร์หมุนจอ/เสียง ไม่มีฮาร์ดแวร์จริงให้ใช้ (extension
จะแจ้ง diagnostic แล้วทำงานส่วนอื่นต่อ) และเรนเดอร์เป็น software (pixman)

```bash
# แสงจอ (ควรเปลี่ยนทันที ไม่ต้องใช้ sudo)
dev-os-shell brightness-up
dev-os-shell brightness-down

# เสียง (ปุ่มบน folio ควรทำงานด้วย)
dev-os-shell volume-up
dev-os-shell volume-mute

# หมุนจอ: หมุนเครื่องจริง จอควรหมุนตามใน ~1 วินาที
# ล็อก/ปลดล็อกการหมุน
dev-os-shell rotate-lock

# คีย์บอร์ดจอ: ถอด folio ออก → OSK ควรโผล่เอง (หรือกด W-o / dev-os-shell osk-toggle)
```

ปรับการตั้งค่าได้ใน **Settings → Duet 5i hardware** (ขั้นแสงจอ, กลับทิศ 90/270,
เปิด/ปิด OSK อัตโนมัติ, คำสั่ง OSK, USB ID ของ folio)

## ถ้าอะไรไม่ทำงาน

อ่าน [DevOs/docs/duet5i-hardware.md](../DevOs/docs/duet5i-hardware.md) ในโฟลเดอร์ DevOs
ที่อธิบายกลไกแต่ละส่วน และดู diagnostic จาก shell:
```bash
# รัน session แบดู log
sh bin/dev-os-session 2>~/devos.log
grep -i 'duet 5i' ~/devos.log
```
สาเหตุที่พบบ่อย: ยังไม่ได้ลง `iio-sensor-proxy` (หมุนจอไม่ทำงาน), ยังไม่ได้ลง `wvkbd`
(OSK ไม่โผล่), หรือเคอร์เนลยังไม่จับเซ็นเซอร์ (ดู [03-troubleshooting.md](03-troubleshooting.md) เรื่องหมุนจอ)

## การทดสอบที่ทำไปแล้ว (บน WSL2 + WSLg แบบ rootless ทั้งหมด)

สร้างสภาพแวดล้อมทดสอบจริงไว้ที่ `DevOs/build/wsl/` (ไม่ต้อง sudo เลย — GJS,
typelibs, toolchain cc/meson/ninja, wlroots 0.17.4 และ labwc 0.7.1 พร้อม patch
ของโปรเจกต์ คอมไพล์จากซอร์สด้วยแพตเทิร์น `apt-get download` + `dpkg-deb -x`)

ผลที่ผ่านแล้ว:

| ชุดทดสอบ | ผล |
|---|---|
| TypeScript typecheck (`tsc --noEmit`) | ✅ ผ่าน |
| GJS test ของ DevOs: config / extensions / updates / store | ✅ 4/4 ชุด |
| Targeted test ของ `org.devos.duet5i` (activate / cleanup / คำสั่งครบ 7 / degradation ไม่ crash / reload ค่า settings) | ✅ ผ่านทุกข้อ |
| Headless session จริง (labwc 0.7.1 ที่ build เอง + shell + extension activate ใน ~4 ms) | ✅ ผ่าน |
| Remote commands ผ่าน `dev-os-shell` บน D-Bus ครบทั้ง 7 คำสั่ง | ✅ ผ่าน |
| Smoke suite ของโปรเจกต์ (`tools/test/smoke.py`) | ⚠️ บางส่วน — session + renderer-test ผ่าน แต่ desktop-ui-test ติดข้อจำกัด rootless (WebKit spawn `WebKitNetworkProcess` ด้วย absolute path ที่ฝังใน binary) ไม่ใช่ปัญหาของโค้ดเรา |

บั๊กจริง 1 ตัวที่การทดสอบนี้จับได้และแก้แล้ว: `src/main.ts` ของ DevOs มี whitelist
คำสั่ง CLI — คำสั่งของ extension เราไม่อยู่ในลิสต์ ทำให้ปุ่มแสงจอ/เสียงบน folio
จะส่งคำสั่งไม่ถึง shell บนเครื่องจริง (เพิ่ม 7 คำสั่งเข้า whitelist แล้ว
พร้อมอัปเดต `tests/extensions.test.ts` ให้นับ extension 12 ตัว)

## ส่งกลับไป upstream

โค้ดที่เราเพิ่มเป็น extension แบบ system ที่ไม่แตะ package อื่น (ยกเว้นไฟล์
whitelist และ test ที่จำเป็นต้องแก้ตามธรรมเนียมของโปรเจกต์) — เหมาะจะส่ง
PR กลับไปที่ d-osc/DevOs ได้ทันที ถ้าไม่อยากรอต้นทางรวม ก็ใช้ Extension Store
ของ DevOs แจกเป็น user extension ได้ (ดู `docs/extension-store.md` ของ DevOs)
