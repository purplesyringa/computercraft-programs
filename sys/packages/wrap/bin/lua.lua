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
