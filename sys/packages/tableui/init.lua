local function doTabStop(goal_x)
	local x, y = term.getCursorPos()
	term.setCursorPos(math.max(x + 1, goal_x), y)
end

return {
	header = function(columns)
		local _, y = term.getCursorPos()
		term.setCursorPos(1, y)

		local next_tab_stop = 1
		for _, column in ipairs(columns) do
			column.tab_stop = next_tab_stop
			if next_tab_stop ~= 1 then
				doTabStop(next_tab_stop)
			end
			write(column.heading)
			if column.width then
				next_tab_stop = next_tab_stop + column.width
			end
		end
		print()

		return function(values)
			for _, column in ipairs(columns) do
				if column.tab_stop ~= 1 then
					doTabStop(column.tab_stop)
				end
				write(values[column.key])
			end
			print()
		end
	end,
}
