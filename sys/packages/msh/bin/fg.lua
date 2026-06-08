local args = { ... }
local tab
if #args ~= 0 then
    tab = shell.openTab(table.unpack(args))
else
    tab = shell.openTab("msh")
end
shell.switchTab(tab)
