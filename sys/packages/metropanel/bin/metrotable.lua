local async = require "async"
local display = require "metropanel.display"
async.spawn(display.thread, true)
async.drive()
