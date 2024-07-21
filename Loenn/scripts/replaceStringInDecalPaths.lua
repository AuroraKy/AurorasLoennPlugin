local script = {
    name = "String Replace in decal paths",
	displayName = "String Replace in decal paths",
    parameters = -- if present, a new window will open when the user runs the script. Here, they can set parameters for the script
    {
      from = "",
      to = "",
      fg = true,
      bg = true,
    },
    fieldOrder = {"from", "to", "fg", "bg"}
}


function string:replace(substring, replacement, n)
    return (self:gsub(substring:gsub("%p", "%%%0"), replacement:gsub("%%", "%%%%"), n))
end

function script.run(room, args, ctx)
    local from = args.from or ""
    local to = args.to or ""
    if args.fg then
        for _, fgdecals in ipairs(room.decalsFg) do
            fgdecals.texture = fgdecals.texture:replace(from, to)
        end
    end
    if args.bg then
        for _, bgdecals in ipairs(room.decalsBg) do
            bgdecals.texture = bgdecals.texture:replace(from, to)
        end
    end
end

return script