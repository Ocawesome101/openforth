: example_rect 256 0 do i 16 mod 0 = if cr then ." *" loop ;
: example_mult cr 11 1 do dup i * . loop drop ;
: example_mtbl cr 11 1 do i example_mult loop ;
