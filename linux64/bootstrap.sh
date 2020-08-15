#!/bin/sh

set -x
set -e

SELF=`readlink -f "$0"`
LIN64=`dirname "$SELF"`/rootfs
debootstrap --no-check-gpg --arch amd64 etch $LIN64 http://archive.debian.org/debian

mkdir -p $LIN64/etc/ssl/certs
for file in /etc/ssl/certs/*.0; do
    cat $file >$LIN64/etc/ssl/certs/`basename "$file"`
done

cp /etc/ssl/certs/ca-* $LIN64/etc/ssl/certs/
cat /etc/resolv.conf >$LIN64/etc/resolv.conf

cat > $LIN64/wrap.c <<EOF
#define _GNU_SOURCE
#include <sys/utsname.h>
#include <string.h>

static const
struct utsname Build_utsname = {
  .sysname = "Linux",
  .nodename = "Build",
  .release = "2.4.0",
  .version = "2.4.0",
  .machine = "x86_64",
  .domainname = "Build",
};

int uname(struct utsname *buf) {
    memcpy(buf, &Build_utsname, sizeof(struct utsname));
    return 0;
}
EOF

cat > $LIN64/gccwrap <<EOF
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

chmod +x $LIN64/gccwrap

cat <<__CMDS__ > $LIN64/deploy.sh

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

ln -sf /usr/lib/gcc/x86_64-linux-gnu/4.1.2/libgcc.a /opt/static
ln -sf /usr/lib/gcc/x86_64-linux-gnu/4.1.2/libssp.a /opt/static
ln -sf /usr/lib/gcc/x86_64-linux-gnu/4.1.2/libssp_nonshared.a /opt/static
ln -sf /usr/lib/libffi.a /opt/static/

localedef -i en_US -f UTF-8 en_US.UTF-8

rm -f /wrap.c
rm -f /deploy.sh
apt-get clean
ldconfig

__CMDS__

mkdir -p $LIN64/proc
mkdir -p $LIN64/dev
mount -t proc proc $LIN64/proc
mount -t devtmpfs devtmpfs $LIN64/dev

chroot $LIN64 /bin/bash -x /deploy.sh

umount $LIN64/proc
umount $LIN64/dev

tar -C $LIN64 -c . | ${DOCKER_COMMAND:-docker} import - linux64
