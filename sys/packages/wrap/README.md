# wrap

Patches the built-in `lua` command so that `require` can access system packages. The command is still called `lua`.

Imports relative to the working directory are unsupported.

Provides `wrap` binary that allows running lua scripts with patched require paths.
