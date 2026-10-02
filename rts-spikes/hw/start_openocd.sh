#!/bin/sh
# Start the OpenOCD that ships with Microchip SoftConsole against an Icicle Kit's embedded FlashPro6.
# The distribution's own OpenOCD (0.12) has no microsemi-flashpro interface.
# Override SC with another SoftConsole install; telnet :4444, gdb :3333.
SC=${SC:-/opt/Microchip_SoftConsole-v2022.2}
export LD_LIBRARY_PATH=$SC/openocd/bin
exec "$SC/openocd/bin/openocd" -s "$SC/openocd/share/openocd/scripts" \
     --command "set DEVICE MPFS" --file board/microsemi-riscv.cfg "$@"
