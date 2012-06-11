#!/bin/bash

DISTRO="gentoo"

# Static defines
WGET="wget --timeout=8 --read-timeout=15 -c -t10 -nd"

# Defaults only
if [ `uname -m` == "x86_64" ]; then
    ARCH=${ARCH:-amd64}
    SUBARCH=${SUBARCH:-i686}
else
    ARCH=${ARCH:-x86}
    SUBARCH=${SUBARCH:-$(uname -m)}
fi

INITTAB="/etc/inittab"
FSTAB="/etc/fstab"

CONFFILE="./lxc-conf"

CACHE="/var/cache/lxc/${DISTRO}"

download_new_stage3(){

	    RES=$?
	    if [ "${RES}" != "0" ]; then
		    echo "Cache repository is busy."
		    break
	    fi

	    # check the mini distro was not already downloaded
        TEMPLATE="${CACHE}/${ARCH}_${SUBARCH}_rootfs"
	    echo -n "Checking for pre-existing cache in ${TEMPLATE}... "
	    if [ ! -e "${TEMPLATE}" ]; then

		    echo "not found."

            # make unique variables for x86 and amd64 since stage3 url are different
            echo "Generating strings to run... "
            if [ $ARCH == 'x86' ]; then
                STAGE3SED="s/.*stage3-${SUBARCH}-\(........\)\.tar\.bz2.*/\1/p"
                STAGE3URL="http://distfiles.gentoo.org/releases/${ARCH}/autobuilds/current-stage3/stage3-${SUBARCH}"
            elif [ $ARCH == 'arm' ]; then
                STAGE3SED="s/.*stage3-${SUBARCH}-\(........\)\.tar\.bz2.*/\1/p"
                STAGE3URL="http://distfiles.gentoo.org/releases/${ARCH}/autobuilds/current-stage3-${SUBARCH}/stage3-${SUBARCH}"
            else
                STAGE3SED="s/.*stage3-${ARCH}-\(........\)\.tar\.bz2.*/\1/p"
                STAGE3URL="http://distfiles.gentoo.org/releases/${ARCH}/autobuilds/current-stage3/stage3-${ARCH}"
            fi

		    echo "Determining latest ${DISTRO}:${ARCH}:${SUBARCH} stage3 archive... "
		    mkdir -p ${CACHE} 1>/dev/null 2>/dev/null
            if [ $ARCH != 'arm' ]; then
	    	    LATEST_STAGE3_TIMESTAMP=`${WGET} -q -O - http://distfiles.gentoo.org/releases/${ARCH}/autobuilds/current-stage3/ |sed -n "${STAGE3SED}" |sort -r |uniq |head -n 1`
            else
	    	    LATEST_STAGE3_TIMESTAMP=`${WGET} -q -O - http://distfiles.gentoo.org/releases/${ARCH}/autobuilds/current-stage3-${SUBARCH}/ |sed -n "${STAGE3SED}" |sort -r |uniq |head -n 1`
            fi
		    echo "LATEST_STAGE3_TIMESTAMP= ${LATEST_STAGE3_TIMESTAMP}"

		    echo -n "Downloading (~120MB), please wait... "
            echo "${STAGE3URL}-${LATEST_STAGE3_TIMESTAMP}.tar.bz2"
		    ${WGET} -O ${CACHE}/stage3-${ARCH}-${LATEST_STAGE3_TIMESTAMP}.tar.bz2 "${STAGE3URL}-${LATEST_STAGE3_TIMESTAMP}.tar.bz2" 1>/dev/null 2>/dev/null

	    	RESULT=$?
	    	if [ "${RESULT}" != "0" ]; then
		        echo "failed!"
		        exit 1
		    fi
		    echo "complete."

		    # make sure we are operating on a clear rootfs cache
		    rm -Rf "${TEMPLATE}" #1>/dev/null 2>/dev/null
		    mkdir -p "${TEMPLATE}" #1>/dev/null 2>/dev/null

		    echo -n "Extracting stage3 archive... "
		    tar -jxf ${CACHE}/stage3-${ARCH}-${LATEST_STAGE3_TIMESTAMP}.tar.bz2 -C "${TEMPLATE}" 1>/dev/null 2>/dev/null
		    echo "done."
	    else
		    echo "found."
	    fi

        # make a local copy of the mini
	    echo -n "Copying filesystem... "
	    cp -a "${TEMPLATE}" ${ROOTFS} && echo "done." || exit

}

write_lxc_configuration (){

    echo -n " - writing LXC guest configuration... "
cat <<EOF > ${CONFFILE}
# set arch
lxc.arch = ${SUBARCH}

# set the hostname
# lxc.utsname = ${NAME}

# network interface
lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = br0
# For now, lxc can't set default gateway,
# so whole network config is set directly inside guest
# lxc.network.ipv4 = 0.0.0.0

# root filesystem location
lxc.rootfs = `readlink -f ${ROOTFS}`

# console access
lxc.tty = 1

# this part is based on 'linux capabilities', see: man 7 capabilities
#  eg: you may also wish to drop 'cap_net_raw' (though it breaks ping)
lxc.cap.drop = sys_module mknod mac_override sys_boot

EOF
 echo "done."

}

mount_required_dir(){
    echo -n "mount required directories... "
    mkdir -p ${ROOTFS}/usr/portage
    mount --bind /usr/portage ${ROOTFS}/usr/portage
    mount -t proc proc ${ROOTFS}/proc
    mount -o bind /dev ${ROOTFS}/dev
    mount --bind /sys ${ROOTFS}/sys
    echo "done."
}

