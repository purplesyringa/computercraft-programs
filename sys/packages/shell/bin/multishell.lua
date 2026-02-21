local first_run = true
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
    }, { __index = os }),
}, "/rom/programs/advanced/multishell.lua")
