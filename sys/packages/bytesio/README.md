# bytesio

A `ReadHandle`/`WriteHandle`/`ReadWriteHandle` polyfill based on in-memory data. Can be used to pass controlled data to functions that expect file handles without going through the FS, or to simulate a `tmpfs`.

## Usage

`bytesio.open(contents, mode)` is similar to `fs.open(path, mode)`, but the string denotes the initial contents of the file as opposed to its path. Returns two values: the file handle and a getter function to retrieve the contents of the file at any point (useful if the mode allows writing).

```lua
local bytesio = require "bytesio"

local f1 = bytesio.open("Hello, world!", "r")
assert(f1.read(5) == "Hello")
assert(f1.readAll() == ", world!")
f1.close()

local f2, get = bytesio.open("", "w+")
f2.write("test")
assert(get() == "test")
f2.seek("set", 0)
assert(f2.readAll() == "test")
f2.close()
```
