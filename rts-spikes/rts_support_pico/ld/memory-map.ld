/****************************************************************************
 *                                                                          *
 *                         GNAT COMPILER COMPONENTS                         *
 *                                                                          *
 *                                  A R M                                   *
 *                                                                          *
 *                            Linker Script File                            *
 *                                                                          *
 *      Copyright (C) 1999-2002 Universidad Politecnica de Madrid           *
 *             Copyright (C) 2003-2006 The European Space Agency            *
 *                   Copyright (C) 2003-2021 AdaCore                        *
 *                                                                          *
 * GNAT is free software;  you can  redistribute it  and/or modify it under *
 * terms of the  GNU General Public License as published  by the Free Soft- *
 * ware  Foundation;  either version 2,  or (at your option) any later ver- *
 * sion.  GNAT is distributed in the hope that it will be useful, but WITH- *
 * OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY *
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License *
 * for  more details.  You should have  received  a copy of the GNU General *
 * Public License  distributed with GNAT;  see file COPYING.  If not, write *
 * to  the  Free Software Foundation,  51  Franklin  Street,  Fifth  Floor, *
 * Boston, MA 02110-1301, USA.                                              *
 *                                                                          *
 * As a  special  exception,  if you  link  this file  with other  files to *
 * produce an executable,  this file does not by itself cause the resulting *
 * executable to be covered by the GNU General Public License. This except- *
 * ion does not  however invalidate  any other reasons  why the  executable *
 * file might be covered by the  GNU Public License.                        *
 *                                                                          *
 * GNARL was developed by the GNARL team at Florida State University.       *
 * Extensive contributions were provided by Ada Core Technologies, Inc.     *
 * The  executive  was developed  by the  Real-Time  Systems  Group  at the *
 * Technical University of Madrid.                                          *
 *                                                                          *
 ****************************************************************************/

/*
 * ---------------------------------------------------------------------------
 * MODIFIED FROM THE VENDOR COPY: flash LENGTH is a symbol, not a constant.
 *
 * RTS.md 5.3 / A.25: a --defsym carries a NUMBER, selection carries
 * STRUCTURE. The published embedded_rp2040 crate selects one of four
 * committed directories -- ld/flash-{2,4,8,16}/memory-map.ld, 46 lines each,
 * differing in exactly ONE line -- by concatenating a flash size into a -L
 * path. One symbol replaces all four, and reaches sizes no enumeration of
 * directories could: --defsym accepts ld's own K/M suffixes, so a
 * non-power-of-two part is just another value.
 *
 * `sram` stays a literal deliberately. The rule is "symbol for what VARIES",
 * not "symbol for every number": external QSPI flash is a board choice
 * (2/4/8/16 MB parts all ship on RP2040 boards), while on-chip SRAM is a
 * property of the die and cannot be configured. If the Device axis ever gains
 * a second populated value it becomes a per-device literal in a per-device
 * overlay -- still structure, still not a symbol.
 *
 * The symbol is supplied by the leaf from Flash_Size_KB
 * (light_tasking_pico/runtime_build.gpr; CONTRACT.md 4 pins the name), and it
 * is enforced rather than merely substituted: the ASSERT below fails the link
 * if the image does not fit, and LENGTH(flash) is what an over-large .text
 * overflows.
 * ---------------------------------------------------------------------------
 */

MEMORY
{
  flash  (rx) : ORIGIN = 0x10000000, LENGTH = PICO_FLASH_LENGTH
  sram  (rwx) : ORIGIN = 0x20000000, LENGTH = 256k
}

/*  The smallest part the RP2040 boot ROM is used with. Catches a --defsym
 *  typo (or a missing switch defaulting to 0) at link time instead of
 *  producing an image that overflows on the first byte past the region.  */
ASSERT (LENGTH (flash) >= 2M, "PICO_FLASH_LENGTH is smaller than any shipped Pico flash part")

REGION_ALIAS("sram_tx", sram)
REGION_ALIAS("sram_ro", sram)
REGION_ALIAS("sram_bs", sram)
REGION_ALIAS("sram_da", sram)
