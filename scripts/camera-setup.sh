#!/usr/bin/env bash
# camera-setup.sh — ติดตั้งชุดส่วนประกอบกล้อง Intel IPU6 ให้ครบตาม distro
#
# Fedora (แนะนำ): ทุกอย่างอยู่ใน repo หลัก — libcamera/qcam + PipeWire portal
# Ubuntu: ต้องเพิ่มชุด intel-ipu6 (DKMS + HAL + libcamera แบบแพตช์)
#         ถ้าเปิด Secure Boot โมดูล DKMS จะโหลดไม่ได้จนลงนาม MOK — สคริปต์ตรวจให้
#
# หลังติดตั้งเสร็จจะเรียก camera-check.sh สรุปสถานะให้ทันที
#   sudo bash camera-setup.sh

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "ต้องรันด้วย sudo" >&2
    exit 1
fi

say() { printf '%s\n' "$*"; }

# ---------- ตรวจ Secure Boot (สำคัญกับเส้นทาง Ubuntu เท่านั้น) ----------
sb_state="unknown"
if command -v mokutil >/dev/null 2>&1; then
    sb_state=$(mokutil --sb-state 2>/dev/null | head -1)
fi

if command -v dnf >/dev/null 2>&1; then
    say "== Fedora: ติดตั้งชุด libcamera/PipeWire (ทุกอย่างใน repo หลัก) =="
    dnf install -y libcamera libcamera-tools libcamera-gstreamer v4l-utils \
        xdg-desktop-portal xdg-desktop-portal-gnome || true
elif command -v apt >/dev/null 2>&1; then
    say "== Ubuntu: ติดตั้งชุด libcamera พื้นฐาน =="
    apt update
    apt install -y libcamera-tools libcamera-gstreamer v4l-utils \
        xdg-desktop-portal xdg-desktop-portal-gtk || true
    say ""
    say "== Ubuntu: ชุดเสริมของ Intel สำหรับ IPU6 =="
    if [ "$sb_state" != "SecureBoot disabled" ]; then
        say "⚠️  ตรวจพบ SecureBoot อยู่ในสถานะ: $sb_state"
        say "    โมดูล DKMS (intel-ipu6-dkms/intel-ivsc-dkms) จะโหลดไม่ได้จนกว่าจะลงนาม MOK:"
        say "    sudo kmodgenca -a && sudo mokutil --import /etc/pki/kernel/module-signing-ca.crt"
        say "    แล้วรีบูตเพื่อ Enroll MOK — หรือปิด Secure Boot ใน BIOS ก็ได้"
    fi
    if apt install -y intel-ipu6-dkms intel-ivsc-dkms; then
        say "ติดตั้ง DKMS แล้ว (จะ build ให้อัตโนมัติทุกครั้งที่เคอร์เนลอัปเดต)"
    else
        say "!! ติดตั้ง intel-ipu6-dkms ไม่สำเร็จ — อาจยังไม่มีใน repo ของรุ่นนี้"
        say "   ดูคู่มือล่าสุด: https://discourse.ubuntu.com/t/intel-mipi-laptop-camera-not-working-24-04/63403"
    fi
    apt install -y intel-ipu6-camera-bins intel-ipu6-camera-hal 2>/dev/null \
        || say "!! ไม่มีแพ็กเกจ intel-ipu6-camera-bins/hal ใน repo — ตามคู่มือด้านบน"
else
    say "!! ไม่รู้จัก distro — ติดตั้ง libcamera และส่วนประกอบ IPU6 ด้วยตัวเอง" >&2
fi

say ""
say "== ตรวจสถานะหลังติดตั้ง =="
bash "$ROOT/scripts/camera-check.sh" || true
say ""
say "ถ้ายัง ❌: รีบูต warm 1 ครั้ง (แก้ cold boot ได้ส่วนใหญ่) แล้วรัน"
say "  sudo bash $ROOT/scripts/camera-check.sh"
