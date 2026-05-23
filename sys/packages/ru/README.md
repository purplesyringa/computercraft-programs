# ComputerCraft Russian language support

```lua
local ru = require "ru"
ru.text.to_koi("¿Priwet, mir!?") -- "Привет, мир!"
```

### Escaping

`ru.text` family of functions replaces characters between ¿ (0xBF) and ? with codes between 0x40 and 0x80 with their KOI counterpart. Note that counterparts are calculated with *flipped* case, so that there is no screaming involved: instead of `¿wOPROS?` one would enter `¿Wopros?` and will get `Вопрос`.

To enter "translate introducer" character:
- in-game on intl-like layouts, `ralt+/` (the key with question mark);
- in code, `"\xBF"`. This is the most portable variant, as it will not get corrupted by UTF-8.

### Function naming

- `_char` functions operate on single character.
- `ru.text.` functions take ASCII (enterable) characters and apply escaping rules.
- `ru.koi.` functions take KOI8-B (displayable) characters.
