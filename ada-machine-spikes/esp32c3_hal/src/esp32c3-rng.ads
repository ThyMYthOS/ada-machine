--  esp32c3-rng.ads -- the ESP32-C3's hardware RNG as Machine.RNG.Generic_Source
--  (TODO.md #11): the second, structurally different RNG data point after
--  STM32G474's. STM32's RNG has an enable bit, a data-ready flag and
--  seed/clock health flags; this one is a single read-only data register
--  with none of them. Mapping it onto the signature therefore exposes
--  what the signature cannot say:
--    * Is_Ready is constant True -- the register always holds a word.
--    * Get_Word can never report Seed_Error/Clock_Error: there is no
--      health interface to derive them from, so Status is never modified
--      (GNATprove's "could be IN" note on it is the honest reflection).
--    * Whether the words are *true* random depends on an entropy source
--      outside this peripheral (RF subsystem enabled, or the SAR/high-speed
--      ADC noise source switched on -- bootloader_random_enable in
--      esp-idf); otherwise only a weaker secondary source feeds it.
--      That is native configuration (D8) the portable contract can neither
--      enable nor verify, so this package states it instead of pretending.
with ESP32C3_PAC.SYSCON;
with Interfaces;
use type Interfaces.Unsigned_32;
with Machine.RNG;
use type Machine.RNG.Rng_Status;

package ESP32C3.RNG
  with Preelaborate, SPARK_Mode
is
   function Is_Ready return Boolean is (True)
     with Inline_Always;

   procedure Get_Word (Value  : out Interfaces.Unsigned_32;
                       Status : in out Machine.RNG.Rng_Status)
     with Inline_Always,
          Global => (Input => ESP32C3_PAC.SYSCON.RND_DATA),
          Post   => (if Status'Old /= Machine.RNG.Ok
                     then Status = Status'Old and Value = 0);
end ESP32C3.RNG;
