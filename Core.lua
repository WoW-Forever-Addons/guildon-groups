local addonName, ns = ...
local L = ns.L
ns.Style = LibStub("DonCore-1.0"):Get("Style", 4):ForAddon() -- DonCore's Style for texts (Hex, Number, Wordmark, tooltips); the windows are built from DonCore's Kit
LibStub("DonCore-1.0"):Get("Settings", 1):Attach(addonName, ns) -- the pages in the game's settings with the option blizzLook (Options.lua)

---------------------------------------------------------------------------
-- Guildon Groups (20.11.2026, wish of Elmer Fudd in the guild's Discord: group requests get lost in the guild chat): a
-- group finder inside the guild. A member posts a request (a dungeon, questing in a zone, a quest, an item, free text; now
-- or at a date and time), every member with this part sees it in the list and, when it suits him, as a small toast; "I'm in"
-- tells the creator, who invites with one click. Requests run out by themselves and close when the creator enters an
-- instance. No server: the sets "lfg" (own requests) and "lfgj" (what I joined) travel through GuildShared/Comm.lua.
-- Own frames only: no hooksecurefunc, no HookScript, no Blizzard frame scripts.
-- Error guard, events, saved table and helpers are in Shared/Base.lua (GuildShared/), loaded right after this file.
---------------------------------------------------------------------------
ns.defaults = {
  window = {},         -- place and size of the window (DonCore Kit.Window's store)
  tab = "groups",      -- last open tab
  sets = {},           -- shared data sets, key "<kind>:<owner>" (Comm.lua)
  peers = {},          -- Guildon Groups users seen: full name -> { v = version, t = time() }
  seen = {},           -- requests already announced to the player: key -> time()
  toast = {},          -- place of the toast
}
ns.SCHEMA = 1
ns.WORDMARK = "|cff3fa9f5Guil|rdon Groups"
-- own prefix per game version, so Forever and Era data never mix
ns.PREFIX = ns.ERA and "GuildonGroupsEra" or "GuildonGroups"

ns.DBNAME = "GuildonGroupsDB"
ns.ERROR_HINT = "an error occurred, /gng diag for details"
ns.ADDON_TITLE = "Guildon Groups"

-- this part has no example guild (GuildShared/Comm.lua asks)
function ns.IsDemo() return false end

-- the clock all members share: the server's, else the PC's
function ns.Now()
  return ns.Num(ns.Call(GetServerTime)) or time()
end

-- the one place that picks the blocks of the windows: DonCore's Kit, or with the option blizzLook (on by default) the same
-- blocks from the game's own templates (DonCore Blizz). Returns kit, isBlizzard, reason.
function ns.LookKit()
  local Core = LibStub("DonCore-1.0")
  local Kit = Core:Get("Kit", 4)
  if not (ns.db and ns.db.blizzLook ~= false) then return Kit, false, "option off" end
  local Bz = Core:Get("Blizz", 5)
  if not Bz then return Kit, false, "no DonCore Blizz" end
  local kit, miss = Bz.Kit()
  if kit then return kit, true end
  return Kit, false, "missing: " .. tostring(miss)
end
-- a window that failed in the game's look and was built with the Kit: noted for /gng diag, one chat line per session
local lookErrors, said = {}, false
function ns.LookFailed(what, err)
  lookErrors[#lookErrors + 1] = tostring(what) .. ": " .. tostring(err)
  if said or not ns.Print then return end
  said = true
  ns.Print(L["The window could not be built in the game's look, it opens in the Don look. %s says why."]:format("/gng diag"))
end
function ns.LookNote()
  local _, blizz, why = ns.LookKit()
  return blizz and "blizzard" or ("kit (" .. tostring(why) .. ")"), lookErrors
end
function ns.Blizz() return LibStub("DonCore-1.0"):Get("Blizz", 5) end

-- one of the Guildon parts: its entry at the shared minimap button (Shared/Launcher.lua), with the open requests
ns.MODULE = { id = "groups", title = "Guildon: Groups", icon = "Interface\\Icons\\INV_Misc_GroupLooking", order = 3 }
function ns.LauncherTip()
  local lines = {}
  local n = ns.OpenRequestCount and ns.OpenRequestCount() or 0
  if n > 0 then lines[#lines + 1] = L["Open group requests: %d"]:format(n) end
  if ns.db and ns.db.dnd then lines[#lines + 1] = L["Do not disturb is on: no toasts."] end
  return #lines > 0 and lines or nil
end

function ns.DiagExtra(out)
  out = out or print
  local note, errs = ns.LookNote()
  out(("  look: window %s, others %s%s"):format(ns.WindowLook and tostring(ns.WindowLook()) or "?", note,
    #errs > 0 and (", failed: " .. table.concat(errs, "; ")) or ""))
  local Opt = LibStub("DonCore-1.0"):Get("Options", 8); if Opt and Opt.Look then out("  options: " .. tostring(Opt.Look())) end -- (24.11.2026) the look of the options window
  if ns.GroupsDiag then ns.GroupsDiag(out) end
end

---------------------------------------------------------------------------
-- Copy box (DonCore's Kit.ShowCopy, in the game's look with the option blizzLook): /gng diag and the text for Discord
---------------------------------------------------------------------------
local copyKit
function ns.ShowCopyBox(title, hint, text)
  local words = { selectAll = L["Select all"], close = L["Close"] }
  local K = ns.LookKit and ns.LookKit() or ns.Kit
  if K ~= ns.Kit then
    local ok, d = pcall(K.ShowCopy, title, hint, text, words)
    if ok and d then copyKit = K return d end
    local Bz = ns.Blizz and ns.Blizz()
    if Bz and Bz._copy and Bz._copy.Hide then pcall(Bz._copy.Hide, Bz._copy) end
    if ns.LookFailed then ns.LookFailed("copy box", ok and "no box" or d) end
  end
  copyKit = ns.Kit
  return ns.Kit.ShowCopy(title, hint, text, words)
end
function ns.CopyBox()
  if copyKit and copyKit ~= ns.Kit then local Bz = ns.Blizz and ns.Blizz() return Bz and Bz._copy end
  return ns.Kit._copy
end
function ns.CopyReset()
  local d = ns.CopyBox()
  if d and d.Hide then d:Hide() end
end

-- the diag lines as plain text (colours and links taken out) for the copy box
function ns.DiagLines()
  local lines = {}
  local function add(s)
    lines[#lines + 1] = (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"))
  end
  if not ns.PrintDiag then return lines end
  local ok, err = pcall(ns.PrintDiag, add)
  if not ok then add("  diag error: " .. tostring(err)) end
  return lines
end
function ns.ShowDiag()
  local ok, lines = pcall(ns.DiagLines)
  if ok and #lines > 0 then
    local shown, d = pcall(ns.ShowCopyBox, ns.ADDON_TITLE .. " diag", L["Ctrl+A selects all, Ctrl+C copies."], table.concat(lines, "\n"))
    if shown and d then return d end
  end
  if ns.PrintDiag then ns.PrintDiag() end
end

function GuildonGroups_OnAddonCompartmentClick()
  if ns.ToggleWindow then ns.ToggleWindow() end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_GUILDONGROUPS1 = "/gng"
SLASH_GUILDONGROUPS2 = "/guildongroups"
ns.COMMANDS = {
  { "/gng", "show or hide the window" },
  { "/gng new", "post a new group request" },
  { "/gng dnd", "do not disturb: toasts on or off" },
  { "/gng options", "all settings (also the cog in the window)" },
  { "/gng sync", "ask the guild for new data now" },
  { "/gng diag", "state of the exchange and errors" },
  { "/gng help", "this list" },
}

function ns.PrintHelp()
  ns.Print(L["Commands:"])
  for _, c in ipairs(ns.COMMANDS) do print("  |cffebebeb" .. c[1] .. "|r  |cff9ea3ad" .. L[c[2]] .. "|r") end
end

function ns.Slash(msg)
  msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  if msg == "" or msg == "show" or msg == "toggle" then
    if ns.ToggleWindow then ns.ToggleWindow() end
  elseif msg == "new" or msg == "neu" then
    if ns.ShowRequestForm then ns.ShowRequestForm() end
  elseif msg == "dnd" or msg == "dnd on" or msg == "dnd off" then
    if ns.SetDND then ns.SetDND(msg == "dnd on" and true or (msg == "dnd off" and false or not ns.db.dnd), true) end
  elseif msg == "options" or msg == "optionen" or msg == "config" then
    if not (ns.OpenOptions and ns.OpenOptions()) then ns.Print(L["The options window is missing (DonCore)."]) end
  elseif msg == "sync" then
    if ns.Hello then ns.Hello(true) end
    ns.Print(L["Asked the guild for new data."])
  elseif msg == "diag" then
    ns.ShowDiag()
  elseif msg == "diag chat" then
    if ns.PrintDiag then ns.PrintDiag() end
  elseif msg == "help" or msg == "?" or msg == "hilfe" then
    ns.PrintHelp()
  else
    ns.Print(L["Unknown command: %s"]:format(msg))
    ns.PrintHelp()
  end
end

SlashCmdList["GUILDONGROUPS"] = function(msg) ns.SafeCall("slash", ns.Slash, msg) end
