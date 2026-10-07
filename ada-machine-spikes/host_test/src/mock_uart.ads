--  Mock_Uart -- host stand-in for an L2 UART port (Machine.UART.
--  Generic_Port's formal shape): TX bytes are collected in memory so a
--  test can write the exact byte stream a board would put on the wire
--  (Log_Sink records plus the test-mode verdict line) to a file.
with Machine.UART;
package Mock_Uart
  with SPARK_Mode => Off
is
   type Frame is mod 2**8;

   function Is_Tx_Ready return Boolean;           --  always ready
   procedure Put_Frame (Data : Frame);            --  append to the buffer
   function Is_Rx_Ready return Boolean;           --  never
   procedure Get_Frame (Data : out Frame;
                        Status : in out Machine.UART.Line_Status);

   Max_Bytes : constant := 4096;
   type Byte_Buffer is array (1 .. Max_Bytes) of Frame;

   Buffer : Byte_Buffer := (others => 0);
   Count  : Natural := 0;

   procedure Reset;
end Mock_Uart;
