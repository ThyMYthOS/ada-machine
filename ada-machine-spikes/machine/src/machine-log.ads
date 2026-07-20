--  Deferred-formatting logging vocabulary: ids + scalars, no strings.
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
   --  entirely. In a full build this is rendered from an Alire
   --  configuration variable (ties into TODO #7's config plumbing);
   --  hardcoded here since that plumbing isn't wired end-to-end in
   --  these spikes yet.
   Enabled_Level : constant Level := Info;

   function Enabled (L : Level) return Boolean is (L <= Enabled_Level);

end Machine.Log;
