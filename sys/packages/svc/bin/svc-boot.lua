local configs = require "svc.configs"
local services = require "svc.services"
local targets = require "svc.targets"

assert(not os._svc, "svc-boot has already run")

local svc = {
    start = services.start,
    stop = services.stop,
    kill = services.kill,
    reach = targets.reach,
    serviceStatus = services.status,
    targetStatus = targets.status,
}

function svc.reload()
    configs.reload()
    targets.reload()
end

function svc.status()
    return {
        services = services.allStatus(),
        target = targets.currentStatus(),
    }
end

-- Expose the singleton as `require "svc"`.
os._svc = svc

svc.reload()

settings.define("svc.target", {
    description = "Default target to reach",
    default = "shell",
    type = "string",
})
local target = settings.get("svc.target")
if not svc.targetStatus(target) then
    target = "shell"
end
svc.reach(target)
