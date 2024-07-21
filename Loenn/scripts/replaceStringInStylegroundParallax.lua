local loadedState = require("loaded_state")

local script = {
    name = "String Replace in Parallax texture",
	displayName = "String Replace in Parallax texture",
    parameters = -- if present, a new window will open when the user runs the script. Here, they can set parameters for the script
    {
      from = "",
      to = "",
      fg = true,
      bg = true
    },
    fieldOrder = {"from", "to", "fg", "bg"}
}

function string:replace(substring, replacement, n)
    return (self:gsub(substring:gsub("%p", "%%%0"), replacement:gsub("%%", "%%%%"), n))
end

function script.run(room, args, ctx)
    if args.fg then
        for _, styleFg in ipairs(loadedState.map.stylesFg) do
            if styleFg.texture then styleFg.texture = styleFg.texture:replace(args.from, args.to) end
        end
    end
    if args.bg then
        for _, styleBg in ipairs(loadedState.map.stylesBg) do
            if styleBg.texture then styleBg.texture = styleBg.texture:replace(args.from, args.to) end
        end
    end
end

return script