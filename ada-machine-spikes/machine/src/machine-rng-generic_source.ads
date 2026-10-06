--  The never-blocking L2 data phase for a hardware RNG. Deliberately the
--  narrowest possible formal set (§6.3 "narrow formals"): one native
--  word at a time, no byte-run convenience -- a caller wanting N bytes
--  slices Word itself, the same way Machine.UART.Generic_Port hands back
--  one Frame per call rather than a buffer.
generic
   type Word is mod <>;                     --  native RNG output width,
                                             --  mod 2**32 typical
   with function  Is_Ready return Boolean;   --  a fresh word is available
   with procedure Get_Word (Value : out Word; Status : in out Rng_Status);
                                             --  consume one word; chained
                                             --  on Rng_Status (§7.1). Ok
                                             --  means a word was delivered
                                             --  and no health fault was
                                             --  *reported* -- not that it
                                             --  is true random: a source
                                             --  with no health interface
                                             --  (ESP32-C3) can never
                                             --  report a fault, and
                                             --  entropy-source enabling
                                             --  is native config (D8)
package Machine.RNG.Generic_Source
  with Pure, SPARK_Mode
is end Machine.RNG.Generic_Source;
