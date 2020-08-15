#!/bin/sh

set -x
set -e

SELF=`readlink -f "$0"`
SELFDIR=`dirname "$SELF"`
ARCH=`uname -m`
LINARM32=$SELFDIR/rootfs

for interpreter in "$SELFDIR/qemu/qemu-arm-static.$ARCH" /usr/bin/qemu-arm /usr/bin/qemu-arm-static; do
    if [ -f $interpreter ]; then
	INTERPRETER_FILE=$interpreter
	break
    fi
done

if [ -z "${INTERPRETER_FILE}" ]; then
    echo "qemu-arm not found at host system"
    exit 1
fi

[ ! -d /proc/sys/fs/binfmt_misc ] && mount /proc/sys/fs/binfmt_misc -t binfmt_misc 

if [ ! -f /proc/sys/fs/binfmt_misc/qemu-arm ]; then
    echo ':arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/qemu-arm:' > /proc/sys/fs/binfmt_misc/register 
    INTERPRETER=/qemu-arm
else
    INTERPRETER=$(awk '/interpreter/{print $2}' /proc/sys/fs/binfmt_misc/qemu-arm)
fi

INTERPRETER_ROOTFS=${LINARM32}${INTERPRETER}
INTERPRETER_DIR=$(dirname ${INTERPRETER_ROOTFS})

if [ ! -f ${INTERPRETER_ROOTFS} ]; then
    mkdir -p ${INTERPRETER_DIR}
    cp -vf ${INTERPRETER_FILE} ${INTERPRETER_ROOTFS}
    if [ ! -f $LINARM32/usr/bin/qemu-arm-static ]; then
	ln -sf ${INTERPRETER} $LINARM32/usr/bin/qemu-arm-static
    fi
fi

debootstrap --no-check-gpg --arch armhf wheezy $LINARM32 http://archive.debian.org/debian

mkdir -p $LINARM32/etc/ssl/certs
for file in /etc/ssl/certs/*.0; do
    cat $file >$LINARM32/etc/ssl/certs/`basename "$file"`
done

cp /etc/ssl/certs/ca-* $LINARM32/etc/ssl/certs/
cat /etc/resolv.conf >$LINARM32/etc/resolv.conf

cat > $LINARM32/wrap.c <<EOF
#define _GNU_SOURCE
#include <sys/utsname.h>
#include <string.h>

static const
struct utsname Build_utsname = {
  .sysname = "Linux",
  .nodename = "Build",
  .release = "2.4.0",
  .version = "2.4.0",
  .machine = "armv7l",
  .domainname = "Build",
};

int uname(struct utsname *buf) {
    memcpy(buf, &Build_utsname, sizeof(struct utsname));
    return 0;
}
EOF

cat > $LINARM32/gccwrap <<EOF
#!/bin/bash
declare -a filter=( "\$CFLAGS_FILTER" )
declare -a badargs=( "\$CFLAGS_ABORT" )
declare -a outargs=()

for arg; do
  found=false
  for filtered in \${filter[@]}; do
     if [ "\$filtered" == "\$arg" ]; then
        found=true
        break
     fi
  done

  for bad in \${badargs[@]}; do
     if [ "\$bad" == "\$arg" ]; then
        echo "Unsupported argument found: \$bad"
        exit 1
     fi
  done

  if [ "\$found" = "false" ]; then
        outargs[\${#outargs[@]}]="\$arg"
  fi

done

exec gcc "\${outargs[@]}"
EOF

chmod +x $LINARM32/gccwrap

cat <<__CMDS__ > $LINARM32/deploy.sh

set -x

export LC_ALL=C
export TERM=
export DEBIAN_FRONTEND=noninteractive

/bin/sh -c "apt-get --force-yes -y install build-essential make libc-dev \
 perl m4 gettext libexpat1-dev flex bison file libtool patch xutils locales \
 libx11-dev libxss-dev zip unzip libattr1-dev libasound2-dev libffi-dev \
 cmake < /dev/null"

cd /
gcc -fPIC -o /wrap.so -shared /wrap.c
echo /wrap.so >/etc/ld.so.preload

mkdir /opt/static
ln -sf /usr/lib/gcc/arm-linux-gnueabihf/4.6/libgcc.a /opt/static
ln -sf /usr/lib/gcc/arm-linux-gnueabihf/4.6/libssp.a /opt/static
ln -sf /usr/lib/gcc/arm-linux-gnueabihf/4.6/libssp_nonshared.a /opt/static
ln -sf /usr/lib/libffi.a /opt/static/

rm -f /wrap.c
rm -f /deploy.sh

localedef -i en_US -f UTF-8 en_US.UTF-8

apt-get clean
ldconfig

__CMDS__

mkdir -p $LINARM32/proc
mkdir -p $LINARM32/dev
mount -t proc proc $LINARM32/proc
mount -t devtmpfs devtmpfs $LINARM32/dev

chroot $LINARM32 /bin/bash -x /deploy.sh

umount $LINARM32/proc
umount $LINARM32/dev

tar -C $LINARM32 -c . | docker import - linux-armhf
