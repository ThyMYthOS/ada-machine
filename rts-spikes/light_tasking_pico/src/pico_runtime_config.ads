--  The renaming shim (mirrors rts-spikes/CONTRACT.md §3.3). Alire generates
--  gnat_config/light_tasking_pico_config.ads; tier-2/tier-3 sources cannot
--  `with` a name that varies per leaf, so the leaf commits this indirection
--  under one stable name, Pico_Runtime_Config.

pragma Restrictions (No_Elaboration_Code);
pragma Style_Checks (Off);

with Light_Tasking_Pico_Config;
package Pico_Runtime_Config renames Light_Tasking_Pico_Config;
