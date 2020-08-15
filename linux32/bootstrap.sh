#!/bin/sh
export PATH=/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/sbin:$HOME/.local/bin

set -x
set -e

# ENV
BUILDENV=`dirname $0`
LIN32=$BUILDENV/rootfs

debootstrap --arch i386 woody $LIN32 http://archive.debian.org/debian
mkdir -p $LIN32/usr/src

mkdir -p $LIN32/etc/ssl/certs
cp -L /etc/ssl/certs/*.0 $LIN32/etc/ssl/certs/
cp /etc/ssl/certs/ca-* $LIN32/etc/ssl/certs/
cat /etc/resolv.conf >$LIN32/etc/resolv.conf

cat > $LIN32/wrap.c <<EOF
#define _GNU_SOURCE
#include <sys/utsname.h>
#include <string.h>

static const
struct utsname Build_utsname = {
  .sysname = "Linux",
  .nodename = "Build",
  .release = "2.4.0",
  .version = "2.4.0",
  .machine = "i386",
  .domainname = "Build",
} ;

int uname(struct utsname *buf) {
    memcpy(buf, &Build_utsname, sizeof(struct utsname));
    return 0;
}
EOF

cat > $LIN32/gccwrap <<EOF
#!/bin/bash
declare -a filter=( "\$CFLAGS_FILTER" )
declare -a outargs=()

for arg; do
  found=false
  for filtered in \${filter[@]}; do
     if [ "\$filtered" == "\$arg" ]; then
        found=true
        break
     fi
  done

  if [ "\$found" = "false" ]; then
        outargs[\${#outargs[@]}]="\$arg"
  fi

done

exec gcc "\${outargs[@]}"
EOF

chmod +x $LIN32/gccwrap

cat <<__CMDS__ > $LIN32/deploy.sh

export LC_ALL=C
export TERM=
export DEBIAN_FRONTEND=noninteractive

set -e

/bin/sh -c "apt-get --force-yes -y install gcc-3.0 g++-3.0 make libc-dev \
 perl m4 gettext libexpat1-dev flex bison file libstdc++2.10-dev \
 libtool patch xutils xlibs-dev zip unzip attr-dev locales < /dev/null"

cd /
gcc -fPIC -o /wrap.so -shared /wrap.c
echo /wrap.so >/etc/ld.so.preload

mkdir /opt/static

ln -sf /usr/lib/gcc-lib/i386-linux/3.0.4/libgcc.a /opt/static/
ln -sf /usr/lib/gcc-lib/i386-linux/3.0.4/libstdc++.a /opt/static/
ln -sf /usr/lib/gcc-lib/i386-linux/3.0.4/libsupc++.a /opt/static/

ln -sf /usr/lib/libffi.a /opt/static/
ln -sf /usr/lib/libutil.a /opt/static/
ln -sf /usr/bin/gcc-3.0 /usr/bin/gcc
ln -sf /usr/bin/g++-3.0 /usr/bin/g++
ln -sf /usr/bin/gcc-3.0 /usr/bin/cc
ln -sf /usr/lib/gcc-lib/i386-linux/3.0.4/cc1plus /usr/bin/cc1plus
ln -sf /usr/X11R6/lib/libX11.so /usr/lib/
ln -sf /usr/X11R6/lib/libXss.a /usr/lib/

apt-get clean

localedef -i en_US -f UTF-8 en_US.UTF-8

rm -f /etc/resolv.conf
rm -f /deploy.sh
rm -f /wrap.c

ldconfig
__CMDS__

mkdir -p $LIN32/proc
mkdir -p $LIN32/dev
mount -t proc proc $LIN32/proc
mount -t devtmpfs devtmpfs $LIN32/dev

chroot $LIN32 /bin/bash -x /deploy.sh

umount $LIN32/proc
umount $LIN32/dev

tar -C $LIN32 -c . | ${DOCKER_COMMAND:-docker} import - linux32
