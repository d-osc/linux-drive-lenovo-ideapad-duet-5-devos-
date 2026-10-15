#!/usr/bin/env bash
# camera-check.sh — วินิจฉัยกล้อง Intel IPU6 ของ Duet 5i เชิงลึก + กู้คืน
#
# ตรวจ 7 ชั้น: เคอร์เนล → โมดูล → media devices → เซ็นเซอร์ใน topology →
# /dev/video* → libcamera เห็นกล้อง → dmesg/portal
# แต่ละชั้นบอก ✅/⚠️/❌ พร้อมวิธีแก้ และมีโหมดกู้คืน:
#
#   sudo bash camera-check.sh            ตรวจอย่างเดียว (ไม่ต้อง root)
#   sudo bash camera-check.sh --fix      ตรวจ + ลองกู้คืน (rebind โมดูล IPU6/IVSC
#                                        ผ่าน PCI — แก้อาการ cold boot ไม่ init)
#
# การทดสอบ (ไม่ต้องมีฮาร์ดแวร์): ให้ไฟล์จำลองผลลัพธ์ผ่านตัวแปรสภาพแวดล้อม
#   DUET5I_MEDIACTL_OUT=<ไฟล์ media-ctl -p รวมทุกตัว>
#   DUET5I_CAM_OUT=<ไฟล์ผล cam -l>   DUET5I_DMESG_FILE=<ไฟล์ dmesg>

set -u
FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

say() { printf '%s\n' "$*"; }
ok=0; warn=0; bad=0
report() { # report <สถานะ ok|warn|bad> <ชื่อ> <วิธีแก้>
    case "$1" in
        ok)   say "  ✅ $2"; ok=$((ok+1)) ;;
        warn) say "  ⚠️ $2"; say "     → $3"; warn=$((warn+1)) ;;
        *)    say "  ❌ $2"; say "     → แก้: $3"; bad=$((bad+1)) ;;
    esac
}

# แหล่งข้อมูล (สามารถ override ด้วยไฟล์จำลองเพื่อทดสอบ)
mediactl_dump() {
    if [ -n "${DUET5I_MEDIACTL_OUT:-}" ] && [ -f "$DUET5I_MEDIACTL_OUT" ]; then
        cat "$DUET5I_MEDIACTL_OUT"
    else
        for m in /dev/media[0-9]*; do
            [ -e "$m" ] || continue
            media-ctl -d "$m" -p 2>/dev/null
        done
    fi
}
cam_list() {
    if [ -n "${DUET5I_CAM_OUT:-}" ] && [ -f "$DUET5I_CAM_OUT" ]; then
        cat "$DUET5I_CAM_OUT"
    elif command -v cam >/dev/null 2>&1; then
        cam -l 2>/dev/null
    else
        return 1
    fi
}
dmesg_dump() {
    if [ -n "${DUET5I_DMESG_FILE:-}" ] && [ -f "$DUET5I_DMESG_FILE" ]; then
        cat "$DUET5I_DMESG_FILE"
    else
        dmesg 2>/dev/null
    fi
}

say "================ วินิจฉัยกล้อง Intel IPU6 ================"

# 1) เคอร์เนล ≥ 6.12
kver=$(uname -r)
kmajor=$(printf '%s' "$kver" | cut -d. -f1); kminor=$(printf '%s' "$kver" | cut -d. -f2)
if [ "${kmajor:-0}" -gt 6 ] || { [ "${kmajor:-0}" -eq 6 ] && [ "${kminor:-0}" -ge 12 ]; }; then
    report ok "เคอร์เนล $kver (≥ 6.12: มีไดรเวอร์ IPU6 ในต้นไม้หลัก)"
else
    report bad "เคอร์เนล $kver เก่าเกิน (ต้อง ≥ 6.12)" "อัปเดตเคอร์เนลของ distro (Fedora ล่าสุด) หรือดู docs/03 หัวข้อ Ubuntu"
fi

# 2) โมดูล IPU6/IVSC
lsmod | grep -qiE 'ipu6' && report ok "โมดูล ipu6 โหลดแล้ว" \
    || report bad "โมดูล ipu6 ไม่ได้โหลด" "Fedora: มีในเคอร์เนลอยู่แล้ว (รีบูต) / Ubuntu: intel-ipu6-dkms + intel-ivsc-dkms"
lsmod | grep -qiE 'ivsc' && report ok "โมดูล ivsc (ตัวช่วยกล้อง Intel) โหลดแล้ว" \
    || report warn "โมดูล ivsc ไม่ได้โหลด" "บางรุ่นเครื่องไม่มีก็ใช้ได้ — ถ้ากล้องไม่ขึ้นค่อยลง intel-ivsc-dkms"

# 3) media devices
ls /dev/media[0-9]* >/dev/null 2>&1 && report ok "มี media device ($(ls /dev/media[0-9]* | wc -l | tr -d ' ') ตัว)" \
    || report bad "ไม่มี /dev/media*" "อาการ cold boot — ลอง sudo bash $0 --fix หรือรีบูตแบบ warm (รีสตาร์ตเฉยๆ)"

