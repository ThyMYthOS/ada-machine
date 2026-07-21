--  Deferred-formatting logging vocabulary: ids + scalars, no strings.
with Machine_Config;
package Machine.Log
  with Pure, SPARK_Mode
is
   type Event_Id is mod 2**16;
   type Arg is mod 2**32;
   No_Arg : constant Arg := 0;

   --  Severity, most to least urgent (§14.2).
   type Level is (Error, Warning, Info, Debug, Trace);

   --  Enabled threshold as a static constant so `if L <= Enabled_Level`
   --  folds away at compile time (§14.2), removing disabled call sites
   --  entirely -- rendered from the "Log_Level" Alire configuration
   --  variable declared in this crate's alire.toml (default: Info).
   --  A dependent crate overrides it from its own alire.toml:
   --
   --    [configuration.values]
   --    machine.Log_Level = "Debug"
   --
   --  (spike1_pico/alire.toml does exactly this, as a working example).
   --  Machine_Config.Log_Level_Kind can't be Level itself (it's
   --  declared in a different, generated package), so the two
   --  identical-literal enumerations are bridged through 'Pos/'Val --
   --  this stays a static expression because the config constant is,
   --  so the fold above is unaffected (ties into TODO #7's config
   --  plumbing: this crate is the first end-to-end reference for it).
   Enabled_Level : constant Level :=
     Level'Val (Machine_Config.Log_Level_Kind'Pos (Machine_Config.Log_Level));

   function Enabled (L : Level) return Boolean is (L <= Enabled_Level);

end Machine.Log;
