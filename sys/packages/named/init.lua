return {
    hasHostname = function()
        return settings.get("named.hostname") ~= nil
    end,
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
        peripheral.find("modem", rednet.open)
        rednet.host("named", hostname)
    end,
}
