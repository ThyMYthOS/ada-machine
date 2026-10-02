#include "riscv_def.h"

        /**************/
        /* _start */
        /**************/
        /*
         * An image on this SoC arrives two ways (XIP from eNVM, or already
         * placed in RAM by the system controller/JTAG) and starts in two
         * roles (primary -- first thing running, must park the harts it
         * does not own; secondary -- a supervisor already placed and
         * released us, must touch no other hart). The two axes are
         * orthogonal (RTS-PRODUCTION.md A6):
         *
         *              | primary                | secondary
         *   XIP eNVM   | copy .data, clear .bss, | copy .data, clear .bss,
         *              | park foreign harts      | touch no other hart
         *   RAM-resid. | clear .bss,             | clear .bss only
         *              | park foreign harts      |
         *
         * Axis 1 (boot medium) needs no code-path variant at all: every
         * placement script (rts_support_mpfs/ld/place-*.ld) emits
         * __data_load/__data_start/__data_end unconditionally, so copying
         * only when __data_load /= __data_start serves a RAM-resident
         * image for free (the loop runs zero iterations because the
         * linker already made the two addresses equal).
         *
         * Axis 2 (boot role) is MPFS_BOOT_ROLE_PRIMARY, a -D define fed by
         * the leaf's Boot_Role configuration variable via
         * target_options.gpr's ASMFLAGS (CONTRACT.md §3.6) -- this file
         * runs through the C preprocessor as "Asm_Cpp".
         */

        .section .start
        .globl _start
        .type _start,@function

_start:
.option push
.option norelax
        la gp, __global_pointer$
.option pop
        la sp, __stack_end

        /* Disable interrupts before anything can park: wfi wakes on any
         * pending interrupt enabled in mie even with mstatus.MIE clear,
         * and a hart handed over from an earlier stage may still have a
         * stale mie, a set MIE and an old mtvec. The PLIC and mtimecmp
         * power up random (RTS-PRODUCTION.md A5).
         */
        li      t0, MSTATUS_MIE
        csrc    mstatus, t0
        csrw    mie, zero

#if MPFS_BOOT_ROLE_PRIMARY
        /* Primary: this hart may be any hart the reset ROM (or, on real
         * hardware, a multi-hart HSS release) sends to this same entry
         * point -- QEMU's reset ROM does so unconditionally, with no
         * hart-id gate of its own (QEMU.md). So the gate tested here must
         * be a property of the image's OWN Harts_Mask, not a literal hart
         * id: test bit `mhartid` of the mask, correct unmodified for a
         * single E51 (mask 1), a single U54 (mask 2, 4, 8 or 16), or a
         * genuine multi-hart mask.
         *
         * A hart whose bit is clear parks in `infinite_loop` below. That
         * loop is structurally ready for a release protocol (CLINT MSIP +
         * WFI, with only mie.MSIE enabled) but does not implement one --
         * release is D2/SMP work (RTS-PRODUCTION.md D2), out of scope here.
         */
        csrr t1, mhartid
        li   t0, 1
        sll  t0, t0, t1        /* t0 = 1 << mhartid */
        li   t2, MPFS_HARTS_MASK
        and  t0, t0, t2
        beqz t0, infinite_loop
#endif

        /* Copy .data from its load address to its run address, if they
         * differ (XIP from eNVM: LMA in envm, VMA in l2lim -- see
         * place-envm.ld). A RAM-resident image has __data_load ==
         * __data_start, so this runs zero iterations -- the linker
         * answers axis 1, this file does not need to ask it.
         */
        la a0, __data_load
        la a1, __data_start
        la a2, __data_end
        beq a0, a1, 2f
1:
        bgeu a1, a2, 2f
        lw t0, (a0)
        sw t0, (a1)
        addi a0, a0, 4
        addi a1, a1, 4
        j 1b
2:

        /* Clear bss section */
        la a0, __bss_start
        la a1, __bss_end
        bgeu a0, a1, 4f
3:
        sw zero, (a0)
        addi a0, a0, 4
        bltu a0, a1, 3b
4:

#ifndef __riscv_float_abi_soft
        /* Enable the FPU */
        li      t0, MSTATUS_FS
        csrs    mstatus, t0
#endif

        call main
        call __gnat_exit

infinite_loop:
        wfi
        j infinite_loop

        .globl __gnat_exit
        .type __gnat_exit,@function
__gnat_exit:

#if MPFS_BOOT_ROLE_PRIMARY
        /* MSS_RESET_CR resets every hart, so only an image that owns the
         * whole MSS may do it; a secondary parks and leaves the rest
         * (and its supervisor) running.
         */
        li t0, 0x20002018
        li t1, 0xDEAD
        sw t1, (t0)
#endif

        j infinite_loop

        /* Weak alias _exit to __gnat_exit */
        .weak      _exit
        .set _exit,__gnat_exit
