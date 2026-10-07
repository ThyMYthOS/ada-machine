package body Mock_Uart
  with SPARK_Mode => Off
is
   function Is_Tx_Ready return Boolean is (True);

   procedure Put_Frame (Data : Frame) is
   begin
      if Count < Max_Bytes then
         Count := Count + 1;
         Buffer (Count) := Data;
      end if;
   end Put_Frame;

   function Is_Rx_Ready return Boolean is (False);

   procedure Get_Frame (Data : out Frame;
                        Status : in out Machine.UART.Line_Status) is
      pragma Unreferenced (Status);
   begin
      Data := 0;
   end Get_Frame;

   procedure Reset is
   begin
      Count := 0;
   end Reset;
end Mock_Uart;
