# Copyright (c) 2022 Manfred SCHLAEGL <manfred.schlaegl@gmx.at>
#
# SPDX-License-Identifier: BSD 3-clause "New" or "Revised" License
#

BUILDROOT_GIT=https://gitlab.com/buildroot.org/buildroot.git
BUILDROOT_VERSION=2026.02
VP_NAME=riscv-vp-plusplus
VP_GIT=https://github.com/ics-jku/$(VP_NAME).git
VP_VERSION=master
MRAM_IMAGE_DIR=runtime_mram
UEFI_CODE_IMAGE=images/RISCV_VIRT_CODE.fd
UEFI_VARS_IMAGE=images/RISCV_VIRT_VARS.fd

LINUX_RV64_BUILD_DIR?=buildroot_rv64/output/build/linux-6.19.10/
VMLINUX_RV64?=$(LINUX_RV64_BUILD_DIR)/vmlinux
KERNEL_EFI_IMAGE_RV64?=$(LINUX_RV64_BUILD_DIR)/arch/riscv/boot/Image
RV64_OBJCOPY?=buildroot_rv64/output/host/bin/riscv64-buildroot-linux-gnu-objcopy
RV64_EFI_BFD_TARGET?=pei-riscv64-little
EFI_BOOT_DIR?=buildroot_rv64/output/images/efi_boot_rv64
EFI_SD_IMAGE?=buildroot_rv64/output/images/rv64_efi_sd.img
VIRTIO_BLK_IMAGE?=$(EFI_SD_IMAGE)
EFI_ESP_OFFSET?=1048576
# VP_ARGS can be overriden by user ($ VP_ARGS="..." make run_...)`
VP_ARGS?=--use-data-dmi --tlm-global-quantum=1000000 --use-dbbcache --use-lscache --tun-device tun10
QEMU_VP_ARGS?=--use-data-dmi --tlm-global-quantum=1000000 --use-dbbcache --use-lscache
GDB_PORT?=1234
GDB_BIN?=gdb-multiarch
UEFI_SEC_FV_BASE?=0x80200000
UEFI_DXE_FV_BASE?=0x80200000
KERNEL_VIRT_BASE?=0xffffffff80000000

LINUX_DT_GEN=$(VP_NAME)/vp/build/bin/linux-dt-gen.py
QEMU_VIRT_DT_GEN=$(VP_NAME)/vp/build/bin/qemu_virt-dt-gen.py
DT_BOOTARGS="earlycon=sbi root=/dev/mtdblock0 rootfstype=squashfs ro"
BR_DTC="output/host/bin/dtc"

# memory configuration (vp paramter + device tree)
MEM_SIZE_RV32=$(shell echo $$((1 * 1024*1024*1024)))	# 1 GiB
MEM_SIZE_RV64=$(shell echo $$((2 * 1024*1024*1024)))	# 2 GiB


.PHONY: help all get dtb build_rv32 build_rv64 build vp-rebuild buildroot-reconfigure	\
	buildroot_rv32-rebuild buildroot_rv64-rebuild buildroot-rebuild						\
	run_rv32 run_rv64 run_rv64_mc_uefi run_qemu_virt64_mc_uefi run_qemu_virt64_mc_uefi_dynamic	\
	run_qemu_virt64_mc_uefi_gdb run_qemu_virt64_mc_uefi_dynamic_gdb run_qemu_virt64_mc_uefi_sd	\
	build_rv64_efi_sd connect_qemu_virt64_mc_uefi_gdb connect_qemu_virt64_mc_uefi_sd_gdb_kernel connect_qemu_virt64_mc_uefi_sd_gdb_kernel_auto clean distclean

help:
	@echo
	@echo "Targets:"
	@grep '^[^#[:space:]].*:' Makefile | cut -d':' -f1 | grep -v '\.\|dt/\|='
	@echo
	@echo "VP Arguments:"
	@echo $(VP_ARGS)
	@echo "Can be overriden by user"
	@echo "Example: VP_ARGS=\"$(VP_ARGS)\" make run_rv32_sc"
	@echo

all: build

get: .stamp/vp_get .stamp/buildroot_get

build_rv32: .stamp/vp_build .stamp/buildroot_rv32_build dt/linux-vp_rv32_sc.dtb dt/linux-vp_rv32_mc.dtb

build_rv64: .stamp/vp_build .stamp/buildroot_rv64_build dt/linux-vp_rv64_sc.dtb dt/linux-vp_rv64_mc.dtb

