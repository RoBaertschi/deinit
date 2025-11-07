#!/usr/bin/env sh

if test "$1" != "no"; then
odin build . -out:./buildroot-config/rootfs/sbin/init
./make.sh -C ./buildroot-2025.08/
fi

pushd ./buildroot-2025.08/output/images/
qemu-system-x86_64 -kernel bzImage -drive file=rootfs.ext2,format=raw -append "root=/dev/sda rw loglevel=15" --enable-kvm -cpu host -m 1G -serial stdio
popd
