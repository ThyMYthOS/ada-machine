package body Mock_Regmap
  with SPARK_Mode,
       Refined_State => (State => (File, Writes))
is

   subtype Index is Natural range 0 .. 255;
   File : array (Index) of Byte := (others => 0);
   Writes : Natural := 0;

   function To_Index (Reg : Reg_Address) return Index is
     (Index (Byte (Reg)));

   procedure Write_Reg (Reg : Reg_Address; Value : Byte;
                        Status : in out Access_Status) is
   begin
      if Status /= Ok then
         return;                             --  chained: skip if pending
      end if;
      File (To_Index (Reg)) := Value;
      Writes := Writes + 1;
   end Write_Reg;

   procedure Read_Regs (Start : Reg_Address; Data : out Byte_Array;
                        Status : in out Access_Status) is
      Base : constant Index := To_Index (Start);
   begin
      Data := (others => 0);
      if Status /= Ok then
         return;                             --  chained: skip if pending
      end if;
      for I in Data'Range loop
         Data (I) := File (Base + (I - Data'First));
      end loop;
   end Read_Regs;

   function Write_Count return Natural is (Writes);

begin
   --  Chip id (0xD0) and "not measuring" status (0xF3).
   File (16#D0#) := 16#60#;
   File (16#F3#) := 16#00#;

   --  Calibration 0x88..0x9F (T1,T2,T3,P1..P9, LE 16-bit each) --
   --  encodes dig_T1=27504, T2=26435, T3=-1000, P1=36477, P2=-10685,
   --  P3=3024, P4=2855, P5=140, P6=-7, P7=15500, P8=-14600, P9=6000.
   File (16#88#) := 16#70#; File (16#89#) := 16#6B#;
   File (16#8A#) := 16#43#; File (16#8B#) := 16#67#;
   File (16#8C#) := 16#18#; File (16#8D#) := 16#FC#;
   File (16#8E#) := 16#7D#; File (16#8F#) := 16#8E#;
   File (16#90#) := 16#43#; File (16#91#) := 16#D6#;
   File (16#92#) := 16#D0#; File (16#93#) := 16#0B#;
   File (16#94#) := 16#27#; File (16#95#) := 16#0B#;
   File (16#96#) := 16#8C#; File (16#97#) := 16#00#;
   File (16#98#) := 16#F9#; File (16#99#) := 16#FF#;
   File (16#9A#) := 16#8C#; File (16#9B#) := 16#3C#;
   File (16#9C#) := 16#F8#; File (16#9D#) := 16#C6#;
   File (16#9E#) := 16#70#; File (16#9F#) := 16#17#;

   --  H1 (0xA1) = 75.
   File (16#A1#) := 16#4B#;

   --  0xE1..0xE7: H2=362, H3=0, H4=333, H5=0, H6=30.
   File (16#E1#) := 16#6A#; File (16#E2#) := 16#01#;
   File (16#E3#) := 16#00#;
   File (16#E4#) := 16#14#; File (16#E5#) := 16#0D#;
   File (16#E6#) := 16#00#;
   File (16#E7#) := 16#1E#;

   --  0xF7..0xFE burst: encodes adc_P=415148, adc_T=519888, adc_H=25000
   --  (the reference vector this crate checks BME280 against).
   File (16#F7#) := 16#65#; File (16#F8#) := 16#5A#; File (16#F9#) := 16#C0#;
   File (16#FA#) := 16#7E#; File (16#FB#) := 16#ED#; File (16#FC#) := 16#00#;
   File (16#FD#) := 16#61#; File (16#FE#) := 16#A8#;
end Mock_Regmap;
