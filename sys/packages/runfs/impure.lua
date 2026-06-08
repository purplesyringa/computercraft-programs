settings.define("svc.impure", {
    description = "Load packages and targets from /impure",
    default = false,
    type = "boolean",
})

return {
    get = function()
        return settings.get("svc.impure")
    end,
    set = function(value)
        settings.set("svc.impure", value)
        settings.save()
    end,
}
