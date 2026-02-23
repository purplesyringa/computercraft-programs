# pack

Static linking inspired by webpack, now ported to CC:Tweaked.

## Usage

Have you ever thought that copying a gazillion files to every single device is painful, only to forget one single dependency and copy them all over again? This problem is now solved by packing all the dependencies with the code to a single file!

```lua
local code = require("pack").packString("-- your code here")
```

All `require` calls within will be resolved and saved, so that the resulting code can be executed in clean environment.

Note that, unlike original webpack, there is no support for dynamic requires or packing other assets (e.g. with tmpfs). This only packs code and code dependencies.

If the thought of copying just one file to every single device is still inflicting pain, [`netboot`](../netboot) has you covered.
