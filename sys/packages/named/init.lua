settings.define("named.hostname", {
    description = "Unique hostname",
    type = "string",
})

local named = {}

function named.hasHostname()
    return settings.get("named.hostname") ~= nil
end

function named.hostname()
    local hostname = settings.get("named.hostname")
    if hostname == nil then
        error("Hostname not configured")
    end
    return hostname
end

function named.setHostname(hostname)
    settings.set("named.hostname", hostname)
    settings.save()
    rednet.host("named", hostname)
end

function named.lookup(hostname_or_computer_id)
    local id = tonumber(hostname_or_computer_id)
    if id and id >= 0 and id % 1 == 0 then
        return id
    end
    return rednet.lookup("named", hostname_or_computer_id)
end

function named.collect(pattern, timeout)
    rednet.broadcast(pattern, "named-request")

    local hosts = {}
    parallel.waitForAny(function()
        os.sleep(timeout or 5) -- default
    end, function()
        local seen = {}
        while true do
            local sender, hostname = rednet.receive("named-response")
            if not seen[sender] then
                seen[sender] = true
                table.insert(hosts, { id = sender, hostname = hostname })
            end
        end
    end)
    return hosts
end

return named