# 4) เซ็นเซอร์ใน topology
topology=$(mediactl_dump)
if [ -n "$topology" ]; then
    sensors=$(printf '%s\n' "$topology" | grep -oE '(ov01a1s|ov02c10|ov08a10|ov2740|hi556|hm11b1|hm2170)[^ ]*' | sort -u | tr '\n' ' ')
    if [ -n "$sensors" ]; then
        report ok "พบเซ็นเซอร์ใน media topology: $sensors"
    else
        report bad "media topology ไม่มีเซ็นเซอร์กล้อง" "อาการ probe ไม่สำเร็จ — ลอง sudo bash $0 --fix แล้วตรวจซ้ำ / ถ้าไม่หาย รีบูต warm 1 ครั้ง (bug ที่รู้จักของบางเซ็นเซอร์)"
    fi
else
    report warn "อ่าน media topology ไม่ได้ (ไม่มี media-ctl หรือไม่มี /dev/media*)" "dnf install libcamera-tools"
fi

# 5) /dev/video*
n_video=$(ls /dev/video[0-9]* 2>/dev/null | wc -l | tr -d ' ')
[ "$n_video" -gt 0 ] && report ok "มี /dev/video*  $n_video ตัว" \
    || report bad "ไม่มี /dev/video*" "IPU6 ยังไม่สร้าง video node — ทำตามข้อ 3-4 ก่อน"

# 6) libcamera เห็นกล้อง
if camout=$(cam_list); then
    if printf '%s' "$camout" | grep -qiE 'camera|Available|Found'; then
        report ok "libcamera เห็นกล้อง (cam -l มีรายการ)"
    else
        report warn "libcamera ยังไม่เห็นกล้อง" "ต้องมีเซ็นเซอร์ใน topology ก่อน (ข้อ 4) — แก้ข้อนั้นแล้วข้อนี้ตามมาเอง"
    fi
else
    report warn "ไม่มีเครื่องมือ cam (libcamera-tools)" "dnf install libcamera-tools แล้วตรวจซ้ำ"
fi

# 7) สัญญาณปัญหาใน dmesg
errs=$(dmesg_dump | grep -iE 'ipu6|ivsc' | grep -icE 'error|fail|timeout' || true)
[ "$errs" -eq 0 ] && report ok "dmesg ไม่มี error ของ ipu6/ivsc" \
    || report warn "dmesg มี error เกี่ยวกับ ipu6/ivsc $errs บรรทัด" "ส่งผล sudo bash $0 และ dmesg กลับให้ผู้พัฒนา จะได้ quirk เฉพาะจุด"

# ---------- โหมดกู้คืน: rebind โมดูลผ่าน PCI ----------
if [ "$FIX" -eq 1 ]; then
    if [ "$(id -u)" -ne 0 ]; then say "!! --fix ต้องรันด้วย sudo" >&2; exit 1; fi
    say ""
    say "---------- กู้คืน: rebind คอนโทรลเลอร์ IPU6/IVSC ----------"
    rebound=0
    for driver_path in /sys/bus/pci/drivers/*ipu* /sys/bus/pci/drivers/*ivsc*; do
        [ -d "$driver_path" ] || continue
        driver="${driver_path##*/}"
        for dev_path in "$driver_path"/*/; do
            [ -d "$dev_path" ] || continue
            case "${dev_path##*/}" in
                bind|unbind|new_id|remove_id|uevent) continue ;;
            esac
            addr="${dev_path##*/}"
            say "  rebind $driver: $addr"
            printf '%s' "$addr" > "$driver_path/unbind" 2>/dev/null || true
            sleep 0.5
            printf '%s' "$addr" > "$driver_path/bind" 2>/dev/null && rebound=$((rebound+1)) || true
        done
    done
    if [ "$rebound" -gt 0 ]; then
        say "  รีไดรฟ์แล้ว $rebound ตัว — รอ 2 วินาทีแล้วตรวจซ้ำ"
        sleep 2
    else
        say "  ไม่พบอุปกรณ์ IPU6/IVSC บน PCI ให้ rebind (หรืออยู่ในสถานะที่ rebind ไม่ได้)"
        say "  → ลองรีบูตแบบ warm (รีสตาร์ต) 1 ครั้ง ซึ่งแก้อาการ cold boot ได้ในกรณีส่วนใหญ่"
    fi
    say "ตรวจซ้ำหลังกู้คืน: sudo bash $0"
fi

say ""
say "ผลรวม: ✅ $ok / ⚠️ $warn / ❌ $bad"
if [ "$bad" -eq 0 ]; then
    say "กล้องพร้อมใช้งาน — ทดสอบเปิดภาพด้วย: qcam"
    exit 0
fi
say "ทำตาม \"→ แก้:\" จากบนลงล่าง แล้วรันซ้ำ — ส่งผลกลับให้ผู้พัฒนาได้ทุกเมื่อ"
exit 1
