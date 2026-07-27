local environ = require "environ"

local args = { ... }

if not next(args) then
    os.run({
        shell = shell,
        require = function(name)
            if name == "cc.require" then
                return {
                    make = function()
                        -- `require` and `package` are already set up to import from system packages.
                        return require, package
                    end,
                }
            end
            return require(name)
        end,
    }, "/rom/programs/lua.lua")
elseif args[1] == "--help" then
    printError("Usage:")
    printError("  lua")
    printError("  lua some.lua [args...]")
else
    environ.exec({
        env = _ENV,
        sysroot_require = true,
        path = shell.resolve(args[1]),
    }, table.unpack(args))
end
