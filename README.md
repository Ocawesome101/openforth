# OpenForth

This currently implements `if then else free dup ldi fls words cr drop pwr * + < - . /`, comments `( ... )`, and custom word definitions with `: ;`.  `if then else` are not currently implemented as words.  This may change.  `fls` takes no parameters and displays a map of `N=FSADDRESS`.  `ldi` takes one argument and loads `init.lua` from the corresponding filesystem. `pwr` reboots if its argument is `1`, otherwise shuts down.

Due to size limitations error checking is minimal, as are implemented features.
