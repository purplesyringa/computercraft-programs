local getty = {
    palettes = require "getty.palettes",
    Defaults = require "getty.defaults",
    Seat = require "getty.seat",
    Controller = require "getty.controller",
}

getty.current = getty.Seat.current

return getty
