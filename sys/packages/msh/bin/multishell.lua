local first_run = true

local nested
local shift_held = false

local hangup_in_process = 0
local hangup_saved_focus = nil

os.run({
    shell = shell,
    os = setmetatable({
        run = function(env, path, ...)
            if first_run and path == "/rom/programs/shell.lua" then
                first_run = false
                path = shell.resolveProgram("msh")
            end
            return os.run(env, path, ...)
        end,

        pullEventRaw = function(filter)
            if not nested then
                local i, k, v = 1
                repeat
                    k, v = debug.getlocal(2, i)
                    i = i + 1
                until k == nil or k == "multishell"
                assert(k)
                nested = v
            end

            if hangup_in_process > 0 then
                nested.setFocus(hangup_in_process)
                hangup_in_process = hangup_in_process - 1
                if hangup_in_process == 0 then
                    nested.setFocus(hangup_saved_focus)
                end
                return "terminate", "hangup"
            end

            while true do
                local event = table.pack(os.pullEventRaw())

                if (event[1] == "key" or event[1] == "key_up") and (event[2] == keys.leftShift or event[2] == keys.rightShift) then
                    shift_held = event[1] == "key"
                end

                if event[1] == "terminate" and event[2] == "hangup" then
                    -- Initiate hangup, delivering events to processes one by one. A bit ugly, but
                    -- it works.
                    hangup_saved_focus = nested.getFocus()
                    local count = nested.getCount()
                    nested.setFocus(count)
                    hangup_in_process = count - 1
                    return "terminate", "hangup"
                end

                if event[1] == "key" and event[2] == keys.pause then
                    local n = nested.getCount()
                    local i = nested.getFocus()
                    if shift_held then
                        if i == 1 then
                            nested.setFocus(n)
                        else
                            nested.setFocus(i - 1)
                        end
                    else
                        if i == n then
                            nested.setFocus(1)
                        else
                            nested.setFocus(i + 1)
                        end
                    end
                elseif not filter or event[1] == filter or event[1] == "terminate" then
                    return table.unpack(event, 1, event.n)
                end
            end
        end,
    }, { __index = os }),
}, "/rom/programs/advanced/multishell.lua")
