--  Never-blocking full-duplex SPI data phase.
generic
   with function  Can_Push return Boolean;
                                    --  True when a byte may be started
   with procedure Push (Data : Byte; Status : in out Bus_Status);
                                    --  start exchanging one byte; never blocks
   with function  Can_Pop return Boolean;
                                    --  True when the exchanged byte is ready
   with procedure Pop (Data : out Byte; Status : in out Bus_Status);
                                    --  fetch the exchanged byte
package Machine.SPI.Generic_Master
  with Pure, SPARK_Mode
is end Machine.SPI.Generic_Master;
