cross_container_support
=======================

Test Env
============
host:
1. i686 gentoo os
2. lxc 0.8.0-rc2
3. qemu-user 1.1.0-r1
4. crossdev 20120531
5. cross compiler:
    5.1 type: armv7a-hardfloat-linux-gnueabi
    5.2 gcc 4.6.3
    5.3 binutil 2.22
    5.4 glibc 2.15-r2
    5.5 linux-header 3.5

guest:
stage3-armv7a_hardfp-20120730.tar.bz2

Use(for armv7a)
===========

1. Install a cross compiler
USE="-fortran nossp" crossdev -t armv7a-hardfloat-linux-gnueabi

2. Create a gentoo chroot
lxc.sh create -i ip_address/netmask -g gateway -n chroot_name -r rootfs -a arm
subarch is "armv7a"

3. Start the gentoo chroot
lxc.sh start -n chroot_name

4. Switch to native compiler
cd /root
source switch.sh native
do-compile

5. Back to emu env
source switch.sh emu
