#!/bin/sh

set -x
set -e

DIST=${DIST:-etch}
ARCH=${ARCH:-amd64}

SELF=`readlink -f "$0"`
ROOTFS=`dirname "$SELF"`/rootfs-${DIST}-${ARCH}

case ${ARCH} in
    amd64) UNAME_ARCH="x86_64";;
    i386) UNAME_ARCH="i486";;
    armhf) UNAME_ARCH="armv7l";;
    *) UNAME_ARCH=${ARCH};;
esac

debootstrap --no-check-gpg --arch ${ARCH} ${DIST} ${ROOTFS} \
	    http://archive.debian.org/debian

mkdir -p ${ROOTFS}/etc/ssl/certs
for file in /etc/ssl/certs/*.0; do
    cat $file >${ROOTFS}/etc/ssl/certs/`basename "$file"`
done

cp /etc/ssl/certs/ca-* ${ROOTFS}/etc/ssl/certs/
cat /etc/resolv.conf >${ROOTFS}/etc/resolv.conf

cat > ${ROOTFS}/wrap.c <<EOF
#define _GNU_SOURCE
#include <sys/utsname.h>
#include <string.h>

static const
struct utsname Build_utsname = {
  .sysname = "Linux",
  .nodename = "Build",
  .release = "2.4.0",
  .version = "2.4.0",
  .machine = "${UNAME_ARCH}",
  .domainname = "Build",
};

int uname(struct utsname *buf) {
    memcpy(buf, &Build_utsname, sizeof(struct utsname));
    return 0;
}
EOF

cat > ${ROOTFS}/gccwrap <<EOF
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

chmod +x ${ROOTFS}/gccwrap

cat <<__CMDS__ > ${ROOTFS}/deploy.sh

set -x

export LC_ALL=C
export TERM=
export DEBIAN_FRONTEND=noninteractive

set -e

/bin/sh -c "apt-get --force-yes -y install build-essential make libc-dev locales \
 perl m4 gettext libexpat1-dev flex bison file libtool patch xutils \
 libx11-dev libxss-dev zip unzip libattr1-dev libasound2-dev < /dev/null"

cd /
gcc -fPIC -o /wrap.so -shared /wrap.c
echo /wrap.so >/etc/ld.so.preload

mkdir /opt/static

find /usr -noleaf \
     \( -name libgcc.a \
        -or -name libssp\*.a \) \
     \! -path "*/gcc/*32/*" \
     \! -path "*/gcc/*64/*" \
     -exec ln -vsf '{}' /opt/static/ ';'

localedef -i en_US -f UTF-8 en_US.UTF-8

apt-get clean
ldconfig

rm -f /wrap.c
rm -f /deploy.sh

__CMDS__

mkdir -p ${ROOTFS}/proc
mkdir -p ${ROOTFS}/dev
mount -t proc proc ${ROOTFS}/proc
mount -t devtmpfs devtmpfs ${ROOTFS}/dev

chroot ${ROOTFS} /bin/bash -x /deploy.sh

umount ${ROOTFS}/proc
umount ${ROOTFS}/dev

chown root:root -R ${ROOTFS}

tar -C ${ROOTFS} -c . | \
    ${DOCKER_COMMAND:-docker} import \
			      --change ENV=DIST=${DIST} \
			      --change ENV=ARCH=${ARCH} \
			      --change ENV=UNAME_ARCH=${UNAME_ARCH} \
			      - linux-${ARCH}:${DIST}
