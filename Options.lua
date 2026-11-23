local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Guildon Groups's options in DonCore's shared options window (20.11.2026): which requests show a toast (one switch per
-- category, the level rule, do not disturb), how (sound, chat line, how long), and the window. The cog in the window's
-- header, /gng options and the Blizzard AddOns page open it. With the option blizzLook (on by default) and the game's
-- templates at login the same options are pages in the game's settings (DonCore Settings fullPages).
---------------------------------------------------------------------------
local Opt = LibStub("DonCore-1.0"):Get("Options", 2)

ns.OPTION_DEFAULTS = {
  dnd = false, levelFilter = true, roleFilter = true, role1 = "", role2 = "", toast_d = true, toast_r = true, toast_z = true, toast_q = true, toast_i = true, toast_t = true,
  sound = true, chatLine = true, toastSeconds = 12, postChat = true, minimapButton = true, blizzLook = true,
}

-- (23.11.2026, Daniel: "seine Rolle einstellen ... 2 Rollen, First und Second Spec") the roles of this character; db.role1
-- and db.role2 hold the logged in character's, db.roles all of them (Groups.lua LoadRoles, SaveRoles)
local function RoleOptions()
  local out = {}
  for _, k in ipairs(ns.ROLES) do out[#out + 1] = { k, k == "" and L["none"] or L[ns.ROLE_TEXT[k]] } end
  return out
end

local ITEMS = {
  { header = "My roles" },
  { key = "role1", name = "1st spec", kind = "dropdown", options = RoleOptions,
    tip = "The role of this character's first spec. The button I'm in offers it, and a dungeon request shows a toast while it has a free place." },
  { key = "role2", name = "2nd spec", kind = "dropdown", options = RoleOptions,
    tip = "The role of this character's second spec, if it has one. Both roles count for the toasts." },
  { key = "roleFilter", name = "Only dungeon groups with a place for my roles",
    tip = "A dungeon group has one tank, one healer and three damage dealers. Without a free place for your first or second role there is no toast. Raids, zones, quests, items and other requests always count. Without roles set nothing is left out." },
  { header = "Toasts" },
  { key = "dnd", name = "Do not disturb", tip = "No toasts, no sound and no chat line for new requests. The list still shows them. Also: /gng dnd" },
  { key = "levelFilter", name = "Only requests that suit my level",
    tip = "Dungeons from 3 levels under to 12 levels over the level of the last boss, zones around their level range. Quests, items and other requests always count." },
  { key = "toast_d", name = "Dungeons", tip = "A toast when a member looks for a group for a dungeon." },
  { key = "toast_r", name = "Raids", tip = "A toast when a member looks for a group for a raid." },
  { key = "toast_z", name = "Questing in a zone", tip = "A toast when a member looks for company to quest in a zone." },
  { key = "toast_q", name = "Quests", tip = "A toast when a member looks for help with a quest." },
  { key = "toast_i", name = "Items", tip = "A toast when a member looks for a group to get an item." },
  { key = "toast_t", name = "Other requests", tip = "A toast for requests with a free text." },
  { header = "How" },
  { key = "sound", name = "Sound with a toast", tip = "A short sound when a toast shows." },
  { key = "chatLine", name = "Chat line with a toast", tip = "One line in the chat, so the request can be read later." },
  { key = "toastSeconds", name = "A toast stays for", kind = "dropdown", tip = "A toast stays while the mouse is on it.",
    options = function() return { { 8, L["%d seconds"]:format(8) }, { 12, L["%d seconds"]:format(12) }, { 20, L["%d seconds"]:format(20) } } end },
  { kind = "button", optKey = "button:resetToast", name = "Reset toast position", button = "Reset",
    tip = "Puts the toast back to the top of the screen. Drag a toast to move it.", onClick = function() ns.db.toast = {} end },
  { header = "Window" },
  ns.LookOption({ addon = "Guildon Groups", category = "Guildon: Groups" }),
  { key = "minimapButton", name = "Minimap button", tip = "Shows the Guildon button at the minimap. All Guildon parts share it." },
  { kind = "button", optKey = "button:resetWindow", name = "Reset window position", button = "Reset",
    tip = "Puts the Guildon Groups window back in the middle of the screen at its first size.", onClick = function() if ns.ResetWindow then ns.ResetWindow() end end },
}

local TOAST_MAIN = { "role1", "role2", "roleFilter", "dnd", "levelFilter", "toast_d", "toast_r", "toast_z", "toast_q", "toast_i", "toast_t" }
local HOW_MAIN = { "sound", "chatLine", "toastSeconds", "button:resetToast" }
local WINDOW_MAIN = { "blizzLook", "minimapButton", "button:resetWindow" }

-- one change, from DonCore's window or the game's settings
local function Changed(key)
  if key == "minimapButton" then if ns.RefreshMinimapButton then ns.RefreshMinimapButton() end
  elseif key == "dnd" then ns.SetDND(ns.db.dnd) return
  elseif key == "blizzLook" then ns.LookChanged()
  elseif key == "role1" or key == "role2" then ns.SaveRoles() end
  if ns.Refresh then ns.Refresh() end
  if ns.RefreshSettingsUI then ns.SafeCall("settings", ns.RefreshSettingsUI) end
end

local function Status()
  local total, online, guildon = ns.MemberCounts()
  return { ("Guildon Groups %s"):format(tostring(ns.VERSION or "")),
    ns.InGuild() and L["%d members"]:format(total) .. ", " .. L["online: %d"]:format(online) .. ", " .. L["With Guildon Groups"] .. ": " .. guildon
      or L["You are not in a guild."],
    L["Open group requests: %d"]:format(ns.OpenRequestCount and ns.OpenRequestCount() or 0) }
end

local function Tools()
  return {
    { "Sync", "Ask now", function() if ns.Hello then ns.Hello(true) end ns.Print(L["Asked the guild for new data."]) end,
      "Asks the guild for new data now." },
    { "New request", "Open", function() if ns.ShowRequestForm then ns.ShowRequestForm() end end,
      "Look for a group in the guild: a dungeon, questing in a zone, a quest, an item or anything else." },
  }
end

local function Register()
  if not (Opt and Opt.Register) then return end
  local db = ns.db
  if ns.MinimapOption then
    for i, it in ipairs(ITEMS) do
      if it.key == "minimapButton" and not it.donCommon then ITEMS[i] = ns.MinimapOption({ name = it.name, tip = it.tip }) end
    end
  end
  for k, v in pairs(ns.OPTION_DEFAULTS) do if db[k] == nil then db[k] = v end end
  Opt.Register(ns.OPTIONS_ID, {
    name = "Guildon: Groups", order = 32, addon = "Guildon_Groups",
    tabs = {
      { key = "toasts", title = "Toasts", icon = "Interface\\Icons\\INV_Misc_GroupLooking",
        text = "Your roles and which group requests of the guild show a toast.", main = TOAST_MAIN },
      { key = "how", title = "How", icon = "Interface\\Icons\\INV_Misc_Bell_01",
        text = "Sound, chat line and how long a toast stays.", main = HOW_MAIN },
      { key = "window", title = "Window", icon = "Interface\\Icons\\INV_Misc_Note_01",
        text = "The look of the windows, the minimap button of all Guildon parts and the place of the window.", main = WINDOW_MAIN },
      { key = "tools", title = "Tools", text = "Status", status = true, tools = { "Sync", "New request" } },
    },
    pages = function() return { { items = ITEMS } } end,
    tools = Tools,
    db = function() return ns.db end,
    default = function(key) return ns.OPTION_DEFAULTS[key] end,
    changed = Changed,
    status = Status,
    help = function()
      local lines = {}
      for _, c in ipairs(ns.COMMANDS or {}) do lines[#lines + 1] = c[1] .. "  " .. L[c[2]] end
      return table.concat(lines, "\n")
    end,
    T = function(s) return L[s] end,
    labels = function(s) return L[s] end,
    redirect = function() return ns.OpenGameOptions and ns.OpenGameOptions() or false end,
  })
end

-- the option blizzLook changed: every window is built again in the other look (an open one at once)
function ns.LookChanged()
  if ns.WindowReset then ns.SafeCall("window look", ns.WindowReset) end
  if ns.FormReset then ns.SafeCall("form look", ns.FormReset) end
  if ns.CopyReset then ns.SafeCall("copy look", ns.CopyReset) end
  if ns.ToastReset then ns.SafeCall("toast look", ns.ToastReset) end
end

---------------------------------------------------------------------------
-- The game's settings: the same items as pages, built at login when the option blizzLook is on and the client has the
-- game's templates (else nothing there). A change of the option works for the options after a /reload.
---------------------------------------------------------------------------
local category, fullPages = nil, false

local function ItemOf(key)
  for _, it in ipairs(ITEMS) do if it.key == key or it.optKey == key then return it end end
end
local function PageItems(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = ItemOf(k) end
  return out
end

local function GamePages()
  return {
    { title = "Toasts", tip = "Your roles and which group requests of the guild show a toast.", items = PageItems(TOAST_MAIN) },
    { title = "How", tip = "Sound, chat line and how long a toast stays.", items = PageItems(HOW_MAIN) },
    { title = "Window", tip = "The look of the windows, the minimap button of all Guildon parts and the place of the window.",
      items = PageItems(WINDOW_MAIN) },
  }
end
ns.GameOptionPages = GamePages -- (tests)

local function BuildGameOptions()
  category, fullPages = nil, false
  if not (ns.BuildSettings and ns.db and ns.db.blizzLook ~= false and ns.LookKit and select(2, ns.LookKit())) then return end
  category = ns.BuildSettings({ name = "Guildon: Groups", ownWindow = true, fullPages = true,
    status = Status, tools = Tools(), pages = GamePages(),
    db = function() return ns.db end, default = function(key) return ns.OPTION_DEFAULTS[key] end, changed = Changed,
    T = function(s) return L[s] end })
  fullPages = category ~= nil
end
ns.BuildGameOptions = BuildGameOptions -- (tests)

-- true when the game's settings were opened at Guildon Groups
function ns.OpenGameOptions()
  if not (ns.db and ns.db.blizzLook ~= false and fullPages and category and Settings and Settings.OpenToCategory) then return false end
  if InCombatLockdown and InCombatLockdown() then ns.Print(L["Not in combat."]) return true end
  Settings.OpenToCategory(category:GetID())
  return true
end
function ns.OptionsLook() return fullPages and "game settings" or "don window" end

function ns.OpenOptions(tab)
  if Opt and Opt.Open then Opt.Open(ns.OPTIONS_ID, tab) return true end
end

ns.OnInit(function()
  ns.SafeCall("roles", ns.LoadRoles)
  ns.SafeCall("options", Register)
  ns.SafeCall("game options", BuildGameOptions)
end)
