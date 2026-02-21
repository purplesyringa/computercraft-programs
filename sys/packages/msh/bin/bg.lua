local args = { ... }
if #args ~= 0 then
    shell.openTab(table.unpack(tArgs))
else
    shell.openTab("msh")
end
