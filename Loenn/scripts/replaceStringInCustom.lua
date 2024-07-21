local script = {
    name = "String Replace in Entity/Trigger",
    displayName = "String Replace in Entity/Trigger",
    tooltip = "Can Replace an attribute in an entity/trigger, also dumps the entity to log if name matches",
    tooltips = {
        name = "Should equal the name you see at the top of the loenn window of the entity",
        attr = "Must equal the attribute name, case-sensitive.\nIf you get the name correct the log file will contain a table of attributes of that entity"
    },
    parameters = -- if present, a new window will open when the user runs the script. Here, they can set parameters for the script
    {
      from = "",
      to = "",
      name = "",
      attr = "",
      entities = true,
      triggers = false,
    },
    fieldOrder = {"name", "attr", "from", "to", "entities", "triggers"}
}

function dump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
 end

function string:replace(substring, replacement, n)
    return (self:gsub(substring:gsub("%p", "%%%0"), replacement:gsub("%%", "%%%%"), n))
end

function script.run(room, args, ctx)
    if args.entities then
        for _, entity in ipairs(room.entities) do
            if entity._name == args.name then
                print(dump(entity))
            end
            if entity._name == args.name and entity[args.attr] then 
                entity[args.attr] = entity[args.attr]:replace(args.from, args.to)
            end
        end
    end
    if args.triggers then
        for _, trigger in ipairs(room.triggers) do
            if trigger._name == args.name then
                print(dump(trigger))
            end
            if trigger._name == args.name and trigger[args.attr] then 
                trigger[args.attr] = trigger[args.attr]:replace(args.from, args.to)
            end
        end
    end
end

return script