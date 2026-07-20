--  The never-blocking L2 data phase: the UART equivalent of
--  Machine.I2C.Generic_Master / Machine.SPI.Generic_Master (§6.3).
generic
   type Frame is mod <>;                  --  UART word; mod 2**5 .. 2**9
   with function  Is_Tx_Ready return Boolean;
                                          --  True when Put_Frame may be called
   with procedure Put_Frame (Data : Frame);
                                          --  enqueue one frame; never blocks
   with function  Is_Rx_Ready return Boolean;
                                          --  True when a frame is available
   with procedure Get_Frame (Data : out Frame; Status : in out Line_Status);
                                          --  dequeue one frame; chained (§7.1)
package Machine.UART.Generic_Port
  with Pure, SPARK_Mode
is end Machine.UART.Generic_Port;
