# ComputerCraft Russian language support

```lua
local ru = require "ru"
local text = "<Priwet, mir!>"
local koi = ru.text.to_koi(text) -- "Привет, мир!"
local text2 = ru.koi.to_text(koi) -- "<Priwet, mir>!"
```

Note that ComputerCraft uses a modification of ISO 8859-1 and CP437 as its base layout. To display KOI8 text properly, install [this resource pack](./CCT-koi8b-russian-pack.zip). It replaces all characters required by [KOI8-B](https://en.wikipedia.org/wiki/KOI8-B), and keeps pseudographics in place. To find out which characters are lost, inspect characters 0xA3, 0xB3, and 0xC0..=0xFF in [this CC charmap viewer](https://charmap.madefor.cc)

### Syntax

`ru.text` family of functions replaces characters between `<` and `>` with codes between 0x40 and 0x80 with their KOI counterpart. Note that counterparts are calculated with *flipped* case, so that there is no screaming involved: instead of `<wOPROS>` one would enter `<Wopros>` and will get `Вопрос`.

### Escaping

`<` is parsed as a literal character when within a `<...>` group, and similarly `>` is parsed as a literal character when outside of a `<...>` group. This means that a lone `<` can be escaped as `<<>`, and a `>` inside a translated group can be escaped as `>><`.

### Function naming

- `_char` functions operate on single character.
- `ru.text.` functions take ASCII (enterable) characters and apply escaping rules.
- `ru.koi.` functions take KOI8-B (displayable) characters.

### Playground

Use `convrepl` to test conversions between text and koi representations. Enter empty string to quit.
