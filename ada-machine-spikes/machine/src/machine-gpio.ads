--  GPIO class vocabulary. Signatures live beneath as generic children.
--  Level is binary by construction (D8): a digital output is two-state;
--  Hi-Z/open-drain are configuration/direction concerns kept out of the
--  data phase, not "room for future states".
package Machine.GPIO
  with Pure, SPARK_Mode
is
   type Level is (Low, High);
end Machine.GPIO;
