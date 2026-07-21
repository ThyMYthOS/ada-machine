--  STM32G474 I2C1 -- base 0x4000_5400 (APB1PERIPH_BASE + 0x5400, confirmed
--  against the CMSIS device header). This is the "I2C v2" IP shared with
--  F0/F3/F7/G0/L0/L4/L5/H7 -- ADDR/DIR/TXIS/RXNE/NBYTES-style, not the
--  legacy F1/F4/L1 block spike 4's target-board pick deliberately avoided
--  (§4/README plan: known slave-mode errata reputation on the legacy IP).
--  Curated to exactly the target-mode subset spike 4 needs: own-address
--  set once at Enable, then the never-blocking data phase (§6.2) STM32G474.I2C1
--  drives to conform Machine.I2C.Generic_Target.
with System;
with System.Storage_Elements; use System.Storage_Elements;
with Interfaces; use Interfaces;

package STM32G474_PAC.I2C1
  with Preelaborate, SPARK_Mode
is
   Base : constant System.Address := System'To_Address (16#4000_5400#);

   --  CR1 (0x00) -- bit 0 PE (peripheral enable). Written once at
   --  Enable/Disable time.
   CR1 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#00#;
   CR1_PE : constant := 2#1#;                      --  bit 0

   --  OAR1 (0x08) -- own address 1: bits [7:1] = 7-bit address, bit 10
   --  OA1MODE (0 = 7-bit), bit 15 OA1EN. Written once at Enable time.
   OAR1 : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#08#;
   OAR1_OA1EN : constant := 2#1# * 2**15;

   --  TIMINGR (0x10) -- bus timing (filter widths, SCL high/low counts).
   --  Still consulted in target mode (sampling/filter timing, RM0440),
   --  even though the target never generates the clock itself. Written
   --  once at Enable time; the exact value is a placeholder computed
   --  for the default HSI16 core clock (D8: bus timing is native
   --  configuration, not part of the portable contract, same as
   --  RP2040.I2C0's HCNT/LCNT) -- re-derive with STM32CubeMX's I2C timing
   --  calculator (or RM0440's own worked examples) before real hardware
   --  bring-up rather than trusting this value.
   TIMINGR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Address => Base + 16#10#;

   --  ISR (0x18) -- status, hardware-set, no side effect from reading it
   --  (some bits clear as a side effect of RXDR/TXDR access instead, or
   --  via ICR -- same split RP2040_PAC.I2C0 documents between
   --  IC_RAW_INTR_STAT and IC_CLR_TX_ABRT).
   ISR : Unsigned_32
     with Volatile, Async_Writers, Effective_Writes => False,
          Address => Base + 16#18#;
   ISR_TXE   : constant := 2#1#;                   --  bit 0
   ISR_TXIS  : constant := 2#1# * 2**1;             --  bit 1: master wants a byte
   ISR_RXNE  : constant := 2#1# * 2**2;             --  bit 2: a byte arrived
   ISR_ADDR  : constant := 2#1# * 2**3;             --  bit 3: address matched
   ISR_NACKF : constant := 2#1# * 2**4;             --  bit 4
   ISR_STOPF : constant := 2#1# * 2**5;             --  bit 5
   ISR_DIR   : constant := 2#1# * 2**16;            --  bit 16: 1 = master reads

   --  ICR (0x1C) -- write-1-to-clear (§9's converged ESP32-C3 encoding).
   ICR : Unsigned_32
     with Volatile, Async_Readers, Effective_Writes => True,
          Address => Base + 16#1C#;
   ICR_ADDRCF : constant := 2#1# * 2**3;
   ICR_STOPCF : constant := 2#1# * 2**5;

   --  RXDR (0x24) -- reading dequeues the byte the master wrote and
   --  clears RXNE (a side effect); hardware refills it on the next byte.
   --  Same aspect set as RP2040_PAC.I2C0.IC_CLR_TX_ABRT (§9): Async_Writers
   --  is required alongside Effective_Reads (SPARK RM 7.1.2(6)) because
   --  something else -- the hardware -- must be able to write the object
   --  for "reading has an effect" to be meaningful.
   RXDR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Effective_Reads => True,
          Address => Base + 16#24#;

   --  TXDR (0x28) -- writing supplies the next byte for the master to
   --  read and clears TXIS (a side effect); hardware consumes it.
   TXDR : Unsigned_32
     with Volatile, Async_Readers, Async_Writers, Effective_Writes => True,
          Address => Base + 16#28#;

end STM32G474_PAC.I2C1;
