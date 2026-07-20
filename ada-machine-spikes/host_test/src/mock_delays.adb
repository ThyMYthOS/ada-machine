package body Mock_Delays
  with SPARK_Mode
is
   procedure Delay_Us (Us : Natural) is null;
   procedure Delay_Ms (Ms : Natural) is null;
end Mock_Delays;
