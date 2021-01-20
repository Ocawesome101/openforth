\ a shell.  or, rather, a set of utilities.
\ calling convention: COMPONENT_ID FILE_NAME

: ls 1 swap "list" swap invoke cr 0 do . loop ;
: cat cr fread . ;
