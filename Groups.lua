local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- Group requests: the data and their rules (20.11.2026).
-- Set "lfg" of a member: his open requests, "<id>,<cat>,<ref>,<n|s>,<when>,<created>,<need>,<role>,<look>,<note>" joined by ";", or "-"
-- for none (an empty set cannot travel). cat: d dungeon (ref = instanceID of Data/Dungeons.lua), z questing in a zone
-- (ref = uiMapID), q quest (questID), i item (itemID), t free text (ref 0). n = now, s = at the time <when> (the server's
-- clock, seconds). need = players still wanted (0 = not said). role = what the creator plays (t, h, d or empty). The note is
-- cleaned text (ns.CleanNote).
-- Set "lfgj" of a member: the requests he joined, "<owner>#<id>,<role>,<look>" joined by ";", or "-"; role t, h, d or empty.
-- (23.11.2026, Daniel: "ein Charakterbild ... darf nicht so viele Daten fressen") look = race and sex of the character
-- ("3m", DonCore Art LookCode, empty when unknown): two or three characters in the sets that travel anyway, no message
-- of its own; the picture itself is the client's (Art.RaceIcon).
-- A request runs out NOW_TTL after it was made (now) or PLAN_TTL after its time (planned): nobody has to clean up, and a
-- set of a member who went offline stops counting by itself. The creator's dungeon requests that are due close when he
-- enters an instance (Elmer Fudd: "damit keine Terminleichen übrig bleiben"); he can close, renew and change them himself.
-- Received data are data, never code: both kinds are checked field by field (validate).
---------------------------------------------------------------------------
ns.CATS = { "d", "z", "q", "i", "t" }
ns.CAT_TEXT = { d = "Dungeon", z = "Questing in a zone", q = "Quest", i = "Item", t = "Other" }
ns.CAT_SHORT = { d = "Dungeons", z = "Zones", q = "Quests", i = "Items", t = "Other" }
ns.CAT_ICON = {
  d = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", z = "Interface\\Icons\\INV_Misc_Map_01",
  q = "Interface\\Icons\\INV_Misc_Book_08", i = "Interface\\Icons\\INV_Misc_Bag_08", t = "Interface\\Icons\\INV_Misc_GroupLooking",
}
local RAID_ICON = "Interface\\Icons\\INV_Misc_Head_Dragon_01"
ns.ROLES = { "", "t", "h", "d" }
ns.ROLE_TEXT = { [""] = "Any role", t = "Tank", h = "Healer", d = "Damage" }
ns.Art = LibStub("DonCore-1.0"):Get("Art", 1)
function ns.MyLook() return ns.Art and ns.Art.LookCode() or "" end
local function CleanLook(v) v = tostring(v or "") return v:match("^%d%d?%d?[mf]$") and v or "" end
local NOW_TTL, PLAN_TTL = 45 * 60, 2 * 3600
local DUE = 15 * 60          -- a planned dungeon request counts as due this long before its time (entering an instance closes it)
local PLAN_MAX = 30 * 86400  -- a request cannot be planned further ahead
ns.MAX_OWN, ns.MAX_JOIN, ns.NOTE_MAX = 5, 10, 80
ns.NOW_TTL, ns.PLAN_TTL = NOW_TTL, PLAN_TTL

