package Faulty is
   procedure Boom;
   task Ticker with Storage_Size => 4 * 1024;
end Faulty;
