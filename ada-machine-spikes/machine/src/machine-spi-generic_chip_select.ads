with Machine.GPIO.Generic_Digital_Out;

--  Zero-cost polarity-aware chip-select wrapper over a digital-out pin.
--  Lives in SPI space (SPI is the only CS consumer today) but is
--  deliberately NOT part of the Generic_Master data-phase signature
--  (Machine.SPI's header comment / README §6.1). Polarity is a static
--  generic formal, so with Inline_Always each of Assert/Deassert folds to
--  a single Pin.Set call -- one GPIO store, same as a hand-written CS.Set.
generic
   with package Pin is new Machine.GPIO.Generic_Digital_Out (<>);
   Polarity : CS_Polarity;
package Machine.SPI.Generic_Chip_Select
  with Pure, SPARK_Mode
is
   procedure Assert
     with Inline_Always;
   procedure Deassert
     with Inline_Always;
end Machine.SPI.Generic_Chip_Select;
