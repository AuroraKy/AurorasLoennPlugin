
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
 local script = {
    parameters = -- if present, a new window will open when the user runs the script. Here, they can set parameters for the script
    {
        decalprefix = "objects/auroras_helper/dashsolid/dream", 
        ondecalprefix = "objects/auroras_helper/dashsolid/solid"
    },
}

function script.run(room, args, ctx)
    for _, entity in ipairs(room.entities) do
        if entity._name == "AurorasHelper/DashSolid" then
            print(dump(entity))
            local dirstr = entity["DIR"] == 0 and "UP" 
                    or entity["DIR"] == 1 and "RIGHT" 
                    or entity["DIR"] == 2 and "DOWN" 
                    or entity["DIR"] == 3 and "LEFT" 
            entity["TexturePath"] = args.decalprefix .. dirstr
            entity["OnTexturePath"] = args.ondecalprefix
        end
        --if entity._name == args.name and entity[args.attr] then 
        --    entity[args.attr] = entity[args.attr]:replace(args.from, args.to)
        --end
    end
end

return script