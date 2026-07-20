--  ATmega328P SPI -- SPCR/SPSR/SPDR, data-space addresses per the
--  datasheet register summary. No FIFO: SPDR is a single-byte shift
--  register (Appendix C.1's "depth-1 FIFO" data point).
with System;
with Interfaces; use Interfaces;

package ATmega328P_PAC.SPI
  with Preelaborate, SPARK_Mode
is
   SPCR : Unsigned_8         --  control: SPE, MSTR, CPOL, CPHA, SPR1:0, SPIE
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#4C#);
   SPSR : Unsigned_8         --  status: SPIF (bit7), WCOL (bit6), SPI2X (bit0)
     with Volatile, Async_Readers, Async_Writers,
          Address => System'To_Address (16#4D#);
   SPDR : Unsigned_8         --  data: write starts a transfer, read fetches it
     with Volatile, Async_Readers, Async_Writers,
          Effective_Reads => True, Effective_Writes => True,
          Address => System'To_Address (16#4E#);

   SPCR_SPE  : constant := 2#1# * 2**6;   --  bit 6: SPI enable
   SPCR_MSTR : constant := 2#1# * 2**4;   --  bit 4: master mode
   SPCR_CPOL : constant := 2#1# * 2**3;   --  bit 3
   SPCR_CPHA : constant := 2#1# * 2**2;   --  bit 2
   SPCR_DORD : constant := 2#1# * 2**5;   --  bit 5: 1 = LSB first
   SPCR_SPIE : constant := 2#1# * 2**7;   --  bit 7: interrupt enable (SPI_STC)

   SPSR_SPIF  : constant := 2#1# * 2**7;  --  bit 7: transfer complete
   SPSR_SPI2X : constant := 2#1#;         --  bit 0: double SPI speed
end ATmega328P_PAC.SPI;