build: build_rv32 build_rv64

vp-rebuild:
	rm -rf .stamp/vp_build
	make .stamp/vp_build

buildroot-reconfigure:
	rm -rf .stamp/buildroot_config
	make .stamp/buildroot_config

buildroot_rv32-rebuild:
	rm -rf .stamp/buildroot_rv32_build
	make .stamp/buildroot_rv32_build

buildroot_rv64-rebuild:
	rm -rf .stamp/buildroot_rv64_build
	make .stamp/buildroot_rv64_build

buildroot-rebuild: buildroot_rv32-rebuild buildroot_rv64-rebuild

build_all_dts: dt/linux-vp_rv32_sc.dts dt/linux-vp_rv64_sc.dts dt/linux-vp_rv32_mc.dts dt/linux-vp_rv64_mc.dts

build_all_dtb: dt/linux-vp_rv32_sc.dtb dt/linux-vp_rv64_sc.dtb dt/linux-vp_rv32_mc.dtb dt/linux-vp_rv64_mc.dtb

run_rv32_sc: build_rv32
	$(VP_NAME)/vp/build/bin/linux32-sc-vp						\
		$(VP_ARGS)												\
		--dtb-file=dt/linux-vp_rv32_sc.dtb						\
		--kernel-file buildroot_rv32/output/images/Image		\
		--mram-root-image $(MRAM_IMAGE_DIR)/mram_rv32_root.img	\
		--mram-data-image $(MRAM_IMAGE_DIR)/mram_rv32_data.img	\
		--memory-size $(MEM_SIZE_RV32)							\
		buildroot_rv32/output/images/fw_jump.elf

run_qemu_virt64_mc_uefi_dynamic_gdb: .stamp/vp_build .stamp/buildroot_rv64_build dt/qemu_virt_rv64_mc.dtb
	$(VP_NAME)/vp/build/bin/qemu_virt64-mc-vp					\
		$(QEMU_VP_ARGS)					\
		--debug-mode					\
		--debug-port $(GDB_PORT)			\
		--dtb-file=dt/qemu_virt_rv64_mc.dtb					\
		--uefi-code-image $(UEFI_CODE_IMAGE)					\
		--uefi-vars-image $(UEFI_VARS_IMAGE)					\
		--memory-size $(MEM_SIZE_RV64)					\
		buildroot_rv64/output/images/fw_dynamic.elf
run_rv64_sc: build_rv64
	$(VP_NAME)/vp/build/bin/linux-sc-vp							\
		$(VP_ARGS)												\
		--dtb-file=dt/linux-vp_rv64_sc.dtb						\
		--kernel-file buildroot_rv64/output/images/Image		\
		--mram-root-image $(MRAM_IMAGE_DIR)/mram_rv64_root.img	\
		--mram-data-image $(MRAM_IMAGE_DIR)/mram_rv64_data.img	\
		--memory-size $(MEM_SIZE_RV64)							\
		buildroot_rv64/output/images/fw_jump.elf

run_rv64_mc_uefi: build_rv64
	$(VP_NAME)/vp/build/bin/linux-vp							\
		$(VP_ARGS)								\
		--dtb-file=dt/linux-vp_rv64_mc.dtb						\
		--uefi-code-image $(UEFI_CODE_IMAGE)                    \
		--uefi-vars-image $(UEFI_VARS_IMAGE)					\
		--mram-root-image $(MRAM_IMAGE_DIR)/mram_rv64_root.img	\
		--mram-data-image $(MRAM_IMAGE_DIR)/mram_rv64_data.img	\
		--memory-size $(MEM_SIZE_RV64)							\
		buildroot_rv64/output/images/fw_dynamic.elf

run_qemu_virt64_mc_uefi: .stamp/vp_build .stamp/buildroot_rv64_build dt/qemu_virt_rv64_mc.dtb
	$(VP_NAME)/vp/build/bin/qemu_virt64-mc-vp					\
		$(QEMU_VP_ARGS)								\
		--dtb-file=dt/qemu_virt_rv64_mc.dtb					\
 		--kernel-file $(UEFI_CODE_IMAGE)						\
		--uefi-code-image $(UEFI_CODE_IMAGE)					\
		--uefi-vars-image $(UEFI_VARS_IMAGE)					\
		--memory-size $(MEM_SIZE_RV64)							\
		--debug-cont-sim-on-wait                                \
		buildroot_rv64/output/images/fw_jump.elf

