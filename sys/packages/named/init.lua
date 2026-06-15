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

function named._hostHostname(hostname)
    rednet.host("named", hostname)
    rednet.broadcast("named-response", hostname)
end

function named.setHostname(hostname)
    settings.set("named.hostname", hostname)
    settings.save()
    named._hostHostname(hostname)
end

function named.lookup(hostname_or_computer_id)
    local id = tonumber(hostname_or_computer_id)
    if id and id >= 0 and id % 1 == 0 then
        return id
    end
    return rednet.lookup("named", hostname_or_computer_id)
end

-- Used by the `named` service. Returns `true, hostname` if the current computer's hostname matches
-- the pattern, `false, nil` otherwise.
function named._ownHostnameMatchesPattern(pattern)
    local ok, hostname = pcall(named.hostname)
    if not ok then
        hostname = nil
    end
    if (hostname or ""):match(pattern) then
        return true, hostname
    else
        return false, nil
    end
end

function named.collect(pattern, timeout)
    rednet.broadcast(pattern, "named-request")

    local seen = {}
    local hosts = {}

    local ok, hostname = named._ownHostnameMatchesPattern(pattern)
    if ok then
        local id = os.computerID()
        seen[id] = true
        table.insert(hosts, { id = id, hostname = hostname })
    end

    parallel.waitForAny(function()
        os.sleep(timeout or 5) -- default
    end, function()
        while true do
            local sender, hostname = rednet.receive("named-response")
            if not seen[sender] and (hostname or ""):match(pattern) then
                seen[sender] = true
                table.insert(hosts, { id = sender, hostname = hostname })
            end
        end
    end)
    return hosts
end

return named
