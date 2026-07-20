--  Ada Machine: root of the portable contract. Holds only the shared
--  vocabulary; peripheral classes are child packages (Machine.I2C, ...).
package Machine
  with Pure, SPARK_Mode
is
   type Byte is mod 2**8 with Size => 8;
   type Byte_Array is array (Positive range <>) of Byte;
end Machine;
