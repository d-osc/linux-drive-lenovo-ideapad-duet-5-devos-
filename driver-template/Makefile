# Makefile สำหรับ build โมดูลนอกต้นไม้เคอร์เนล (out-of-tree module)
#
# การใช้งาน (บนเครื่อง Linux ที่ติดตั้ง linux-headers แล้ว):
#   make            — build กับเคอร์เนลที่กำลังรันอยู่
#   make load      — insmod ทันที
#   make unload    — rmmod
#   make clean     — ลบไฟล์ build

obj-m += duet5i_template.o

KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build

all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) modules

load: all
	-modprobe -q misc 2>/dev/null || true
	insmod duet5i_template.ko

unload:
	-rmmod duet5i_template

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) clean

.PHONY: all load unload clean
