# luarepl

Provides a `lua` binary that can be used to
- access Lua repl with patched `require` that can access sysroot packages. Run as `lua` without arguments.
- run standalone lua scripts with patched `require`. Run as `lua path/to/script.lua args...`.

Imports relative to the working directory are unsupported. Use [impure environments](../runfs) instead for anything more complex than a single script.
