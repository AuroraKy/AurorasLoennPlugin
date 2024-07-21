local maxTestedLoennVersion = require("utils.version_parser")("0.7.10")
local maxReasonableLoennVersion = require("utils.version_parser")("0.9")
local currentLoennVersion = require("meta").version
local logging = require("logging")

if currentLoennVersion >= maxReasonableLoennVersion then
    logging.error("Auroras's Loenn Plugin/decal_loading.lua NOT loaded, version is not under 0.8")
    return nil
elseif currentLoennVersion > maxTestedLoennVersion then
    logging.info("Auroras's Loenn Plugin/decal_loading.lua was loaded but this version has not been tested. (>0.7.10)")
end

local mods = require("mods")
local notifications = require("ui.notification")
local languageRegistry = require("language_registry")

local decals = require("decals")

local settings = mods.getModSettings()

local library = {}

if settings.cacheDecals == nil then
    settings.cacheDecals = false
end

library.cacheDecals = settings.cacheDecals


-- region reloadDecals code

library.ReloadDecalsOnce = {fg=true, bg=true}

local function reloadDecals()
  local language = languageRegistry.getLanguage()
  local text = tostring(language.ui.menubar.aurora_aquir_AurorasLoennPlugin_LoadDecalsNotify)

  library.ReloadDecalsOnce.fg = true
  library.ReloadDecalsOnce.bg = true
  notifications.notify(text)
end

local fg_cache = nil
local bg_cache = nil

if not decals.hooked_by_aurora_AurorasLoennPlugin_Cachedecal then
    decals.hooked_by_aurora_AurorasLoennPlugin_Cachedecal = true
    local orig_decals_getPlacements = decals.getPlacements
    function decals.getPlacements(layer, specificMods)
        if not library.cacheDecals or (layer ~= "decalsFg" and layer ~= "decalsBg") then
            return orig_decals_getPlacements(layer, specificMods)
        end

        logging.warning("hi")
        if layer == "decalsFg" then

          if library.ReloadDecalsOnce.fg or not fg_cache then
              fg_cache = orig_decals_getPlacements(layer, specificMods)
              library.ReloadDecalsOnce.fg = false
          end

        elseif layer == "decalsBg" then 

          if library.ReloadDecalsOnce.bg or not bg_cache then
              bg_cache = orig_decals_getPlacements(layer, specificMods)
              library.ReloadDecalsOnce.bg = false
          end

        end

        return layer == "decalsFg" and fg_cache or bg_cache
    end
end

-- endregion reloadDecals code
-- region ui setup 

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

local function button(menu, lang, func)
  local item = $(menu):find(item -> item[1] == lang)
  if not item then
    item = {}
    table.insert(menu, item)
  end
  item[1] = lang
  item[2] = func
end


local function injectMenuItems()
    local menubar = require("ui.menubar").menubar
    local viewMenu = $(menubar):find(menu -> menu[1] == "view")[2]
    checkbox(viewMenu, "aurora_aquir_AurorasLoennPlugin_LoadDecalsOnce",
                function()
                    library.cacheDecals = not library.cacheDecals
                    settings.cacheDecals = library.cacheDecals
                end,
                function() return library.cacheDecals end)
                
    button(viewMenu, "aurora_aquir_AurorasLoennPlugin_LoadDecals", reloadDecals)
end

injectMenuItems()

-- regionend ui setup


return library