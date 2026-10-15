// SPDX-License-Identifier: GPL-2.0
/*
 * duet5i_template.c — แม่แบบโมดูลเคอร์เนลสำหรับ IdeaPad Duet 5i
 *
 * วัตถุประสงค์: เป็นจุดตั้งต้นของไดรเวอร์ใหม่ เมื่อผลจาก probe-hardware.sh
 * พบอุปกรณ์ที่เคอร์เนลยังไม่มีไดรเวอร์ให้
 *
 * โครงสร้างนี้ประกอบด้วย:
 *   1. โมดูลพื้นฐาน (init/exit) — โหลด/ถอดได้ทันทีด้วย insmod/rmmod
 *   2. อุปกรณ์ misc character device — ให้ userspace อ่าน/เขียนผ่าน /dev/duet5i0
 *      (เหมาะกับเซ็นเซอร์/ฟีเจอร์พิเศษของเครื่อง เช่น สถานะการถอดคีย์บอร์ด)
 *   3. ตัวอย่างการจับ platform device และ USB device อยู่ใน comment ด้านล่าง
 *
 * การเลือกประเภทไดรเวอร์ที่ถูกต้อง (สำคัญที่สุดของงานนี้):
 *   - อุปกรณ์ I2C (จอสัมผัส/ทัชแพตบางรุ่น) → drivers/hid/i2c-hid หรือ drivers/input
 *   - อุปกรณ์ USB (คีย์บอร์ด folio)     → struct usb_driver / usbhid quirks
 *   - เซ็นเซอร์หมุนจอ                   → drivers/iio (accelerometer)
 *   - ACPI device (ปุ่มพิเศษ/VBT)       → platform driver + struct acpi_device_id
 *
 * เอกสารเริ่มต้น: Documentation/driver-api ในซอร์สของเคอร์เนล
 * และคู่มือ "Linux Device Drivers" (LDD3) + ตัวอย่างล่าสุดในเคอร์เนล
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/uaccess.h>

#define DRIVER_NAME "duet5i_template"
#define DEVICE_NAME "duet5i0"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("คุณ <you@example.com>");
MODULE_DESCRIPTION("Skeleton driver for Lenovo IdeaPad Duet 5i hardware");
MODULE_VERSION("0.1");

/* ------------------------------------------------------------------ */
/* ส่วน character device — ทดลอง: cat /dev/duet5i0                     */
/* ------------------------------------------------------------------ */

static char response[] = "duet5i skeleton driver alive\n";

static int duet5i_open(struct inode *inode, struct file *file)
{
	pr_info(DRIVER_NAME ": open\n");
	return 0;
}

static ssize_t duet5i_read(struct file *file, char __user *buf,
			   size_t count, loff_t *ppos)
{
	size_t len = sizeof(response) - 1;

	if (*ppos >= len)
		return 0;
	if (count > len - *ppos)
		count = len - *ppos;
	if (copy_to_user(buf, response + *ppos, count))
		return -EFAULT;
	*ppos += count;
	return count;
}

static ssize_t duet5i_write(struct file *file, const char __user *buf,
			    size_t count, loff_t *ppos)
{
	pr_info(DRIVER_NAME ": write (%zu bytes) — ต่อยอดเป็นคำสั่งควบคุมได้ที่นี่\n",
		count);
	return count;
}

static const struct file_operations duet5i_fops = {
	.owner = THIS_MODULE,
	.open = duet5i_open,
	.read = duet5i_read,
	.write = duet5i_write,
};

static struct miscdevice duet5i_misc = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = DEVICE_NAME,
	.fops = &duet5i_fops,
	.mode = 0666,
};

/* ------------------------------------------------------------------ */
/* ตัวอย่าง: การจับ platform device ที่ ACPI แจ้ง (เอา comment ออกเมื่อใช้) */
/* ------------------------------------------------------------------ */
/*
#include <linux/platform_device.h>

static const struct acpi_device_id duet5i_acpi_ids[] = {
	{ "XXXX0000", 0 },   // ← รหัส _HID จาก: grep -r . /sys/bus/acpi/devices/*/hid
	{ }
};
MODULE_DEVICE_TABLE(acpi, duet5i_acpi_ids);

static int duet5i_probe(struct platform_device *pdev)
{
	pr_info(DRIVER_NAME ": probe %s\n", dev_name(&pdev->dev));
	return 0;
}

static int duet5i_remove(struct platform_device *pdev)
{
	return 0;
}

static struct platform_driver duet5i_driver = {
	.driver = {
		.name = DRIVER_NAME,
		.acpi_match_table = duet5i_acpi_ids,
	},
	.probe = duet5i_probe,
	.remove = duet5i_remove,
};
module_platform_driver(duet5i_driver);
*/

/* ------------------------------------------------------------------ */
/* ตัวอย่าง: การจับ USB device (เช่น คีย์บอร์ด folio)                    */
/* ------------------------------------------------------------------ */
/*
#include <linux/usb.h>

static const struct usb_device_id duet5i_usb_ids[] = {
	{ USB_DEVICE(0x1234, 0x5678) },   // ← VID:PID จาก lsusb
	{ }
};
MODULE_DEVICE_TABLE(usb, duet5i_usb_ids);
*/

/* ------------------------------------------------------------------ */
/* จุดเริ่ม/จบของโมดูล                                                  */
/* ------------------------------------------------------------------ */

static int __init duet5i_init(void)
{
	int ret = misc_register(&duet5i_misc);
	if (ret) {
		pr_err(DRIVER_NAME ": misc_register ล้มเหลว (%d)\n", ret);
		return ret;
	}
	pr_info(DRIVER_NAME ": โหลดแล้ว — ลอง: cat /dev/%s\n", DEVICE_NAME);
	return 0;
}

static void __exit duet5i_exit(void)
{
	misc_deregister(&duet5i_misc);
	pr_info(DRIVER_NAME ": ถอดแล้ว\n");
}

module_init(duet5i_init);
module_exit(duet5i_exit);
