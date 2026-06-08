local args = { ... }
if #args ~= 0 then
    shell.openTab(table.unpack(args))
else
    shell.openTab("msh")
end
