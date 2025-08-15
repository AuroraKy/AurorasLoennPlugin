local supportedUntilLoennVersion = require("utils.version_parser")("1.1")
local currentLoennVersion = require("meta").version

if supportedUntilLoennVersion <= currentLoennVersion then
    return nil
end

local mods = require("mods")
local settings = mods.getModSettings()

local SidebarSize = {}

if settings.maxCharsSidebar == nil then
    settings.maxCharsSidebar = 45
end

if settings.restrictSidebarSize == nil then
    settings.restrictSidebarSize = false
end

SidebarSize.restrictSidebarSize = settings.restrictSidebarSize

-- copied from AnotherLoenTool lol thanks!!!
local function checkbox(menu, lang, toggle, active)
  local item = $(menu):find(item -> item[1] == lang)
  if not item then
    item = {}
    table.insert(menu, item)
  end
  item[1] = lang
  item[2] = toggle
  item[3] = "checkbox"
  item[4] = active
end


local function injectCheckboxes()
    local menubar = require("ui.menubar").menubar
    local viewMenu = $(menubar):find(menu -> menu[1] == "edit")[2]
    checkbox(viewMenu, "aurora_aquir_AurorasLoennPlugin_restrict_sidebar_size",
                function()
                    SidebarSize.restrictSidebarSize = not SidebarSize.restrictSidebarSize
                    settings.restrictSidebarSize = SidebarSize.restrictSidebarSize
                end,
                function() return SidebarSize.restrictSidebarSize end)
end

injectCheckboxes()

local listWidgets = require("ui.widgets.lists")

if not listWidgets.hooked_by_aurora_lmao then
    listWidgets.hooked_by_aurora_lmao = true
    local orig_updateItems = listWidgets.updateItems
    function listWidgets.updateItems(list, items, target, fromFilter, preventCallback, callbackRequiresChange)
        if SidebarSize.restrictSidebarSize then
            for _, item in ipairs(items) do
                if type(item.text) == "string" and string.len(item.text) > settings.maxCharsSidebar then
                    if not item.tooltipText then item.tooltipText = item.text end
                    item.text = string.sub(item.text, 1, settings.maxCharsSidebar) .. "..."
                end
            end
        end
        return orig_updateItems(list, items, target, fromFilter, preventCallback, callbackRequiresChange)
    end
end


return SidebarSize