--  Stand-in for the config package Alire generates from alire.toml's
--  [configuration.variables] (§16: "static choices ... use Alire crate
--  configuration variables -> generated config packages"). A real build
--  gets this from `alr build`; hand-authored here since this spike has
--  no Alire/toolchain available to generate it.
package ATmega328P_HAL_Config
  with Pure, SPARK_Mode
is
   F_CPU : constant := 16_000_000;   --  Hz; matches a 16 MHz crystal Pico-class board
end ATmega328P_HAL_Config;
