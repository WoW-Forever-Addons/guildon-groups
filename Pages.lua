local _, ns = ...
local L = ns.L
local Kit = ns.Kit
-- (Blizzard look) the page takes its blocks from the window's kit (ns.PageKit), the form from its own pick when it is built
local UI, FUI = Kit, Kit

---------------------------------------------------------------------------
-- The tab "Groups" and the form for a new request (20.11.2026). Data and rules in Groups.lua, the cards in Toast.lua.
-- On top the filter chips (all, for my level, one per category), my role, do not disturb and "New request"; the requests in
-- groups (mine, the ones I joined, the open ones); right the picked request in a card with what the player may do (I'm in,
-- leave, whisper; the creator: invite all, renew, close). Under 960 px the card goes over the list.
-- The window itself is Shared/Window.lua (GuildShared, DonCore's Kit.Window); the options are in Options.lua.
---------------------------------------------------------------------------
local S = Kit.SIZE
local DETAIL_W = 320

ns.TABS = {
  { key = "groups", title = "Groups", icon = "Interface\\Icons\\INV_Misc_GroupLooking" },
}
ns.PANEL_NAME = "GuildonGroupsPanel"
ns.OPTIONS_ID = "Guildon Groups"
ns.SLASH = "/gng options"
function ns.TitleText() return "Groups" end

ns.GROUP_FILTERS = { "all", "level", "d", "z", "q", "i", "t" }
local FILTER_TEXT = { all = "All", level = "For my level" }

local function RoleText(role) return L[ns.ROLE_TEXT[role or ""] or "Any role"] end
-- the game's role symbol in front of a text, "" when the client has none
function ns.RoleIcon(role, size) return ns.Art and ns.Art.RoleIconTag(role, size or 14) or "" end

local function LevelText(r)
  local lo, hi = ns.LevelRange(r)
  if not lo then return nil end
  return hi and ("%d-%d"):format(lo, hi) or ("%d+"):format(lo)
end

---------------------------------------------------------------------------
-- What the form offers
---------------------------------------------------------------------------
-- the dungeons by level, the range on the right
local function DungeonItems()
  local ids = {}
  for id in pairs(ns.DUNGEONS) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b)
    local x, y = ns.DUNGEONS[a], ns.DUNGEONS[b]
    if x[4] ~= y[4] then return x[4] < y[4] end
    if x[2] ~= y[2] then return x[2] < y[2] end
    if x[3] ~= y[3] then return x[3] < y[3] end
    return x[1] < y[1]
  end)
  local out = {}
  for _, id in ipairs(ids) do
    local d = ns.DUNGEONS[id]
    -- (23.11.2026) the client's picture of the dungeon in front of its name
    local tex = ns.DungeonIcon(id)
    out[#out + 1] = { value = id, text = (tex and ("|T%s:16:16|t "):format(tostring(tex)) or "") .. ns.DungeonName(id),
      right = d[2] == d[3] and tostring(d[2]) or (d[2] .. "-" .. d[3]) }
  end
  return out
end

