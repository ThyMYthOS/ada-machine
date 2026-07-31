--  The renaming shim (CONTRACT.md §3.3). Alire generates
--  gnat_config/light_mpfs_config.ads, whose name embeds the profile;
--  shared tier-2/tier-3 sources cannot `with` a name that varies per
--  leaf, so every leaf commits this indirection under the one stable
--  name, MPFS_Runtime_Config.

pragma Restrictions (No_Elaboration_Code);
pragma Style_Checks (Off);

with Light_Mpfs_Config;
package MPFS_Runtime_Config renames Light_Mpfs_Config;
