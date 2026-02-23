#!/bin/sh
if [ -d www ]; then
    rm -r www
fi

mkdir www

cp sys/packages/netboot/boot.lua www/netboot.lua
python3 -m initrd www/initrd.lua
