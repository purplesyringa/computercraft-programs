local ru = require "ru"

while true do
    local inp = read()
    if inp == "" then
        break
    end
    print("to koi:", ru.text.to_koi(inp))
    print("to text:", ru.koi.to_text(inp))
end