run_qemu_virt64_mc_uefi_sd: build_rv64_efi_sd .stamp/vp_build .stamp/buildroot_rv64_build dt/qemu_virt_rv64_mc.dtb
	$(VP_NAME)/vp/build/bin/qemu_virt64-mc-vp						\
		$(QEMU_VP_ARGS)							\
		--dtb-file=dt/qemu_virt_rv64_mc.dtb					\
		--uefi-code-image $(UEFI_CODE_IMAGE)					\
		--uefi-vars-image $(UEFI_VARS_IMAGE)					\
		--virtio-blk-image $(VIRTIO_BLK_IMAGE)				\
		--virtio-blk-debug					\
		--memory-size $(MEM_SIZE_RV64)						\
		buildroot_rv64/output/images/fw_dynamic.elf
run_qemu_virt64_mc_uefi_sd_gdb: build_rv64_efi_sd .stamp/vp_build .stamp/buildroot_rv64_build dt/qemu_virt_rv64_mc.dtb
	$(VP_NAME)/vp/build/bin/qemu_virt64-mc-vp						\
		$(QEMU_VP_ARGS)							\
		--debug-mode								\
		--debug-port $(GDB_PORT)						\
		--dtb-file=dt/qemu_virt_rv64_mc.dtb					\
		--uefi-code-image $(UEFI_CODE_IMAGE)					\
		--uefi-vars-image $(UEFI_VARS_IMAGE)					\
		--virtio-blk-image $(VIRTIO_BLK_IMAGE)				\
		--debug-cont-sim-on-wait						\
		--memory-size $(MEM_SIZE_RV64)						\
		buildroot_rv64/output/images/fw_dynamic.elf

run_qemu_virt64_mc_uefi_gdb: .stamp/vp_build .stamp/buildroot_rv64_build dt/qemu_virt_rv64_mc.dtb
	$(VP_NAME)/vp/build/bin/qemu_virt64-mc-vp					\
		$(QEMU_VP_ARGS)								\
		--debug-mode								\
		--debug-port $(GDB_PORT)						\
		--dtb-file=dt/qemu_virt_rv64_mc.dtb					\
		--kernel-file $(UEFI_CODE_IMAGE)						\
		--uefi-code-image $(UEFI_CODE_IMAGE)					\
		--uefi-vars-image $(UEFI_VARS_IMAGE)					\
		--debug-cont-sim-on-wait						\
		--memory-size $(MEM_SIZE_RV64)		\
		buildroot_rv64/output/images/fw_jump.elf

connect_qemu_virt64_mc_uefi_gdb:
	$(GDB_BIN) \
		-ex "set architecture riscv:rv64" \
		-ex "target remote :$(GDB_PORT)" \
		-ex "symbol-file buildroot_rv64/output/images/fw_jump.elf" \
		-ex "source $(CURDIR)/tools/riscv_uefi_symbols.py" \
		-ex "riscv-uefi-load-symbols --log $(CURDIR)/run_uefi.log" \
		-ex "add-symbol-file $(VMLINUX_RV64) $(KERNEL_VIRT_BASE)"

connect_qemu_virt64_mc_uefi_gdb_fv:
	$(GDB_BIN) \
		-ex "set architecture riscv:rv64" \
		-ex "target remote :$(GDB_PORT)" \
		-ex "symbol-file buildroot_rv64/output/images/fw_jump.elf" \
		-ex "source $(CURDIR)/tools/riscv_uefi_symbols.py" \
		-ex "riscv-uefi-load-symbols --sec-fv-base $(UEFI_SEC_FV_BASE) --dxe-fv-base $(UEFI_DXE_FV_BASE)" \
		-ex "add-symbol-file $(VMLINUX_RV64) $(KERNEL_VIRT_BASE)"

connect_qemu_virt64_mc_uefi_sd_gdb_kernel:
	$(GDB_BIN) \
		-ex "set architecture riscv:rv64" \
		-ex "target remote :$(GDB_PORT)" \
		-ex "file $(VMLINUX_RV64)" \
		-ex "break _start_kernel" \
		-ex "break start_kernel"

connect_qemu_virt64_mc_uefi_sd_gdb_kernel_auto:
	$(GDB_BIN) \
		-ex "set pagination off" \
		-ex "set architecture riscv:rv64" \
		-ex "file $(VMLINUX_RV64)" \
		-ex "target remote :$(GDB_PORT)" \
		-ex "break _start_kernel" \
		-ex "break start_kernel" \
		-ex "break setup_arch" \
		-ex "break mm_init" \
		-ex "break rest_init" \
		-ex "continue"

