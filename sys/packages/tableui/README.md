# tableui

A small library for drawing tables.

## Usage

```lua
local tableui = require "tableui"

local writeRow = tableui.header({
	{ key = "title", heading = "Title", width = 12 },
	{ key = "rating", heading = "Rating", width = 8 },
	{ key = "description", heading = "Description" },
})
writeRow({ title = "Weird stuff", rating = "3/10", description = "Somewhat approachable" })
writeRow({ title = "Cinema", rating = "11/10", description = "Absolute cinema" })
```

Call `tableui.header` to draw a table header and get a callback that can then be invoked on each row. Each element of the list passed to `header` corresponds to a column; the meaning of the keys `key`, `heading`, and `width` should be self-descriptive. `width` should be present for all columns except the last one.
