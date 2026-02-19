settings.define("named.hostname", {
    description = "Unique hostname",
    type = "string",
})
local hostname = settings.get("named.hostname")

if hostname ~= nil then
    peripheral.find("modem", rednet.open)
    rednet.host("named", hostname)
end

return {
    hostname = function()
        local hostname = settings.get("named.hostname")
        if hostname == nil then
            error("Hostname not configured")
        end
        return hostname
    end,
    setHostname = function(hostname)
        settings.set("named.hostname", hostname)
        settings.save()
    end,
}