run_qemu_virt64_mc_uefi_dynamic: .stamp/vp_build .stamp/buildroot_rv64_build dt/qemu_virt_rv64_mc.dtb
	$(VP_NAME)/vp/build/bin/qemu_virt64-mc-vp					\
		$(QEMU_VP_ARGS)								\
		--dtb-file=dt/qemu_virt_rv64_mc.dtb					\
		--uefi-code-image $(UEFI_CODE_IMAGE)					\
		--uefi-vars-image $(UEFI_VARS_IMAGE)					\
		--memory-size $(MEM_SIZE_RV64)							\
		buildroot_rv64/output/images/fw_dynamic.elf

build_rv64_efi_sd: .stamp/buildroot_rv64_build dt/qemu_virt_rv64_mc.dtb
	@echo " + CREATE RV64 EFI SD IMAGE: $(EFI_SD_IMAGE)"
	@test -f $(KERNEL_EFI_IMAGE_RV64) || (echo "Missing kernel EFI Image at $(KERNEL_EFI_IMAGE_RV64). Run 'make build_rv64' first." && exit 1)
	@test -f buildroot_rv64/output/images/rootfs.tar || (echo "Missing rootfs.tar. Run 'make build_rv64' first." && exit 1)
	@command -v sfdisk >/dev/null || (echo "sfdisk not found. Install util-linux." && exit 1)
	@command -v mcopy >/dev/null || (echo "mcopy not found. Install mtools." && exit 1)
	@command -v mmd >/dev/null || (echo "mmd not found. Install mtools." && exit 1)
	@command -v mformat >/dev/null || (echo "mformat not found. Install mtools." && exit 1)
	@command -v cpio >/dev/null || (echo "cpio not found. Install cpio." && exit 1)
	rm -rf $(EFI_BOOT_DIR)
	mkdir -p $(EFI_BOOT_DIR)/EFI/BOOT $(EFI_BOOT_DIR)/dtb $(EFI_BOOT_DIR)/rootfs
	cp $(KERNEL_EFI_IMAGE_RV64) $(EFI_BOOT_DIR)/EFI/BOOT/BOOTRISCV64.EFI
	cp dt/qemu_virt_rv64_mc.dtb $(EFI_BOOT_DIR)/dtb/qemu_virt_rv64_mc.dtb
	tar -xf buildroot_rv64/output/images/rootfs.tar -C $(EFI_BOOT_DIR)/rootfs
	printf 'nod /dev/console 0600 0 0 c 5 1\nnod /dev/null 0666 0 0 c 1 3\n' > $(EFI_BOOT_DIR)/initrd-devnodes.txt
	(cd $(LINUX_RV64_BUILD_DIR) && usr/gen_initramfs.sh -o $(CURDIR)/$(EFI_BOOT_DIR)/initrd.cpio -u 0 -g 0 $(CURDIR)/$(EFI_BOOT_DIR)/rootfs $(CURDIR)/$(EFI_BOOT_DIR)/initrd-devnodes.txt)
	rm -f $(EFI_BOOT_DIR)/initrd-devnodes.txt
	rm -rf $(EFI_BOOT_DIR)/rootfs
	printf '\\EFI\\BOOT\\BOOTRISCV64.EFI dtb=\\dtb\\qemu_virt_rv64_mc.dtb initrd=\\initrd.cpio rdinit=/sbin/init console=ttyS0,115200n8 earlycon=uart8250,mmio,0x10000000,115200 loglevel=7 ignore_loglevel\n' > $(EFI_BOOT_DIR)/startup.nsh
	dd if=/dev/zero of=$(EFI_SD_IMAGE) bs=1M count=512
	printf 'label: gpt\nfirst-lba: 2048\n, , U\n' | sfdisk $(EFI_SD_IMAGE)
	mformat -i $(EFI_SD_IMAGE)@@$(EFI_ESP_OFFSET) -F -v EFI ::
	mmd -i $(EFI_SD_IMAGE)@@$(EFI_ESP_OFFSET) ::/EFI ::/EFI/BOOT ::/dtb
	mcopy -i $(EFI_SD_IMAGE)@@$(EFI_ESP_OFFSET) $(EFI_BOOT_DIR)/EFI/BOOT/BOOTRISCV64.EFI ::/EFI/BOOT/BOOTRISCV64.EFI
	mcopy -i $(EFI_SD_IMAGE)@@$(EFI_ESP_OFFSET) $(EFI_BOOT_DIR)/dtb/qemu_virt_rv64_mc.dtb ::/dtb/qemu_virt_rv64_mc.dtb
	mcopy -i $(EFI_SD_IMAGE)@@$(EFI_ESP_OFFSET) $(EFI_BOOT_DIR)/initrd.cpio ::/initrd.cpio
	mcopy -i $(EFI_SD_IMAGE)@@$(EFI_ESP_OFFSET) $(EFI_BOOT_DIR)/startup.nsh ::/startup.nsh

