--  ATmega328P Timer/Counter0 -- only the registers ATmega328P.Clock actually
--  touches (free-running overflow counting in Normal mode): TCCR0A/B select
--  the mode and prescaler, TIMSK0 enables the overflow interrupt. TCNT0/OCR0*/
--  TIFR0 are unused here and deliberately omitted (§9 rule 1: no completeness
--  padding). TCCR0A/B are low I/O-space registers, hence the same +0x20
--  data-space offset already visible in Port_B's PORTB/DDRB (0x25/0x24 here
--  vs. avr-libc's _SFR_IO8(0x05)/_SFR_IO8(0x04)); TIMSK0 is extended I/O
--  (memory-mapped directly, no offset), like the TWI registers alongside it.
with System;
with Interfaces; use Interfaces;

package ATmega328P_PAC.Timer0
  with Preelaborate, SPARK_Mode
is
   TCCR0A : Unsigned_8       --  mode: WGM01:0 (Normal = 00)
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#44#);
   TCCR0B : Unsigned_8       --  clock select: CS02:0 (prescaler)
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#45#);
   TIMSK0 : Unsigned_8       --  interrupt mask: TOIE0
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#6E#);

   TCCR0B_CS0_DIV_64 : constant := 2#011#;  --  CS02:0 = 011 -> clk/64
   TIMSK0_TOIE0      : constant := 2#1# * 2**0;  --  bit 0: overflow interrupt
end ATmega328P_PAC.Timer0;
