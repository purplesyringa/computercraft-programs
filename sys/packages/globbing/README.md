# globbing

A library for translating POSIX-style globs (with `*` and `?`) to Lua patterns.

### Usage

`globbing.toPattern(glob)` -- produce a pattern from a glob. The returned pattern is wrapped in `^...$`, so it can be immediately passed to `string.match`.