-- the zones of both continents as the client lists them (WoW Forever's own zones with them), else the classic ones
local zoneIDs
local function ZoneIDs()
  if zoneIDs then return zoneIDs end
  local ids, seen = {}, {}
  local zoneType = Enum and Enum.UIMapType and ns.Num(Enum.UIMapType.Zone) or 3
  if C_Map and type(C_Map.GetMapChildrenInfo) == "function" then
    for _, cont in ipairs(ns.CONTINENTS) do
      local kids = ns.Call(C_Map.GetMapChildrenInfo, cont, zoneType, true)
      for _, k in ipairs(type(kids) == "table" and kids or {}) do
        local m = type(k) == "table" and ns.Num(k.mapID)
        if m and not seen[m] then seen[m] = true ids[#ids + 1] = m end
      end
    end
  end
  if #ids == 0 then
    for id in pairs(ns.ZONES) do ids[#ids + 1] = id end
  else
    zoneIDs = ids -- the client answered: kept for the session
  end
  return ids
end

local function ZoneItems()
  local out = {}
  for _, id in ipairs(ZoneIDs()) do
    local z = ns.ZONES[id]
    out[#out + 1] = { value = id, text = ns.ZoneName(id), right = z and (z[2] .. "-" .. z[3]) or nil, lo = z and z[2] or 99, hi = z and z[3] or 99 }
  end
  table.sort(out, function(a, b)
    if a.lo ~= b.lo then return a.lo < b.lo end
    if a.hi ~= b.hi then return a.hi < b.hi end
    return a.text < b.text
  end)
  return out
end

-- the quests in the player's own log
local function QuestItems()
  local out = {}
  local QL = C_QuestLog
  if QL and type(QL.GetNumQuestLogEntries) == "function" and type(QL.GetInfo) == "function" then
    for i = 1, math.min(ns.Num(ns.Call(QL.GetNumQuestLogEntries)) or 0, 60) do
      local info = ns.Call(QL.GetInfo, i)
      if type(info) == "table" and ns.Usable(info.isHeader) and not info.isHeader and ns.Num(info.questID) and ns.Str(info.title) then
        out[#out + 1] = { value = info.questID, text = info.title, right = ns.Num(info.level) and tostring(info.level) or nil }
      end
    end
  elseif type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function" then
    for i = 1, math.min(ns.Num(ns.Call(GetNumQuestLogEntries)) or 0, 60) do
      local title, level, _, header, _, _, _, id = ns.Call(GetQuestLogTitle, i)
      if ns.Str(title) and ns.Usable(header) and not header and ns.Num(id) and id > 0 then
        out[#out + 1] = { value = id, text = title, right = ns.Num(level) and tostring(level) or nil }
      end
    end
  end
  if #out == 0 then out[1] = { value = 0, text = L["Your quest log is empty."] } end
  return out
end

-- an item as the player names it: its ID, a link pasted into the field, or "item:<id>"
function ns.ParseItem(text)
  text = tostring(text or "")
  local id = text:match("|Hitem:(%d+)") or text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$")
  id = tonumber(id)
  return id and id > 0 and id < 1000000000 and id or nil
end

-- "20:30", "20.30", "2030", "20": hour and minute, nil when it is not a time of day
function ns.ParseClock(text)
  text = tostring(text or ""):gsub("%s", "")
  local h, m = text:match("^(%d%d?)[:%.](%d%d)$")
  if not h then h, m = text:match("^(%d%d)(%d%d)$") end
  if not h then h, m = text:match("^(%d%d?)$"), "0" end
  h, m = tonumber(h), tonumber(m)
  if not h or h > 23 or m > 59 then return nil end
  return h, m
end

local function DayItems()
  local now = ns.Now()
  local out = { { value = 0, text = L["Now"] }, { value = 1, text = L["Today"] }, { value = 2, text = L["Tomorrow"] } }
  for i = 3, 7 do
    local t = now + (i - 1) * 86400
    out[#out + 1] = { value = i, text = ns.DayName(tonumber(date("%w", t)) + 1) .. " " .. date(L["%m/%d"], t) }
  end
  return out
end

---------------------------------------------------------------------------
-- The form (Kit.Dialog): what, when, how many, a note, and whether a line goes into the guild chat
---------------------------------------------------------------------------
local form
local FORM_W, LABEL_W = 460, 130
local ROW = S.button + S.gap
local WHAT = { d = "dungeon", z = "zone", q = "quest", i = "item" }

local function FormHeight(err)
  local rows = 6 + (form.cat ~= "t" and 1 or 0) + ((form.day or 0) > 0 and 1 or 0)
  return rows * ROW + (err and 20 or 0)
end

local function SetError(text)
  form.err:SetText(text or "")
  form:SetBodySize(FORM_W - 2 * S.pad, FormHeight(text and text ~= ""))
  FUI.Fit(form.err, form:BodyWidth())
  form:Layout()
end

local WHY_TEXT = {
  name = "Please wait a moment: the game has not named your character yet.",
  guild = "You are not in a guild.",
  full = "You have too many open requests. Close one first.",
  bad = "Please choose what the group is for.",
  time = "Please check the day and the time: it must lie ahead, at most 30 days.",
  text = "Please write what the group is for.",
}

local function Send()
  local cat = form.cat
  local ref = 0
  if cat == "d" then ref = form.dungeonKey or 0
  elseif cat == "z" then ref = form.zoneKey or 0
  elseif cat == "q" then ref = form.questKey or 0
  elseif cat == "i" then ref = ns.ParseItem(form.item:GetText()) or 0 end
  local when
  if (form.day or 0) > 0 then
    local h, m = ns.ParseClock(form.clock:GetText())
    if not h then SetError(L["Please write the time as hour and minute, for example 20:30."]) return end
    local t = date("*t", ns.Now() + (form.day - 1) * 86400)
    t.hour, t.min, t.sec = h, m, 0
    when = time(t)
  end
  local r, why = ns.AddRequest(cat, ref, when, form.need:GetValue() or 0, form.note:GetText(), form.roleKey)
  if not r then SetError(L[WHY_TEXT[why] or WHY_TEXT.bad]) return end
  ns.db.postChat = form.chatKey == "y"
  if ns.db.postChat then ns.PostToGuildChat(r) end
  form:Hide()
  ns.Print(L["Request posted: %s. Members with Guildon Groups see it."]:format((ns.RequestTitle(r))))
  ns.OpenTab("groups")
  if ns.SelectRequest then ns.SelectRequest(r.key) end
  return r
end

local function LayoutForm(d, w)
  if not d.need then return end
  local fw = math.max(60, w - LABEL_W - S.gap)
  local fx = LABEL_W + S.gap
  local y = 0
  local function Row(label, field, width, show)
    label:SetShown(show ~= false)
    field:SetShown(show ~= false)
    if show == false then return end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", d.body, "TOPLEFT", 0, -y - 7)
    FUI.Fit(label, LABEL_W)
    field:ClearAllPoints()
    field:SetPoint("TOPLEFT", d.body, "TOPLEFT", fx, -y)
    field:Layout(width)
    y = y + ROW
  end
  Row(d.labels.cat, d.catBox, fw)
  -- one row for what the group is for: the field of the chosen category
  local what = WHAT[d.cat]
  for _, k in pairs(WHAT) do if k ~= what then d[k]:Hide() end end
  d.labels.what:SetText(d.cat == "d" and L["Dungeon"] or d.cat == "z" and L["Zone"] or d.cat == "q" and L["Quest"] or L["Item"])
  if what then Row(d.labels.what, d[what], fw) else d.labels.what:Hide() end
  Row(d.labels.day, d.dayBox, fw)
  Row(d.labels.clock, d.clock, 80, (d.day or 0) > 0)
  Row(d.labels.role, d.roleBox, fw)
  Row(d.labels.need, d.need, 64)
  Row(d.labels.note, d.note, fw)
  Row(d.labels.chat, d.chatBox, fw)
  d.err:ClearAllPoints()
  d.err:SetPoint("TOPLEFT", d.body, "TOPLEFT", 0, -y - 2)
  FUI.Fit(d.err, w)
end

local function Relayout()
  form.err:SetText("")
  form:SetBodySize(FORM_W - 2 * S.pad, FormHeight())
  form:Layout()
end

local function BuildFormIn()
  form = FUI.Dialog(FUI.blizzLook and "GuildonGroupsFormBlizz" or "GuildonGroupsForm", { width = FORM_W, height = 330, onLayout = function(d, w) LayoutForm(d, w) end })
  local b = form.body
  form.cat, form.day = "d", 0
  form.labels = {}
  for k, text in pairs({ cat = L["Looking for"], what = L["Dungeon"], day = L["When"], clock = L["Time"], need = L["Players wanted"], role = L["My role"],
    note = L["Note"], chat = L["Guild chat"] }) do
    local fs = FUI.Text(b, "row", Kit.C.muted)
    fs:SetText(text)
    form.labels[k] = fs
  end
  form.catBox = FUI.Dropdown(b, {
    items = function()
      local out = {}
      for _, c in ipairs(ns.CATS) do out[#out + 1] = { value = c, text = L[ns.CAT_TEXT[c]] } end
      return out
    end,
    get = function() return form.cat end,
    set = function(v) form.cat = v Relayout() end,
  })
  form.dungeon = FUI.Dropdown(b, { items = DungeonItems, get = function() return form.dungeonKey end, set = function(v) form.dungeonKey = v end })
  form.zone = FUI.Dropdown(b, { items = ZoneItems, get = function() return form.zoneKey end, set = function(v) form.zoneKey = v end })
  form.quest = FUI.Dropdown(b, { items = QuestItems, get = function() return form.questKey end, set = function(v) form.questKey = v end })
  form.item = FUI.EditBox(b, { maxLetters = 200, placeholder = L["Item ID, or drag the item here"], clear = true })
  -- an item dragged from the bags onto the field: its ID goes in (our own frame's script)
  form.item:SetScript("OnReceiveDrag", ns.Guard("item drop", function(self)
    local kind, id = ns.Call(GetCursorInfo)
    if ns.Usable(kind) and kind == "item" and ns.Num(id) then
      self:SetValue(tostring(id))
      ns.Call(ClearCursor)
    end
  end))
  form.dayBox = FUI.Dropdown(b, { items = DayItems, get = function() return form.day end, set = function(v) form.day = v Relayout() end })
  form.clock = FUI.EditBox(b, { maxLetters = 5, placeholder = "20:30" })
  -- what the creator plays himself: the group shows him in that place
  form.roleBox = FUI.Dropdown(b, {
    items = function()
      local out = {}
      for _, k in ipairs(ns.ROLES) do out[#out + 1] = { value = k, text = ns.RoleIcon(k) .. L[ns.ROLE_TEXT[k]] } end
      return out
    end,
    get = function() return form.roleKey or "" end,
    set = function(v) form.roleKey = v end,
  })
  form.need = FUI.EditBox(b, { numeric = true, min = 0, max = 39, maxLetters = 2, placeholder = "0" })
  form.note = FUI.EditBox(b, { maxLetters = ns.NOTE_MAX, placeholder = L["optional"], clear = true })
  form.chatBox = FUI.Dropdown(b, {
    items = function() return { { value = "y", text = L["Also post one line in the guild chat"] }, { value = "n", text = L["Only for members with Guildon Groups"] } } end,
    get = function() return form.chatKey end,
    set = function(v) form.chatKey = v end,
  })
  form.chatBox:SetTooltip(L["Guild chat"], { L["One line in the guild chat reaches the members who do not have Guildon Groups."] })
  form.clock:SetNext(form.need) form.need:SetNext(form.note) form.note:SetNext(form.clock)
  form.err = FUI.Text(b, "sub", Kit.C.red)
  form:SetButtons({
    { text = L["Cancel"], onClick = function(d) d:Hide() end },
    { text = L["Post the request"], kind = "primary", onClick = function() Send() end },
  })
  form.Send = Send
  form:SetTitle(L["New group request"], ns.MODULE.icon)
  form:SetBodySize(FORM_W - 2 * S.pad, FormHeight())
end

-- the form in the game's look (option blizzLook): a build that fails there is done again with the Kit
local function BuildForm()
  FUI = ns.LookKit and ns.LookKit() or Kit
  if FUI == Kit then BuildFormIn() return end
  local ok, err = pcall(BuildFormIn)
  if ok then return end
  if form and form.Hide then pcall(form.Hide, form) end
  form, FUI = nil, Kit
  if ns.LookFailed then ns.LookFailed("request form", err) end
  BuildFormIn()
end
function ns.FormReset()
  if not form then return end
  form:Hide()
  form = nil
end
function ns.RequestForm() return form end -- (tests)

-- cat: the category the form starts with (default: dungeon)
function ns.ShowRequestForm(cat)
  if not ns.InGuild() then ns.Print(L["You are not in a guild."]) return nil end
  if not form then BuildForm() end
  form.cat = ns.CAT_TEXT[cat or ""] and cat or "d"
  form.day = 0
  -- the first dungeon that suits the player's level, the zone he stands in, the first quest of his log
  local level = ns.MyLevel()
  form.dungeonKey = nil
  for _, it in ipairs(DungeonItems()) do
    if not form.dungeonKey then form.dungeonKey = it.value end
    if ns.LevelFits({ cat = "d", ref = it.value }, level) and level <= ns.DUNGEONS[it.value][3] then form.dungeonKey = it.value break end
  end
  local here = C_Map and ns.Num(ns.Call(C_Map.GetBestMapForUnit, "player"))
  local zones = ZoneItems()
  form.zoneKey = zones[1] and zones[1].value or nil
  for _, it in ipairs(zones) do if it.value == here then form.zoneKey = here end end
  local quests = QuestItems()
  form.questKey = quests[1].value
  form.chatKey = ns.db.postChat == false and "n" or "y"
  form.roleKey = (ns.MyRoles())
  form.item:SetValue("")
  form.clock:SetValue("")
  form.need:SetValue("")
  form.note:SetValue("")
  for _, k in ipairs({ "catBox", "dungeon", "zone", "quest", "dayBox", "roleBox", "chatBox" }) do form[k]:Update() end
  form.err:SetText("")
  form:SetBodySize(FORM_W - 2 * S.pad, FormHeight())
  form:Show()
  form:Layout()
  return form
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local page
local Refresh

-- a card over the list (narrow window) gets an opaque ground: the game's box is 85 % opaque, the Kit's card already full
-- (as in Guildon Crafts, 18.11.2026)
local function Opaque(d, on)
  if not (d and d.boxed and d.SetBackdropColor) then return end
  if d._opaque == (on and true or false) then return end
  d._opaque = on and true or false
  d:SetBackdropColor(0.09, 0.08, 0.07, on and 1 or 0.85)
end

local function State()
  local db = ns.db
  local ok = false
  for _, f in ipairs(ns.GROUP_FILTERS) do if f == db.groupFilter then ok = true end end
  if not ok then db.groupFilter = "all" end
  return db
end

local function Entry(r)
  local title, icon, itemID = ns.RequestTitle(r)
  local pill
  if r.mine then pill = { L["yours"], "yellow" }
  elseif ns.Joined(r.key) ~= nil then pill = { L["you are in"], "green" }
  elseif #r.joiners > 0 then pill = { L["%d in"]:format(#r.joiners), "blue" }
  else pill = { L["open"], "blue" } end
  return { key = r.key, req = r, icon = icon, title = title, sub = ns.PortraitName(r.owner, r.look, 12) .. "  " .. ns.RequestSubLine(r),
    pill = pill, status = pill[2], itemID = itemID, rightWidth = 90 }
end

-- the rows of the list and how many requests they show
function ns.GroupEntries()
  local db = State()
  local level = ns.MyLevel()
  local mine, joined, open = {}, {}, {}
  for _, r in ipairs(ns.Requests()) do
    local f = db.groupFilter
    if f == "all" or (f == "level" and ns.LevelFits(r, level)) or f == r.cat then
      if r.mine then mine[#mine + 1] = r elseif ns.Joined(r.key) ~= nil then joined[#joined + 1] = r else open[#open + 1] = r end
    end
  end
  local out = {}
  local closed = type(db.groupFold) == "table" and db.groupFold or {}
  local function Group(list, key, title)
    if #list == 0 then return end
    out[#out + 1] = { kind = "group", key = "h:" .. key, fold = key, text = title, count = #list, collapsed = closed[key] and true or false }
    if not closed[key] then for _, r in ipairs(list) do out[#out + 1] = Entry(r) end end
  end
  Group(mine, "mine", L["My requests"])
  Group(joined, "joined", L["I'm in"])
  Group(open, "open", L["Open requests"])
  return out, #mine + #joined + #open
end

-- what the player may do with a request: label, kind of the button, action
local function Actions(r)
  local out = {}
  local function Add(label, fn, kind) out[#out + 1] = { label = label, fn = fn, kind = kind } end
  if r.mine then
    if #r.joiners > 0 then
      Add(L["Invite all"], function() for _, j in ipairs(r.joiners) do if ns.IsOnline(j.name) then ns.InviteMember(j.name) end end end, "primary")
    end
    if r.now then Add(L["Renew"], function() ns.RenewRequest(r.id) end) end
    Add(L["Close request"], function() ns.CloseRequest(r.id) end)
    return out
  end
  if ns.Joined(r.key) ~= nil then
    Add(L["Leave"], function() ns.Leave(r.key) end)
  else
    -- (23.11.2026) one button per role of mine that still has a place (first and second spec), else plain "I'm in"
    local roles = ns.RolesFor(r)
    if #roles == 0 then
      Add(L["I'm in"], function() ns.Join(r.key) end, "primary")
    else
      for i, x in ipairs(roles) do
        Add(L["I'm in as %s"]:format(RoleText(x)), function() ns.Join(r.key, x) end, i == 1 and "primary" or nil)
      end
    end
  end
  Add(L["Whisper %s"]:format(ns.ShortName(r.owner)), function() ns.WhisperMember(r.owner) end)
  return out
end
ns.RequestActions = Actions

-- the rows of the group card: { role, name } in the order tank, healer, damage, any role; a dungeon (not a raid) has one
-- tank, one healer and three damage dealers, and a place nobody took yet is a row without a name
local SLOTS = { { "t", 1 }, { "h", 1 }, { "d", 3 } }
function ns.GroupRows(r)
  local group, out = ns.GroupOf(r), {}
  local party = r.cat == "d" and not ns.IsRaid(r.ref)
  for _, slot in ipairs(SLOTS) do
    local n = 0
    for _, m in ipairs(group) do
      if m.role == slot[1] then n = n + 1 out[#out + 1] = { role = m.role, name = m.name, owner = m.owner, look = m.look } end
    end
    if party then for _ = n + 1, slot[2] do out[#out + 1] = { role = slot[1] } end end
  end
  for _, m in ipairs(group) do
    if m.role == "" then out[#out + 1] = { role = "", name = m.name, owner = m.owner, look = m.look } end
  end
  return out
end

local function FillDetail(d, r)
  local title, icon, itemID = ns.RequestTitle(r)
  local pill = r.mine and { L["yours"], "yellow" } or (ns.Joined(r.key) ~= nil and { L["you are in"], "green" }) or { L["open"], "blue" }
  d:SetHead({ icon = icon, title = title, pill = pill, itemID = itemID, meta = L[ns.CAT_TEXT[r.cat]] })
  local acts = {}
  for i, a in ipairs(Actions(r)) do
    if i > 4 then break end
    acts[#acts + 1] = { text = a.label, kind = a.kind, onClick = function() a.fn() Refresh() end }
  end
  d:SetActions(acts)
  d:Begin()
  local on = ns.IsOnline(r.owner)
  d:Line(L["From"], Kit.C.muted, ns.PortraitName(r.owner, r.look) .. "  " .. (on and L["online"] or L["offline"]), on and Kit.C.green or Kit.C.quiet)
  d:Line(L["When"], Kit.C.muted, ns.WhenText(r), Kit.C.title)
  d:Line(ns.LeftText(r), Kit.C.quiet)
  if (r.need or 0) > 0 then d:Line(L["Players wanted"], Kit.C.muted, tostring(r.need), Kit.C.title) end
  local range = LevelText(r)
  if range then
    local fits = ns.LevelFits(r, ns.MyLevel())
    d:Line(L["Level"], Kit.C.muted, range, fits and Kit.C.green or Kit.C.red)
  end
  if r.note ~= "" and r.cat ~= "t" then
    d:Section(L["Note"])
    d:Para(r.note, Kit.C.body)
  end
  -- the group as it stands (Daniel 20.11.2026): tank on top, the healer second, the damage dealers under them, the names
  -- in the game's class colours; a dungeon group shows its free places
  d:Section(L["Group: %d"]:format(#r.joiners + 1))
  for _, row in ipairs(ns.GroupRows(r)) do
    if row.name then
      local online = ns.IsOnline(row.name)
      -- (23.11.2026, Daniel: "ein Charakterbild mit drin") race picture and class symbol in front of the name
      d:Line(ns.RoleIcon(row.role) .. RoleText(row.role), Kit.C.muted, ns.PortraitName(row.name, row.look) .. (online and "" or ("  (" .. L["offline"] .. ")")), Kit.C.body)
    else
      d:Line(ns.RoleIcon(row.role) .. RoleText(row.role), Kit.C.quiet, L["free"], Kit.C.quiet)
    end
  end
  if #r.joiners == 0 then
    d:Para(r.mine and L["Nobody else yet. Members see your request in their list and as a toast."] or L["Nobody else yet. Be the first."], Kit.C.muted)
  end
  d:End()
end

function Refresh()
  if not page then return end
  ns.InvalidateRequests()
  local db = State()
  local data, n = ns.GroupEntries()
  page.chips:SetActive(db.groupFilter)
  page.role1:Update()
  page.role2:Update()
  page.dnd:SetText(db.dnd and L["Do not disturb: on"] or L["Do not disturb: off"])
  if page.dnd.SetSelected then page.dnd:SetSelected(db.dnd and true or false) end
  page.list:SetItems(data)
  page.count:SetText(L["%d requests"]:format(n))
  local sel = page.selected
  if sel and not ns.Request(sel) then sel = nil page.overlay = nil end
  page.selected = sel
  local picked
  for _, e in ipairs(data) do if e.req and e.key == sel then picked = e break end end
  page.list:Select(picked)
  if page._w then page:Layout(page._w, page._h, page._mode) end
end
ns.RefreshGroups = Refresh

function ns.SelectRequest(key)
  if not page then return end
  page.selected = key
  page.overlay = key ~= nil or nil
  Refresh()
end

ns.PAGE_BUILDERS.groups = function(p)
  UI = ns.PageKit and ns.PageKit() or Kit
  page = p
  State()
  p.chips = UI.ChipBar(p, { onChange = function(key)
    State().groupFilter = key
    p.selected, p.overlay = nil, nil
    Refresh()
  end })
  for _, f in ipairs(ns.GROUP_FILTERS) do p.chips:Add(f, L[FILTER_TEXT[f] or ns.CAT_SHORT[f]]) end
  -- (23.11.2026, Daniel: "2 Rollen, First und Second Spec") the roles of this character: what "I'm in" offers and which
  -- dungeon requests show a toast (a free place for one of them); also in the options
  local function RoleBox(i)
    local key, label = "role" .. i, i == 1 and L["1st spec"] or L["2nd spec"]
    local box = UI.Dropdown(p, {
      items = function()
        local out = {}
        for _, k in ipairs(ns.ROLES) do out[#out + 1] = { value = k, text = label .. ": " .. ns.RoleIcon(k) .. (k == "" and L["none"] or RoleText(k)) } end
        return out
      end,
      get = function() return ns.db[key] or "" end,
      set = function(v) ns.db[key] = v ns.SaveRoles() Refresh() end,
    })
    box:SetTooltip(label, { L["The roles of this character (first and second spec). \"I'm in\" offers them, and a dungeon request shows a toast only while one of them has a free place."] }, L["Click: choose"])
    return box
  end
  p.role1, p.role2 = RoleBox(1), RoleBox(2)
  p.dnd = UI.Button(p, "", { small = true, onClick = function() ns.SetDND(not ns.db.dnd) Refresh() end })
  p.dnd:SetTooltip(L["Do not disturb"], { L["On: no toasts, no sound and no chat line for new requests. The list still shows them."] }, L["Also: /gng dnd"])
  p.count = UI.Text(p, "sub", Kit.C.muted, "RIGHT")
  p.new = UI.Button(p, L["New request"], { kind = "primary", onClick = function() ns.ShowRequestForm() end })
  p.new:SetTooltip(L["New request"], { L["Look for a group in the guild: a dungeon, questing in a zone, a quest, an item or anything else."] }, L["Also: /gng new"])
  p.list = UI.List(p, {
    onToggle = function(e)
      if not e.fold then return end
      local db = State()
      db.groupFold = type(db.groupFold) == "table" and db.groupFold or {}
      db.groupFold[e.fold] = e.collapsed or nil
      Refresh()
    end,
    onClick = function(e)
      if not e.req then return end
      if p.selected == e.key and p.detail:IsShown() then p.CloseCard() return end
      p.selected, p.overlay = e.key, true
      p.list:Select(e)
      ns.Relayout()
    end,
  })
  p.list:SetEmpty(L["No open group requests. \"New request\" posts one."])
  p.CloseCard = function()
    p.overlay, p.selected = nil, nil
    p.list:Select(nil)
    ns.Relayout()
  end
  p.detail = UI.Detail(p, { onClose = p.CloseCard })
  p.Hint = function() return L["Requests run out by themselves: \"now\" after 45 minutes, planned ones 2 hours after their time."] end
  p.Layout = function(self, w, h, mode)
    self._w, self._h, self._mode = w, h, mode
    local narrow = mode ~= "full"
    local full = w - 2 * S.pad
    local r = self.selected and ns.Request(self.selected)
    local lw = (r and not narrow) and full - DETAIL_W - S.pad or full
    local y = S.gap
    -- first line: the chips, right of them the count and "New request"
    local nw = math.min(self.new.natural or 110, 150)
    self.new:Layout(nw)
    self.new:ClearAllPoints()
    self.new:SetPoint("TOPRIGHT", self, "TOPLEFT", S.pad + full, -y)
    self.count:ClearAllPoints()
    self.count:SetPoint("TOPRIGHT", self, "TOPLEFT", S.pad + full - nw - S.gap, -y - 7)
    UI.Fit(self.count, 90)
    self.chips:ClearAllPoints()
    self.chips:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y - 2)
    self.chips:Layout(math.max(40, full - nw - 90 - 2 * S.gap))
    y = y + S.button + S.gap
    -- second line: my two roles and do not disturb
    local rw = math.max(120, math.min(170, math.floor((full - 2 * S.gap) * 0.3)))
    self.role1:ClearAllPoints()
    self.role1:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    self.role1:Layout(rw)
    self.role2:ClearAllPoints()
    self.role2:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad + rw + S.gap, -y)
    self.role2:Layout(rw)
    local dw = math.min(math.max(120, self.dnd.natural or 150), math.max(60, full - 2 * (rw + S.gap)))
    self.dnd:Layout(dw)
    self.dnd:ClearAllPoints()
    self.dnd:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad + 2 * (rw + S.gap), -y - 2)
    y = y + S.button + S.gap
    self.list:ClearAllPoints()
    self.list:SetPoint("TOPLEFT", self, "TOPLEFT", S.pad, -y)
    self.list:Resize(lw, math.max(40, h - y - S.gap))
    local show = r and true or false
    self.detail:SetShown(show)
    if show then
      local cw = narrow and math.min(DETAIL_W, full) or DETAIL_W
      self.detail:ClearAllPoints()
      self.detail:SetPoint("TOPRIGHT", self, "TOPRIGHT", -S.pad, -y)
      self.detail:Layout(cw, h - y - S.gap)
      Opaque(self.detail, narrow)
      if narrow then pcall(self.detail.SetFrameLevel, self.detail, (self.list:GetFrameLevel() or 1) + 20) end
      self.detail.close:Show()
      FillDetail(self.detail, r)
    end
  end
  p.Refresh = function() Refresh() end
end