-- free text as it travels: no colour codes or links, none of the separators, one line, at most NOTE_MAX bytes (a cut never
-- splits a character of several bytes)
function ns.CleanNote(s)
  s = tostring(s or ""):gsub("|", ""):gsub("[%c;,:#~]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if #s > ns.NOTE_MAX then s = s:sub(1, ns.NOTE_MAX):gsub("[\192-\255]?[\128-\191]*$", ""):gsub(" $", "") end
  return s
end

local function Expires(r) return r.now and (r.created + NOW_TTL) or (r.when + PLAN_TTL) end

local function Encode(list)
  local out = {}
  for _, r in ipairs(list) do
    out[#out + 1] = table.concat({ r.id, r.cat, r.ref or 0, r.now and "n" or "s", r.when, r.created, r.need or 0, r.role or "", CleanLook(r.look), ns.CleanNote(r.note) }, ",")
  end
  return #out > 0 and table.concat(out, ";") or "-"
end

-- the requests of one set as a list, nil when the text is not a set of requests
function ns.DecodeRequests(d)
  if type(d) ~= "string" or #d > 2000 then return nil end
  local out = {}
  if d == "-" then return out end
  for e in (d .. ";"):gmatch("([^;]*);") do
    local id, cat, ref, kind, when, created, need, role, look, note = e:match("^(%d+),([dzqit]),(%d+),([ns]),(%d+),(%d+),(%d+),([thd]?),(%d*[mf]?),([^,]*)$")
    if not id or #out >= ns.MAX_OWN or #look > 4 or #id > 7 or #ref > 9 or #when > 11 or #created > 11 or #need > 2 or #note > ns.NOTE_MAX then return nil end
    out[#out + 1] = { id = tonumber(id), cat = cat, ref = tonumber(ref), now = kind == "n", when = tonumber(when),
      created = tonumber(created), need = tonumber(need), role = role, look = CleanLook(look), note = ns.CleanNote(note) }
  end
  return out
end

local function EncodeJoins(map)
  local keys = {}
  for k in pairs(map) do keys[#keys + 1] = k end
  table.sort(keys)
  local look = CleanLook(ns.MyLook())
  for i, k in ipairs(keys) do keys[i] = k .. "," .. map[k] .. "," .. look end
  return #keys > 0 and table.concat(keys, ";") or "-"
end

-- the joins of one set as key -> role, nil when the text is not a set of joins; second value: the joiner's look
function ns.DecodeJoins(d)
  if type(d) ~= "string" or #d > 2000 then return nil end
  local out, n, look = {}, 0, ""
  if d == "-" then return out, look end
  for e in (d .. ";"):gmatch("([^;]*);") do
    local owner, id, role, lk = e:match("^([^,#]+)#(%d+),([thd]?),?(%d*[mf]?)$")
    n = n + 1
    if not owner or n > ns.MAX_JOIN or #id > 7 or #owner > 60 or #lk > 4 then return nil end
    out[owner .. "#" .. tonumber(id)] = role
    if lk ~= "" then look = CleanLook(lk) end
  end
  return out, look
end

---------------------------------------------------------------------------
-- All open requests of the guild, with who joined
---------------------------------------------------------------------------
local cache, byKey

function ns.InvalidateRequests() cache, byKey = nil, nil end

function ns.Requests()
  if cache then return cache end
  local now, me = ns.Now(), ns.MyName()
  local list, map = {}, {}
  for _, s in ipairs(ns.SetsOf("lfg")) do
    if s.o == me or ns.IsMember(s.o) then
      for _, r in ipairs(ns.DecodeRequests(s.d) or {}) do
        r.owner, r.key, r.expires = s.o, s.o .. "#" .. r.id, Expires(r)
        r.start = r.now and r.created or r.when
        r.mine = s.o == me
        if r.expires > now then
          r.joiners = {}
          list[#list + 1] = r
          map[r.key] = r
        end
      end
    end
  end
  for _, s in ipairs(ns.SetsOf("lfgj")) do
    if s.o == me or ns.IsMember(s.o) then
      local joins, look = ns.DecodeJoins(s.d)
      for key, role in pairs(joins or {}) do
        local r = map[key]
        if r and s.o ~= r.owner then r.joiners[#r.joiners + 1] = { name = s.o, role = role, look = look } end
      end
    end
  end
  for _, r in ipairs(list) do table.sort(r.joiners, function(a, b) return a.name < b.name end) end
  -- soonest first: what runs now, then the planned ones by their time
  table.sort(list, function(a, b)
    if a.now ~= b.now then return a.now end
    if a.start ~= b.start then
      if a.now then return a.start > b.start end
      return a.start < b.start
    end
    return a.key < b.key
  end)
  cache, byKey = list, map
  return list
end

-- the group of a request as it stands (Daniel 20.11.2026: "oben Tank, als zweites Healer und dann die 3 DDs"): the creator
-- and everyone who joined, tanks first, then healers, then damage, then members who said no role; by name inside a role.
-- Each: { name, role, owner = true for the creator }
local ROLE_ORDER = { t = 1, h = 2, d = 3, [""] = 4 }
function ns.GroupOf(r)
  local out = { { name = r.owner, role = r.role or "", owner = true, look = r.look or "" } }
  for _, j in ipairs(r.joiners or {}) do out[#out + 1] = { name = j.name, role = j.role or "", look = j.look or "" } end
  table.sort(out, function(a, b)
    local x, y = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
    if x ~= y then return x < y end
    return a.name < b.name
  end)
  return out
end

function ns.Request(key)
  if not key then return nil end
  ns.Requests()
  return byKey[key]
end

function ns.OpenRequestCount() return #ns.Requests() end

-- my role in a request I joined ("" = any), nil when I did not join
function ns.Joined(key)
  local me = ns.MyName()
  local s = me and ns.GetSet("lfgj", me)
  local map = s and ns.DecodeJoins(s.d) or {}
  return map[key]
end

---------------------------------------------------------------------------
-- My roles (Daniel 23.11.2026: "seine Rolle einstellen ... auch 2 Rollen, First und Second Spec, und dass man dann auch
-- nur für die Rolle die Toasts bekommt"): per character in db.roles["Name-Realm"] = "<first><second>" (t, h, d or "-"),
-- shown as the options role1 and role2 (ns.LoadRoles copies them in after the login, ns.SaveRoles back).
-- A dungeon group (not a raid) has one tank, one healer and three damage dealers: a request fits my roles when one of
-- them still has a free place there; other requests always fit (they have no places).
---------------------------------------------------------------------------
local SLOT_N = { t = 1, h = 1, d = 3 }
local function Role(v) return (v == "t" or v == "h" or v == "d") and v or "" end
function ns.MyRoles()
  local db = ns.db or {}
  local a, b = Role(db.role1), Role(db.role2)
  if a == "" then a, b = b, "" end
  if b == a then b = "" end
  return a, b
end
function ns.SaveRoles()
  local me, db = ns.MyName(), ns.db
  if not (me and db) then return end
  db.roles = type(db.roles) == "table" and db.roles or {}
  local a, b = Role(db.role1), Role(db.role2)
  db.roles[me] = (a ~= "" or b ~= "") and ((a ~= "" and a or "-") .. (b ~= "" and b or "-")) or nil
end
function ns.LoadRoles()
  local me, db = ns.MyName(), ns.db
  if not (me and db) then return end
  local v = type(db.roles) == "table" and db.roles[me]
  if type(v) ~= "string" and Role(db.myRole) ~= "" then v = db.myRole .. "-" end -- the one role of 0.1.0
  v = type(v) == "string" and v or ""
  db.role1, db.role2 = Role(v:sub(1, 1)), Role(v:sub(2, 2))
end

-- the free places of a dungeon group per role, nil for any other request
function ns.FreeSlots(r)
  if not (r and r.cat == "d" and not ns.IsRaid(r.ref)) then return nil end
  local free = { t = SLOT_N.t, h = SLOT_N.h, d = SLOT_N.d }
  for _, m in ipairs(ns.GroupOf(r)) do
    if free[m.role] then free[m.role] = free[m.role] - 1 end
  end
  return free
end

-- the roles I could join as: my first and second role that still have a free place (all of them for a request without
-- places); fits = false when I set roles and none of them is free
function ns.RolesFor(r)
  local a, b = ns.MyRoles()
  if a == "" then return {}, true end
  local free, out = ns.FreeSlots(r), {}
  for _, x in ipairs({ a, b }) do
    if x ~= "" and (not free or free[x] > 0) then out[#out + 1] = x end
  end
  return out, #out > 0
end
function ns.RoleFits(r) local _, fits = ns.RolesFor(r) return fits end
-- the role "I'm in" takes when none is named: the first one with a free place, else my first one
function ns.PickRole(r)
  local list = ns.RolesFor(r)
  if list[1] then return list[1] end
  return (ns.MyRoles())
end

---------------------------------------------------------------------------
-- Names, icons, times, levels
---------------------------------------------------------------------------
local function MapName(map)
  if not (map and map > 0 and C_Map) then return nil end
  local info = ns.Call(C_Map.GetMapInfo, map)
  return type(info) == "table" and ns.Str(info.name) or nil
end

function ns.DungeonName(id)
  local d = ns.DUNGEONS[id]
  if not d then return L["Dungeon %d"]:format(id or 0) end
  return MapName(d[5]) or d[1]
end
function ns.IsRaid(id) local d = ns.DUNGEONS[id] return d ~= nil and d[4] == 1 end
-- (23.11.2026, Daniel: "für die Dungeon-Auswahl ... die ganzen Blizzard-Bilder") the client's picture of the instance
function ns.DungeonIcon(id)
  local d = ns.DUNGEONS[id]
  if not (d and ns.Art) then return nil end
  return (ns.Art.DungeonIcon(id, { MapName(d[5]), d[1] }))
end

function ns.ZoneName(id)
  return MapName(id) or (ns.ZONES[id] and ns.ZONES[id][1]) or L["Zone %d"]:format(id or 0)
end

function ns.QuestName(id)
  local name = C_QuestLog and (ns.Str(ns.Call(C_QuestLog.GetTitleForQuestID, id)) or ns.Str(ns.Call(C_QuestLog.GetQuestInfo, id)))
  return name or L["Quest %d"]:format(id or 0), name ~= nil
end

function ns.ItemName(id)
  local name = ns.Str(ns.Call(C_Item and C_Item.GetItemInfo or GetItemInfo, id))
  return name or L["Item %d"]:format(id or 0), name ~= nil
end
local function ItemIcon(id)
  local icon = ns.Call(C_Item and C_Item.GetItemIconByID or GetItemIcon, id)
  return ns.Usable(icon) and icon or nil
end

-- title, icon, itemID (the mouse shows the item's tooltip)
function ns.RequestTitle(r)
  if r.cat == "d" then return ns.DungeonName(r.ref), ns.DungeonIcon(r.ref) or (ns.IsRaid(r.ref) and RAID_ICON or ns.CAT_ICON.d) end
  if r.cat == "z" then return L["Questing: %s"]:format(ns.ZoneName(r.ref)), ns.CAT_ICON.z end
  if r.cat == "q" then return L["Quest: %s"]:format((ns.QuestName(r.ref))), ns.CAT_ICON.q end
  if r.cat == "i" then return L["Item: %s"]:format((ns.ItemName(r.ref))), ItemIcon(r.ref) or ns.CAT_ICON.i, r.ref end
  return r.note ~= "" and r.note or L["Group request"], ns.CAT_ICON.t
end

-- the level range a request suits: lo, hi (hi nil = no upper end); nothing = no level rule
-- Dungeon (Elmer Fudd 20.11.2026): 3 under to 12 over the boss level, and never narrower than the dungeon's own range (a
-- dungeon with wings starts far under its last boss). Raid: from its level. Zone: 2 under to 4 over the zone's range.
function ns.LevelRange(r)
  if r.cat == "d" then
    local d = ns.DUNGEONS[r.ref]
    if not d then return nil end
    if d[4] == 1 then return d[2], nil end
    return math.max(1, math.min(d[6] - 3, d[2])), math.max(d[6] + 12, d[3])
  elseif r.cat == "z" then
    local z = ns.ZONES[r.ref]
    if z then return math.max(1, z[2] - 2), z[3] + 4 end
  end
  return nil
end
function ns.LevelFits(r, level)
  local lo, hi = ns.LevelRange(r)
  if not lo or not level then return true end
  return level >= lo and (not hi or level <= hi)
end
function ns.MyLevel() return ns.Num(ns.Call(UnitLevel, "player")) or 0 end

local DAYS = { "WEEKDAY_SUNDAY", "WEEKDAY_MONDAY", "WEEKDAY_TUESDAY", "WEEKDAY_WEDNESDAY", "WEEKDAY_THURSDAY", "WEEKDAY_FRIDAY", "WEEKDAY_SATURDAY" }
local DAYS_EN = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
function ns.DayName(wday) return ns.Str(_G[DAYS[wday] or ""]) or DAYS_EN[wday] or "?" end
local function SameDay(a, b) return date("%Y%m%d", a) == date("%Y%m%d", b) end

-- "now", "today 20:30", "tomorrow 20:30", "Saturday 21.11. 20:30"
function ns.WhenText(r)
  if r.now then return L["now"] end
  local now = ns.Now()
  local clock = date("%H:%M", r.when)
  if SameDay(r.when, now) then return L["today %s"]:format(clock) end
  if SameDay(r.when, now + 86400) then return L["tomorrow %s"]:format(clock) end
  return ("%s %s %s"):format(ns.DayName(tonumber(date("%w", r.when)) + 1), date(L["%m/%d"], r.when), clock)
end

-- "12 min left" for a running request, "starts in 2 h" for a planned one
function ns.LeftText(r)
  local now = ns.Now()
  local function Span(sec)
    sec = math.max(0, sec)
    if sec < 3600 then return L["%d min"]:format(math.ceil(sec / 60)) end
    if sec < 2 * 86400 then return L["%d h"]:format(math.floor(sec / 3600 + 0.5)) end
    return L["%d days"]:format(math.floor(sec / 86400 + 0.5))
  end
  if not r.now and r.when > now then return L["starts in %s"]:format(Span(r.when - now)) end
  return L["%s left"]:format(Span(Expires(r) - now))
end

---------------------------------------------------------------------------
-- My own requests
---------------------------------------------------------------------------
local function Own()
  local me = ns.MyName()
  local s = me and ns.GetSet("lfg", me)
  local list, now, out = s and ns.DecodeRequests(s.d) or {}, ns.Now(), {}
  for _, r in ipairs(list) do if Expires(r) > now then out[#out + 1] = r end end
  return out, #out ~= #list
end

local function Changed()
  ns.InvalidateRequests()
  if ns.OnDataChanged then ns.OnDataChanged() end
end

local function Publish(list)
  local ok = ns.SetOwn("lfg", Encode(list))
  Changed()
  return ok
end

-- the request, or nil and why: "name" (not logged in yet), "guild", "full", "bad" (what is asked for), "time", "text"
-- when: nil = now, else the time on the server's clock; role: what the creator plays (t, h, d, or empty)
function ns.AddRequest(cat, ref, when, need, note, role)
  if not ns.MyName() then return nil, "name" end
  if not ns.InGuild() then return nil, "guild" end
  ref, need, note = tonumber(ref) or 0, math.floor(tonumber(need) or 0), ns.CleanNote(note)
  if not ns.CAT_TEXT[cat or ""] or ref < 0 or ref ~= math.floor(ref) or ref > 999999999 then return nil, "bad" end
  if cat == "d" and not ns.DUNGEONS[ref] then return nil, "bad" end
  if (cat == "z" or cat == "q" or cat == "i") and ref == 0 then return nil, "bad" end
  if cat == "t" then
    ref = 0
    if note == "" then return nil, "text" end
  end
  if need < 0 or need > 39 then need = 0 end
  if role == nil then role = (ns.MyRoles()) end
  role = (role == "t" or role == "h" or role == "d") and role or ""
  local now = ns.Now()
  if when ~= nil then
    when = math.floor(tonumber(when) or 0)
    if when < now - 60 or when > now + PLAN_MAX then return nil, "time" end
  end
  local list = Own()
  if #list >= ns.MAX_OWN then return nil, "full" end
  ns.db.nextId = (tonumber(ns.db.nextId) or 0) % 9000000 + 1
  local r = { id = ns.db.nextId, cat = cat, ref = ref, now = when == nil, when = when or now, created = now, need = need, role = role, look = ns.MyLook(), note = note }
  list[#list + 1] = r
  if not Publish(list) then return nil, "name" end
  return ns.Request(ns.MyName() .. "#" .. r.id) or r
end

function ns.CloseRequest(id)
  local list, out = Own(), {}
  for _, r in ipairs(list) do if r.id ~= id then out[#out + 1] = r end end
  if #out == #list then return false end
  Publish(out)
  return true
end

-- a request for "now" runs again from this moment
function ns.RenewRequest(id)
  local list = Own()
  for _, r in ipairs(list) do
    if r.id == id and r.now then
      r.created, r.when = ns.Now(), ns.Now()
      Publish(list)
      return true
    end
  end
  return false
end

-- players still wanted, changed by the creator (0 = not said)
function ns.SetNeed(id, need)
  need = math.floor(tonumber(need) or 0)
  if need < 0 or need > 39 then return false end
  local list = Own()
  for _, r in ipairs(list) do
    if r.id == id then
      r.need = need
      Publish(list)
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Joining
---------------------------------------------------------------------------
local function MyJoins()
  local me = ns.MyName()
  local s = me and ns.GetSet("lfgj", me)
  return s and ns.DecodeJoins(s.d) or {}
end

local function PublishJoins(map)
  ns.SetOwn("lfgj", EncodeJoins(map))
  Changed()
end

function ns.Join(key, role)
  local r = ns.Request(key)
  if not r or r.mine or not ns.MyName() then return false end
  if role == nil then role = ns.PickRole(r) end
  role = ns.ROLE_TEXT[role] and role or ""
  local map, n = MyJoins(), 0
  for k in pairs(map) do if k ~= key then n = n + 1 end end
  if n >= ns.MAX_JOIN then return false, "full" end
  map[key] = role
  PublishJoins(map)
  return true
end

function ns.Leave(key)
  local map = MyJoins()
  if map[key] == nil then return false end
  map[key] = nil
  PublishJoins(map)
  return true
end

---------------------------------------------------------------------------
-- Invite, whisper, a line in the guild chat
---------------------------------------------------------------------------
-- inviting is not protected; the game itself says when the group is full or the player already is in one
function ns.InviteMember(name)
  if not name or name == ns.MyName() then return false end
  local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
  if not fn then return false end
  return (pcall(fn, ns.ShortName(name)))
end

function ns.WhisperMember(name)
  if not name or name == ns.MyName() then return false end
  if type(ChatFrame_OpenChat) ~= "function" then return false end
  return (pcall(ChatFrame_OpenChat, "/w " .. ns.ShortName(name) .. " "))
end

-- one plain line for the members without this part; called from the click that posts the request
function ns.ChatLine(r)
  local title = ns.RequestTitle(r)
  local parts = { ("LFG: %s (%s)"):format(title, ns.WhenText(r)) }
  if (r.need or 0) > 0 then parts[#parts + 1] = L["need %d"]:format(r.need) end
  if r.note ~= "" and r.cat ~= "t" then parts[#parts + 1] = r.note end
  return (table.concat(parts, ", ") .. " (Guildon Groups)"):sub(1, 250)
end
function ns.PostToGuildChat(r)
  local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if type(fn) ~= "function" or not ns.InGuild() then return false end
  return (pcall(fn, ns.ChatLine(r), "GUILD"))
end

---------------------------------------------------------------------------
-- Housekeeping: what ran out leaves the own sets; entering an instance closes the own dungeon requests that are due
---------------------------------------------------------------------------
local function Prune()
  if not ns.MyName() then return end
  local list, changed = Own()
  if changed then Publish(list) end
  -- (the roster must be there: without it no request of another member counts yet)
  local map, gone = MyJoins(), false
  for key in pairs(#ns.Members() > 0 and map or {}) do
    if not ns.Request(key) then map[key] = nil gone = true end
  end
  if gone then PublishJoins(map) end
  local now = ns.Now()
  for k, t in pairs(ns.db.seen) do if type(t) ~= "number" or now - t > 35 * 86400 then ns.db.seen[k] = nil end end
end
ns.PruneRequests = Prune

local function CheckInstance()
  local inside, kind = ns.Call(IsInInstance)
  if not (ns.Usable(inside) and inside and ns.Usable(kind) and (kind == "party" or kind == "raid")) then return end
  local list, out, now = Own(), {}, ns.Now()
  for _, r in ipairs(list) do
    if not (r.cat == "d" and (r.now and r.created or r.when) <= now + DUE) then out[#out + 1] = r end
  end
  if #out == #list then return end
  Publish(out)
  ns.Print(L["You are inside an instance: your dungeon request is closed."])
end
ns.CheckInstance = CheckInstance

ns.OnInit(function()
  -- every half minute: requests run out by the clock, the list and the counts follow
  ns.NewTicker(30, function()
    ns.InvalidateRequests()
    Prune()
    if ns.OnDataChanged then ns.OnDataChanged() end
  end)
end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(3, CheckInstance) end)
ns.On("ZONE_CHANGED_NEW_AREA", function() ns.After(3, CheckInstance) end)
-- item names arrive later from the server ("Item 2835" until then)
-- (21.11.2026, Ruckler) only for an item a shown request names (the game sends this for every item any addon asks for)
ns.On("GET_ITEM_INFO_RECEIVED", function(_, itemID)
  if not ns.OnDataChanged then return end
  if ns.WindowOpen and not ns.WindowOpen() then return end -- the window repaints only while open (Window.lua Later)
  local id = ns.Num(itemID)
  if id then
    local shown = false
    for _, r in ipairs(ns.Requests()) do if r.cat == "i" and r.ref == id then shown = true break end end
    if not shown then return end
  end
  ns.OnDataChanged()
end)

ns.RegisterKind("lfg", {
  validate = function(d) return ns.DecodeRequests(d) ~= nil end,
  onUpdate = function(owner)
    ns.InvalidateRequests()
    if ns.OnRequestsArrived then ns.OnRequestsArrived(owner) end
    if ns.OnDataChanged then ns.OnDataChanged() end
  end,
})
ns.RegisterKind("lfgj", {
  validate = function(d) return ns.DecodeJoins(d) ~= nil end,
  onUpdate = function(owner)
    ns.InvalidateRequests()
    if ns.OnJoinsArrived then ns.OnJoinsArrived(owner) end
    if ns.OnDataChanged then ns.OnDataChanged() end
  end,
})

function ns.GroupsDiag(out)
  local list, mine, joined = ns.Requests(), 0, 0
  for _, r in ipairs(list) do if r.mine then mine = mine + 1 end end
  for _ in pairs(MyJoins()) do joined = joined + 1 end
  out(("  requests open %d (mine %d), joined %d, do not disturb %s, level %d"):format(#list, mine, joined, ns.db.dnd and "on" or "off", ns.MyLevel()))
end

-- (23.11.2026) the roles of the character who logged in (db.role1, db.role2 hold the last character's until then)
ns.On("PLAYER_LOGIN", function() ns.LoadRoles() if ns.Refresh then ns.Refresh() end end)
