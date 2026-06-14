settings.define("named.hostname", {
    description = "Unique hostname",
    type = "string",
})

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
        rednet.host("named", hostname)
    end,

    lookup = function(hostname_or_computer_id)
        local id = tonumber(hostname_or_computer_id)
        if id and id >= 0 and id % 1 == 0 then
            return id
        end
        return rednet.lookup("named", hostname_or_computer_id)
    end,

    collect = function(pattern)
        rednet.broadcast(pattern, "named-request")

        local timeout = 5
        local finish = os.clock() + timeout

        local seen = {}
        local hosts = {}

        while timeout > 0 do
            local sender, hostname = rednet.receive("named-response", timeout)
            timeout = finish - os.clock()
            if not sender then
                break
            end
            if not seen[sender] then
                seen[sender] = true
                table.insert(hosts, { id = sender, hostname = hostname })
            end
        end

        return hosts
    end,
}
