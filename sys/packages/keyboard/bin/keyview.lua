while true do
    local event, key, is_repeat = os.pullEvent()
    if event == "key" then
        print(("+%s %s %s"):format(keys.getName(key), key, is_repeat and "rep" or ""))
    elseif event == "key_up" then
        print(("-%s %s"):format(keys.getName(key), key))
    elseif event == "char" then
        print((" %s %s"):format(key, string.byte(key)))
    end
end
