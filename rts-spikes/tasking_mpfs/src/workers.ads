--  Jorvik forbids local tasks and protected objects, so these are
--  library-level rather than declared inside the main subprogram.
package Workers is

   protected Counter is
      procedure Bump;
      function Value return Natural;
   private
      N : Natural := 0;
   end Counter;

   --  Ravenscar allocates task stacks statically, so an explicit size keeps
   --  the image inside LIM (1920 KB) rather than taking the default.
   task Ticker with Storage_Size => 4 * 1024;

end Workers;
