local motds = {}
for line in io.lines(fs.combine(shell.getRunningProgram(), "../../motd")) do
    table.insert(motds, line)
end
print(motds[math.random(1, #motds)])
