return {
    description = "Configures rednet.host",
    type = "oneshot",
    start = function()
        settings.define("named.hostname", {
            description = "Unique hostname",
            type = "string",
        })
        local hostname = settings.get("named.hostname")

        if hostname ~= nil then
            peripheral.find("modem", rednet.open)
            rednet.host("named", hostname)
        end
    end,
}
