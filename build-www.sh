#!/bin/sh
if [ -d www ]; then
    rm -r www
fi

mkdir www

cp sys/packages/netboot/boot.lua www/netboot.lua
cd initrd-ng
cargo run --release -- build --sysroot ../sys --output ../www/initrd.lua
