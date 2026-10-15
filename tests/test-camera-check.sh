#!/bin/sh
# ทดสอบ camera-check.sh ด้วยไฟล์จำลองผลลัพธ์ (media-ctl / cam / dmesg)
set -eu
root="/mnt/c/Users/ondev/Projects/development/lab/linux-driver-lenovo-ideapad-duet-5"
tmp=$(mktemp -d /tmp/fake-cam-XXXXXX)

# กรณี 1: topology มีเซ็นเซอร์ ov01a1s + libcamera เห็นกล้อง + dmesg สะอาด
cat > "$tmp/mediactl-ok.txt" <<'EOF'
Media controller information for driver ipu6-isys:
Entity 21: ov01a1s 17-0010 (1 pad, 1 link)
	Entity 22: Intel ipu6-isys CSI2 1
EOF
cat > "$tmp/cam-ok.txt" <<'EOF'
Using cameras:
1: /base/pci_0000:00:05.0/platform/ipu6/isys/csiport0/ov01a1s@0010 [ov01a1s]
EOF
: > "$tmp/dmesg-clean.txt"

out=$(DUET5I_MEDIACTL_OUT="$tmp/mediactl-ok.txt" DUET5I_CAM_OUT="$tmp/cam-ok.txt" \
      DUET5I_DMESG_FILE="$tmp/dmesg-clean.txt" \
      bash "$root/scripts/camera-check.sh" 2>&1 || true)
printf '%s\n' "$out" | grep -q 'พบเซ็นเซอร์ใน media topology: ov01a1s' \
    && echo "PASS: ตรวจพบเซ็นเซอร์ ov01a1s จาก topology จำลอง" || { echo "FAIL: ไม่เจอเซ็นเซอร์"; exit 1; }
printf '%s\n' "$out" | grep -q 'libcamera เห็นกล้อง' \
    && echo "PASS: libcamera รายงานเห็นกล้อง" || { echo "FAIL: libcamera"; exit 1; }
printf '%s\n' "$out" | grep -q 'dmesg ไม่มี error' \
    && echo "PASS: dmesg สะอาด" || { echo "FAIL: dmesg"; exit 1; }

# กรณี 2: มี topology แต่ไม่มีเซ็นเซอร์ (อาการ cold boot probe ไม่สำเร็จ) ต้องแนะนำ --fix
cat > "$tmp/mediactl-nosensor.txt" <<'EOF'
Media controller information for driver ipu6-isys:
Entity 5: Intel ipu6-isys CSI2 0
Entity 9: Intel ipu6-isys video 1
EOF
out2=$(DUET5I_MEDIACTL_OUT="$tmp/mediactl-nosensor.txt" \
       bash "$root/scripts/camera-check.sh" 2>&1 || true)
printf '%s\n' "$out2" | grep -q 'media topology ไม่มีเซ็นเซอร์' \
    && echo "PASS: รายงานไม่พบเซ็นเซอร์ (cold boot) พร้อมคำแนะนำ --fix" || { echo "FAIL: ต้องแจ้งไม่พบเซ็นเซอร์"; exit 1; }

# กรณี 3: dmesg มี error ต้องนับเป็น ⚠️ และแนะนำส่งกลับ
cat > "$tmp/dmesg-bad.txt" <<'EOF'
ipu6-isys ipu6-isys.0: failed to setup routing
ivsc ivsc.1: timeout on probe
EOF
out3=$(DUET5I_MEDIACTL_OUT="$tmp/mediactl-ok.txt" DUET5I_CAM_OUT="$tmp/cam-ok.txt" \
       DUET5I_DMESG_FILE="$tmp/dmesg-bad.txt" \
       bash "$root/scripts/camera-check.sh" 2>&1 || true)
printf '%s\n' "$out3" | grep -q 'error เกี่ยวกับ ipu6/ivsc 2 บรรทัด' \
    && echo "PASS: นับ error ใน dmesg ได้ถูกต้อง (2 บรรทัด)" || { echo "FAIL: นับ dmesg ผิด"; exit 1; }

rm -rf "$tmp"
echo "TEST-DONE"