run_rv32_mc: build_rv32
	$(VP_NAME)/vp/build/bin/linux32-vp							\
		$(VP_ARGS)												\
		--dtb-file=dt/linux-vp_rv32_mc.dtb						\
		--kernel-file buildroot_rv32/output/images/Image		\
		--mram-root-image $(MRAM_IMAGE_DIR)/mram_rv32_root.img	\
		--mram-data-image $(MRAM_IMAGE_DIR)/mram_rv32_data.img	\
		--memory-size $(MEM_SIZE_RV32)							\
		buildroot_rv32/output/images/fw_jump.elf

run_rv64_mc: build_rv64
	$(VP_NAME)/vp/build/bin/linux-vp							\
		$(VP_ARGS)												\
		--dtb-file=dt/linux-vp_rv64_mc.dtb						\
		--kernel-file buildroot_rv64/output/images/Image		\
		--mram-root-image $(MRAM_IMAGE_DIR)/mram_rv64_root.img	\
		--mram-data-image $(MRAM_IMAGE_DIR)/mram_rv64_data.img	\
		--memory-size $(MEM_SIZE_RV64)							\
		buildroot_rv64/output/images/fw_jump.elf

clean:
	- $(MAKE) clean -C $(VP_NAME)
	- $(MAKE) clean -C buildroot_rv64
	- $(MAKE) clean -C buildroot_rv32
	- rm -rf dt/*.dtb
	- rm -rf .stamp/buildroot_config
	- rm -rf .stamp/buildroot_get_sources
	- rm -rf .stamp/buildroot_rv??_build

distclean:
	- rm -rf .stamp
	- rm -rf buildroot_rv32 buildroot_rv64 buildroot_dl
	- rm -rf $(VP_NAME)
	- rm -rf dt/*.dtb
	- rm -rf dt/*.dts


## MISC/HELPERS

.stamp/init:
	@mkdir -p `dirname $@`
	@touch $@


## VP

.stamp/vp_get: .stamp/init
	@echo " + GET RISC-V VP"
	rm -rf $(VP_NAME)
	git clone $(VP_GIT) $(VP_NAME)
	( cd $(VP_NAME) && git checkout $(VP_VERSION) )
	@touch $@

.stamp/vp_build: .stamp/vp_get
	@echo " + BUILD RISC-V VP"
	# ensure release build
	RELEASE_BUILD=ON $(MAKE) vps -C $(VP_NAME) -j$(NPROCS)
	@touch $@


## BUILDROOT

.stamp/buildroot_get: .stamp/init
	@echo " + GET BUILDROOT"
	rm -rf buildroot_rv32 buildroot_rv64
	git clone $(BUILDROOT_GIT) buildroot_rv32
	( cd buildroot_rv32 && git checkout $(BUILDROOT_VERSION) )
	cp -a buildroot_rv32 buildroot_rv64
	@touch $@

.stamp/buildroot_config: .stamp/buildroot_get
	@echo " + CONFIG BUILDROOT"
	cp configs/buildroot_rv32.config buildroot_rv32/.config
	cp configs/buildroot_rv64.config buildroot_rv64/.config
	cp configs/busybox.config buildroot_rv32
	cp configs/busybox.config buildroot_rv64
	cp configs/linux_rv32.config buildroot_rv32
	cp configs/linux_rv64.config buildroot_rv64
	@touch $@

.stamp/buildroot_get_sources: .stamp/buildroot_config
	@echo " + GET BUILDROOT PACKAGE SOURCES"
	env -u LD_LIBRARY_PATH $(MAKE) -C buildroot_rv32 source
	env -u LD_LIBRARY_PATH $(MAKE) -C buildroot_rv64 source
	@touch $@

.stamp/buildroot_rv32_build: .stamp/buildroot_get_sources
	@echo " + BUILD BUILDROOT FOR RV32"
	env -u LD_LIBRARY_PATH $(MAKE) -C buildroot_rv32
	mkdir -p $(MRAM_IMAGE_DIR)
	cp buildroot_rv32/output/images/rootfs.squashfs $(MRAM_IMAGE_DIR)/mram_rv32_root.img
	@touch $@

.stamp/buildroot_rv64_build: .stamp/buildroot_get_sources
	@echo " + BUILD BUILDROOT FOR RV64"
	env -u LD_LIBRARY_PATH $(MAKE) -C buildroot_rv64
	mkdir -p $(MRAM_IMAGE_DIR)
	cp buildroot_rv64/output/images/rootfs.squashfs $(MRAM_IMAGE_DIR)/mram_rv64_root.img
	@touch $@


## DEVICETREE

dt/linux-vp_rv32_sc.dts: Makefile $(LINUX_DT_GEN)
	@echo " + CREATE VP RV32 SINGLECORE DTS: $@"
	@mkdir -p `dirname $@`
	$(LINUX_DT_GEN)							\
		--quiet								\
		--bootargs $(DT_BOOTARGS)			\
		--target linux32-sc-vp				\
		--memory-size $(MEM_SIZE_RV32)		\
		--output-file $@

dt/linux-vp_rv64_sc.dts: Makefile $(LINUX_DT_GEN)
	@echo " + CREATE VP RV64 SINGLECORE DTS: $@"
	@mkdir -p `dirname $@`
	$(LINUX_DT_GEN)							\
		--quiet								\
		--bootargs $(DT_BOOTARGS)			\
		--target linux-sc-vp				\
		--memory-size $(MEM_SIZE_RV64)		\
		--output-file $@

dt/linux-vp_rv32_mc.dts: Makefile $(LINUX_DT_GEN)
	@echo " + CREATE VP RV32 MULTICORE DTS: $@"
	@mkdir -p `dirname $@`
	$(LINUX_DT_GEN)							\
		--quiet								\
		--bootargs $(DT_BOOTARGS)			\
		--target linux32-vp					\
		--memory-size $(MEM_SIZE_RV32)		\
		--output-file $@


dt/linux-vp_rv64_mc.dts: Makefile $(LINUX_DT_GEN)
	@echo " + CREATE VP RV64 MULTICORE DTS: $@"
	@mkdir -p `dirname $@`
	$(LINUX_DT_GEN)							\
		--quiet								\
		--bootargs $(DT_BOOTARGS)			\
		--target linux-vp					\
		--memory-size $(MEM_SIZE_RV64)		\
		--output-file $@

dt/linux-vp_rv32_sc.dtb: dt/linux-vp_rv32_sc.dts .stamp/buildroot_rv32_build
	@echo " + CREATE VP RV32 SINGLECORE DTB: $@"
	buildroot_rv32/$(BR_DTC) $< -o $@

dt/linux-vp_rv64_sc.dtb: dt/linux-vp_rv64_sc.dts .stamp/buildroot_rv64_build
	@echo " + CREATE VP RV64 SINGLECORE DTB: $@"
	buildroot_rv64/$(BR_DTC) $< -o $@

dt/linux-vp_rv32_mc.dtb: dt/linux-vp_rv32_mc.dts .stamp/buildroot_rv32_build
	@echo " + CREATE VP RV32 MULTICORE DTB: $@"
	buildroot_rv32/$(BR_DTC) $< -o $@

dt/linux-vp_rv64_mc.dtb: dt/linux-vp_rv64_mc.dts .stamp/buildroot_rv64_build
	@echo " + CREATE VP RV64 MULTICORE DTB: $@"
	buildroot_rv64/$(BR_DTC) $< -o $@

dt/qemu_virt_rv64_mc.dts: Makefile $(QEMU_VIRT_DT_GEN)
	@echo " + CREATE QEMU VIRT RV64 MULTICORE DTS: $@"
	@mkdir -p `dirname $@`
	$(QEMU_VIRT_DT_GEN)					\
		--target qemu_virt64-mc-vp			\
		--memory-size $(MEM_SIZE_RV64)			\
		--output-file $@

dt/qemu_virt_rv64_mc.dtb: dt/qemu_virt_rv64_mc.dts .stamp/buildroot_rv64_build
	@echo " + CREATE QEMU VIRT RV64 MULTICORE DTB: $@"
	buildroot_rv64/$(BR_DTC) $< -o $@