write_distro_fstab() {
cat <<EOF > ${ROOTFS}/${FSTAB}
# required to prevent boot-time error display
none / none defaults 0 0
tmpfs  /dev/shm   tmpfs  defaults  0 0
EOF
}

# custom network configuration
write_distro_network() {
    # /etc/resolv.conf
    if [ ! -e ${ROOTFS}/etc/resolv.conf ]; then
        touch ${ROOTFS}/etc/resolv.conf
    fi
    grep -i 'search ' /etc/resolv.conf > ${ROOTFS}/etc/resolv.conf
    grep -i 'nameserver ' /etc/resolv.conf >> ${ROOTFS}/etc/resolv.conf

    # gentoo network configuration
cat <<EOF > ${ROOTFS}/etc/conf.d/net
config_eth0="${IPV4}"
routes_eth0="default via ${GATEWAY}"
EOF
    if [ -e ${ROOTFS}/etc/init.d/net.eth0 ]; then
        rm -fr ${ROOTFS}/etc/init.d/net.eth0
        rm -fr ${ROOTFS}/etc/runlevels/default/net.eth0
    fi
    (cd ${ROOTFS}/etc/init.d ; ln -s net.lo net.eth0)
    ln -s /etc/init.d/net.eth0 ${ROOTFS}/etc/runlevels/default/net.eth0
}

# fix init system
write_distro_init_fixes() {
	#thanks openrc, now it is simple :)
	sed 's/^#rc_sys=""/rc_sys="lxc"/g' -i ${ROOTFS}/etc/rc.conf
}

# custom inittab
write_distro_inittab() {
    sed -i 's/^c[1-9]/#&/' ${ROOTFS}/${INITTAB} # disable getty
    echo "# Lxc main console" >> ${ROOTFS}/${INITTAB}
    echo "1:12345:respawn:/sbin/agetty -a root 38400 console linux" >> ${ROOTFS}/${INITTAB}
    # we also blank out /etc/issue here in order to prevent delays spawning login
    # caused by attempts to determine domainname on disconnected containers
    rm ${ROOTFS}/etc/issue && touch ${ROOTFS}/etc/issue
    # we also disable the /etc/init.d/termencoding script which can cause errors
    sed -i 's/^(\s*keyword .*)$/$1 -lxc/' ${ROOTFS}/etc/init.d/termencoding
    # quiet login
    #touch ${ROOTFS}/root/.hushlogin
}

create (){

    echo "create the lxc container"

    if [ -z "${NAME}" ]; then
	    echo "Cannot get lxc name"
        exit 1
    fi

    if [ -z "${ROOTFS}" ]; then
	    echo "Cannot get the rootfs of gentoo lxc"
        exit 1
    fi

    if [ $ARCH == 'arm' ]; then
        echo -n "What is the subarch of ${ARCH}? "
        read _SUBARCH_
        SUBARCH=${_SUBARCH_}_hardfp
    fi

    # check if the rootfs does already exist
    if [ ! -e "${ROOTFS}" ]; then
	    mkdir -p /var/lock/subsys/
	(
    	flock -n -x 200
        download_new_stage3
	) 200> "/var/lock/subsys/lxc"
    fi

    exit 1

    write_lxc_configuration

    write_distro_inittab

    mount_required_dir

    write_distro_fstab

    write_distro_network

    write_distro_init_fixes

    /usr/sbin/lxc-create -n ${NAME} -f ${CONFFILE} 1>/dev/null 2>/dev/null
    RES=$?

    if [ "${RES}" != "0" ]; then
        echo "Failed to create '${NAME}'"
        exit 1
    fi

    echo "All done!"
 
}

help (){
    echo "help"
}

destroy() {

    /usr/sbin/lxc-stop -n ${NAME}
    /usr/sbin/lxc-destroy -n ${NAME}
    echo "destroy $NAME"

    if [ -e ${ROOTFS}/etc/init.d/net.eth0 ]; then
        rm -fr ${ROOTFS}/etc/init.d/net.eth0
        rm -fr ${ROOTFS}/etc/runlevels/default/net.eth0
    fi

    umount ${ROOTFS}/usr/portage
    umount ${ROOTFS}/proc
    umount ${ROOTFS}/dev
    umount ${ROOTFS}/sys
    rm -f ${CONFFILE}

    echo -n "Shall I remove the rootfs and configfile [y/n] ? "
    read
    if [ "${REPLY}" = "y" ]; then
	rm -rf ${ROOTFS}
    fi

    return 0
}

start() {

    echo "start the ${NAME} lxc containter..."
    /usr/sbin/lxc-start -n ${NAME} -f ${CONFFILE}

}

# Note: assuming uid==0 is root -- might break with userns??
if [ "$(id -u)" != "0" ]; then
    echo "This script should be run as 'root'"
    exit 1
fi

CACHE="/var/cache/lxc/${DISTRO}"

OPTIND=2
while getopts "i:g:n:a:r:c" opt
do
    case $opt in
        i) IPV4=$OPTARG ;;
        g) GATEWAY=$OPTARG ;;
        n) NAME=$OPTARG ;;
        a) ARCH=$OPTARG ;;
        r) ROOTFS=$OPTARG ;;
        c) ;;
        \?) ;;
    esac
done

case "$1" in
    create)
        create;;
    start)
        start;;
    destroy)
	    destroy;;
    help)
	help;;
    *)
        help	
        exit 1;;
esac

