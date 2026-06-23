# keyboard

[libxkbcommon](https://xkbcommon.org) but in Minecraft!

Enables switching keyboard layouts. The API surface is quite versatile, enabling anything from simple key-to-char mapping to IME to keyboard macros.

## Usage as a user

To activate a non-default layout, use <kbd>Alt-Shift-(Key)</kbd>, where `Key` is one of the following QWERTY keys:
- `f` (`<AC04>`), phonetic Rulemak-DH by Yuki
- `j` (`<AC07>`), standard JCUKEN layout for Russian language

Names in angle brackets refer to [xkb keycodes](https://xkbcommon.org/doc/current/keymap-text-format-v1-v2.html#the-xkb_keycodes-section).

To switch back to the native layout, use <kbd>Alt-Shift</kbd>. Pressing <kbd>Alt-Shift</kbd> toggles between the most recently used non-default layout and the native layout.

## Usage as a developer

This is a low-level library that handles keyboard layouts and translates the events `key`, `key_up`, and `char`.

```lua
local keyboard = require "keyboard"

local kb = keyboard.new(function(event)
    -- deliver event in any way
end)

while true do
    local event = table.pack(os.pullEvent())
    if event[1] == "key" then
        kb:on_key(event)
    elseif event[1] == "key_up" then
        kb:on_key_up(event)
    elseif event[1] == "char" then
        kb:on_char(event)
    else
        -- handle other events
    end
end
```

### Keyboard handler API

- `require "keyboard".new`: Create new keyboard handler
- `kb:setNativeLayout()`: Switch to native layout
- `kb:toggleLayout()`: Toggle layouts between native and the most recently-used custom layout, as if by <kbd>Alt-Shift</kbd>
- `kb:setCustomLayout(key)`: Switch to custom layout and update the most recently-used custom layout, as if by <kbd>Alt-Shift-key</kbd>
- `kb.last_custom_layout_name`: The [key](https://tweaked.cc/module/keys.html) corresponding to the most recently-used custom layout or `nil`
- `kb:on_key(event)`, `kb:on_key_up(event)`, `kb:on_char(event)`: Hooks for `key`, `key_up`, and `char` events

## Custom layouts

Currently, all layouts are hard-coded in `keyboard.layouts` subpackage. Layout autodetection and impure layouts are planned, but currently not yet implemented.

Layouts are defined in Lua files. Lua layout file should return a factory function that returns a layout handler. This function can be called more than once, and the returned layout objects should be independent and share no state.

### Table-based layouts

Most layouts are one-to-one key to char mappings, and we have a `simple` API to facilitate creation of such layouts. `require "keyboard.simple"` is a layout factory factory that accepts a map of key names from [`keys` API](https://github.com/cc-tweaked/CC-Tweaked/blob/mc-1.20.x/projects/core/src/main/resources/data/computercraft/lua/rom/apis/keys.lua#L16) to a list of characters:

```lua
return require "keyboard.simple" {
    one = { '1' }, -- types the same character regardless of modifiers
    two = { '2', '@' }, -- separate normal and "Shift" characters
    three = { '3', '#', 'e' }, -- adds an "AltGr" character. AltGr+Shift falls back to AltGr
    four = { '4', '$', 'r', 'R' }, -- all four combinations
}
```

Table-based layouts support four levels with usual Shift and [AltGr](https://en.wikipedia.org/wiki/AltGr_key) semantics:
- Caps Lock has no special treatment.
- Level 1 is accessed without modifiers.
- Level 2 is accessed with any <kbd>Shift</kbd>.
- Level 3 is accessed with <kbd>AltGr</kbd> (right <kbd>Alt</kbd>).
- Level 4 is accessed with <kbd>AltGr</kbd> and any <kbd>Shift</kbd>.
- If the key description does not specify the required level, then a subset of modifiers is probed. A subset of higher level takes precedence, so if a key has three levels and <kbd>AltGr</kbd> and <kbd>Shift</kbd> are pressed, level 3 is used (drop <kbd>Shift</kbd>) instead of level 2 (drop <kbd>AltGr</kbd>).

Keys that are not mentioned (literally the 99% of the keyboard in the example) use the native key-to-char conversion to enable partial mappings.

Remapping the key to the right of a short <kbd>Shift</kbd> on an ISO keyboard (`<LSGT>`) this way is unsupported due to GLFW not being able to agree internally which key should it be (`WORLD_1` or `WORLD_2`) and CC: Tweaked commenting out the corresponding `world1` and `world2` definitions in `keys` API.

### Layout handler API

If simple tables were not enough for your layout needs, you can construct the layout handler object manually. The layout handler must export `on_key` method and can export two optional methods `on_key_up` and `on_char`, which are invoked when the corresponding event arrives to the machine and decide which events are delivered to the running program:

```lua
return function() -- factory
    return {
        on_key = ...,
        on_key_up = ...,
        on_char = ...,
    }
end
```

The layout handler can use these callbacks in the following way:

- The `on_key` handler can inspect the pressed key and manually emit a `char` event, suppressing the native `char` event (if any). If the key is unknown, it can fall back to the native layout and pass the native `char` event through. This method is used by table-based layouts.

- Alternatively, the `on_char` handler can inspect the native `char` event and decide between delivering it and delivering some other events. This method can be used for [transliteration](https://en.wikipedia.org/wiki/Transliteration).

- Both `on_key` and `on_char` can deliver events other than `char`. For example, the handler can emit a `key`+`key_up` pair for <kbd>Backspace</kbd> to allow a character to be typed with multiple key presses.

Note that while the native `char` event can be dropped by `on_key`, the native `key` and `key_up` events are always delivered. Event manipulation is limited to dropping `char` and emitting arbitrary events.

All three methods take the following parameters:

- `send_event: function(event)`: a callback to deliver an event, e.g. `send_event({ "char", "x" })`.

- `keys_pressed: { key: boolean }`: a set of keycodes that are currently pressed. `keys_pressed` shows which keys were pressed *prior to* handling the relevant event. For `key`, the key that is being pressed is not in it; for `key_up`, the key that is being unpressed is still in it.

- `event`: the corresponding event table. `event[1]` is the event name.

#### `layout.on_key(send_event, keys_pressed, event)`

Handle a `key` event. If this function returns `true`, the corresponding `char` event will be dropped. If it returns `false` or `nil`, the `char` event will be delivered.

Note that calling `send_event(event)` in this handler is redundant, since the `key` event is always delivered. You should only need `send_event({ "char", ... })` and `send_event({ "key", ... }); send_event({ "key_up", ... })` here.

#### `layout.on_key_up(send_event, keys_pressed, event)`

Handle a `key_up` event. This is usually not required. If absent, treated as an empty function.

#### `layout.on_char(send_event, keys_pressed, event)`

Handle a native `char` event. This function doesn't see `char` events emitted via `send_event`. It is invoked regardless of the return value of `on_key`:

- If `on_key` returns `false`, the native `char` event will be delivered, along with any events sent by `on_char`.
- If `on_key` returns `true`, the native `char` event will be dropped. If `on_char` wants to deliver it, it can call `send_event(event)`.

If absent, treated as an empty function.

#### Various pitfalls

Beware of sending `char` event with code `0x0A`, as most real-world programs expect only `key` event with `key.enter`.

If you send a `key` event, don't forget to send `key_up` event.

#### Example layout: Native

```lua
return function()
    return {
        on_key = function() end
    }
end
```

This layout is redundant as native layout is built in the code, but is still a valid example of minimal but working layout.

#### Example layout: Null

```lua
return function()
    return {
        on_key = function()
            return true -- don't forward next `char` event
        end
    }
end
```

This is not a very useful layout as it suppresses all `char` events and only `key`/`key_up` events are delivered.

#### Example layout: Keyboard macros

> -- Mom, can we have `xdotool type`?
>
> -- No, sweetie, we have `xdotool type` at home.
>
> `xdotool type` at home:

```lua
local function type(send_event, str)
    for i = 1, #str do
        send_event({ "char", str:sub(i, i) })
    end
end

return function()
    return {
        on_key = function(send_event, keys_pressed, event)
            if keys_pressed[keys.menu] then
                if event[2] == keys.one then
                    type(send_event, "meow :3")
                elseif event[2] == keys.two then
                    type(send_event, "svc reboot")
                    send_event({ "key", keys.enter })
                    send_event({ "key_up", keys.enter })
                end
                return true
            end
        end
    }
end
```
