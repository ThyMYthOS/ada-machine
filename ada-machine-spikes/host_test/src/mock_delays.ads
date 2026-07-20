--  Mock_Delays -- host stand-in for Machine.Blocking.Generic_Delays'
--  formals. No real waiting needed: Mock_Regmap's status register
--  already reads "not measuring", so Measure's poll loop exits on its
--  first pass regardless of whether Delay_Ms actually elapses time.
package Mock_Delays
  with SPARK_Mode
is
   procedure Delay_Us (Us : Natural) with Global => null;
   procedure Delay_Ms (Ms : Natural) with Global => null;
end Mock_Delays;
