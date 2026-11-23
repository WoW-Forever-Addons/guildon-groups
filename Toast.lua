local _, ns = ...
local L = ns.L

---------------------------------------------------------------------------
-- The toast (20.11.2026, Elmer Fudd: "Alle Mitglieder, die sich in dem Addon nicht auf DND gesetzt haben, erhalten eine
-- Toastbenachrichtung wenn sie im Bereich -3 / +12 gemessen am Endboss-Level sind ... Man sollte einstellen können, wofür
-- man Pop Up-Benachrichtigungen bekommen möchte und sich schnell DND stellen können").
-- A new request of a member shows once as a small card at the top of the screen: who, what, when, with "I'm in", "Show"
-- and a button for do not disturb. Which requests: the category is switched on (options), the level suits (option, on by
-- default; ns.LevelFits), do not disturb is off. A chat line and a sound come with it (options).
-- With the option blizzLook (on by default) the card is the game's own box with the game's fonts and buttons.
-- In combat nothing shows: the cards wait until the fight is over. Several cards show one after the other.
-- At login the requests that are already open come as one card ("3 open group requests for you"), not one each.
-- The creator hears when someone joins his request (a card with "Invite"). A planned request reminds its creator and
-- everyone who joined 15 minutes before its time.
---------------------------------------------------------------------------
local Kit = LibStub("DonCore-1.0"):Get("Kit", 4)
local S = Kit.SIZE
local W, H = 340, 96
local REMIND = 15 * 60
local QUIET = 25 -- seconds after login in which arrivals are gathered into one card

local frame, UI
local queue, current = {}, nil
local quietUntil, burst = nil, {}

local function ClassName(name)
  local m = ns.Member(name)
  local file = m and m.classFile ~= "" and m.classFile or ((ns.InfoOf(name) or {}).classFile or "")
  return "|c" .. ns.ClassHex(file) .. ns.ShortName(name) .. "|r"
end
ns.ClassName = ClassName

-- (23.11.2026, Daniel: "ein Charakterbild mit drin") the race picture of the look a member sent (Groups.lua), then the
-- class symbol, then the name in the class colour; parts the client lacks are left out
function ns.PortraitName(name, look, size)
  size = size or 14
  local m = ns.Member(name)
  local file = m and m.classFile ~= "" and m.classFile or ((ns.InfoOf(name) or {}).classFile or "")
  local race, sex
  if ns.Art then race, sex = ns.Art.ParseLook(look) end
  local pic = race and ns.Art.RaceIconTag(race, sex, size) or ""
  local cls = (file ~= "" and ns.Kit and ns.Kit.IconText) and ns.Kit.IconText({ class = file }, size) or ""
  return pic .. cls .. ClassName(name)
end

-- "now, need 3, <note>"
local function SubLine(r)
  local parts = { ns.WhenText(r) }
  if (r.need or 0) > 0 then parts[#parts + 1] = L["need %d"]:format(r.need) end
  -- (23.11.2026) a quest request says whether I have the quest too
  if r.cat == "q" then local t, c = ns.QuestStateText(r.ref) parts[#parts + 1] = c .. t .. "|r" end
  if r.note ~= "" and r.cat ~= "t" then parts[#parts + 1] = r.note end
  return table.concat(parts, ", ")
end
ns.RequestSubLine = SubLine

-- does the player want a card for this request? second value: why not ("dnd", "category", "level", "role")
function ns.WantsToast(r)
  local db = ns.db
  if db.dnd then return false, "dnd" end
  -- (23.11.2026, Daniel: "alles einzeln abwählbar") raids have their own switch, apart from dungeons
  local key = (r.cat == "d" and ns.IsRaid(r.ref)) and "toast_r" or ("toast_" .. r.cat)
  if db[key] == false then return false, "category" end
  if db.levelFilter ~= false and not ns.LevelFits(r, ns.MyLevel()) then return false, "level" end
  -- (23.11.2026, Daniel: "nur für die Rolle die Toasts") a dungeon group without a free place for my first or second role
  if db.roleFilter ~= false and not ns.RoleFits(r) then return false, "role" end
  return true
end

function ns.SetDND(on, say)
  ns.db.dnd = on and true or false
  if on then
    for i = #queue, 1, -1 do queue[i] = nil end
    if frame then frame:Hide() end
    current = nil
  end
  if say then ns.Print(on and L["Do not disturb is on: no toasts. /gng dnd switches it off."] or L["Do not disturb is off."]) end
  if ns.Refresh then ns.Refresh() end
  if ns.RefreshSettingsUI then ns.SafeCall("settings", ns.RefreshSettingsUI) end
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
local function Paint(tex, c, a) tex:SetColorTexture(c[1], c[2], c[3], a or 1) end

local Next

local function Close()
  if frame then frame:Hide() end
  current = nil
  Next()
end

local function Build(kit)
  UI = kit or (ns.LookKit and ns.LookKit()) or Kit
  local C = Kit.C
  -- (one frame per look: a frame keeps its name, the other look builds its own)
  local f = CreateFrame("Frame", UI ~= Kit and "GuildonGroupsToastBlizz" or "GuildonGroupsToast", UIParent)
  f:SetSize(W, H)
  ns.Call(f.SetFrameStrata, f, "HIGH")
  ns.Call(f.SetClampedToScreen, f, true)
  ns.Call(f.SetMovable, f, true)
  ns.Call(f.EnableMouse, f, true)
  ns.Call(f.RegisterForDrag, f, "LeftButton")
  if Kit.Scaled then Kit.Scaled(f) end
  -- (Daniel 20.11.2026: "dass wir Blizzard-Look damit einbauen") with the option blizzLook the card stands in the game's own
  -- box (the tooltip's border on a dark ground, DonCore Blizz's Box) with the game's fonts and buttons; else the Don card
  local Bz = UI ~= Kit and ns.Blizz and ns.Blizz() or nil
  if Bz and Bz.Box then
    f.box = Bz.Box("Frame", f)
    f.box:SetAllPoints(f)
    ns.Call(f.box.SetFrameLevel, f.box, math.max(0, (ns.Num(ns.Call(f.GetFrameLevel, f)) or 1) - 1))
    ns.Call(f.box.EnableMouse, f.box, false)
    -- the card lies over the game world: nearly opaque, so the text stays readable on a bright ground
    if f.box.boxed and f.box.SetBackdropColor then f.box:SetBackdropColor(0.09, 0.08, 0.07, 0.95) end
    f.blizzLook = true
  else
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    Paint(f.bg, C.card, 0.96)
    f.edges = {}
    for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
      local e = f:CreateTexture(nil, "BORDER")
      e:SetPoint(p[1], f, p[1], 0, 0)
      e:SetPoint(p[2], f, p[2], 0, 0)
      if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
      Paint(e, C.gold, 1)
      f.edges[i] = e
    end
  end
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(36, 36)
  f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", S.pad, -S.pad)
  pcall(f.icon.SetTexCoord, f.icon, 0.07, 0.93, 0.07, 0.93)
  local tx = S.pad + 36 + S.gap
  local tw = W - tx - S.pad - 20
  f.kicker = UI.Text(f, "sub", C.txGold)
  f.kicker:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -S.pad + 2)
  f.title = UI.Text(f, "row", C.title)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -S.pad - 13)
  f.sub = UI.Text(f, "sub", C.muted)
  f.sub:SetPoint("TOPLEFT", f, "TOPLEFT", tx, -S.pad - 29)
  f.textWidth = tw
  f.close = UI.Button(f, "x", { small = true, onClick = function() Close() end })
  f.close:Layout(20)
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  f.buttons = {}
  for i = 1, 3 do
    local b = UI.Button(f, "", { small = true, kind = i == 1 and "primary" or nil, onClick = function()
      local a = current and current.actions and current.actions[i]
      if not a then return end
      local keep = ns.SafeCall("toast action", a.fn)
      if not keep then Close() end
    end })
    f.buttons[i] = b
  end
  f:SetScript("OnDragStart", function(self) ns.Call(self.StartMoving, self) end)
  f:SetScript("OnDragStop", function(self)
    ns.Call(self.StopMovingOrSizing, self)
    local x, y = ns.Call(self.GetCenter, self)
    local pw, ph = ns.Call(UIParent.GetWidth, UIParent), ns.Call(UIParent.GetHeight, UIParent)
    local sc = ns.Num(ns.Call(self.GetScale, self)) or 1
    if ns.Num(x) and ns.Num(y) and ns.Num(pw) and ns.Num(ph) then
      ns.db.toast.x, ns.db.toast.y = x * sc - pw / 2, y * sc - ph / 2
    end
  end)
  -- the card stays while the mouse is on it
  f:SetScript("OnUpdate", function(self, dt)
    if not current then return end
    if self.IsMouseOver and ns.Call(self.IsMouseOver, self) then return end
    current.left = (current.left or 0) - (ns.Num(dt) or 0)
    if current.left <= 0 then Close() end
  end)
  f:Hide()
  frame = f
end

local function Place()
  frame:ClearAllPoints()
  local st, sc = ns.db.toast, ns.Num(ns.Call(frame.GetScale, frame)) or 1
  if ns.Num(st.x) and ns.Num(st.y) then
    frame:SetPoint("CENTER", UIParent, "CENTER", st.x / sc, st.y / sc)
  else
    frame:SetPoint("TOP", UIParent, "TOP", 0, -160 / sc)
  end
end

local function Show(t)
  if not frame then
    local ok, err = pcall(Build)
    if not ok then
      -- the card could not be built in the game's look: once more with the Kit
      if frame and frame.Hide then pcall(frame.Hide, frame) end
      frame = nil
      if ns.LookFailed then ns.LookFailed("toast", err) end
      Build(Kit)
    end
  end
  current = t
  t.left = tonumber(ns.db.toastSeconds) or 12
  frame.icon:SetTexture(t.icon or ns.MODULE.icon)
  frame.kicker:SetText(t.kicker or "")
  frame.title:SetText(t.title or "")
  frame.sub:SetText(t.sub or "")
  local Fit = UI.Fit or Kit.Fit
  Fit(frame.kicker, frame.textWidth)
  Fit(frame.title, frame.textWidth)
  Fit(frame.sub, frame.textWidth)
  local x = S.pad
  for i, b in ipairs(frame.buttons) do
    local a = t.actions and t.actions[i]
    if a then
      b:SetText(a.text)
      local bw = math.min(math.max(60, (b.natural or 80)), 130)
      b:Layout(bw)
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, S.gap)
      b:Show()
      x = x + bw + S.gap
    else
      b:Hide()
    end
  end
  Place()
  frame:Show()
end

Next = function()
  if current or #queue == 0 then return end
  if ns.db.dnd then for i = #queue, 1, -1 do queue[i] = nil end return end
  if InCombatLockdown and ns.Call(InCombatLockdown) then return end -- PLAYER_REGEN_ENABLED calls again
  local t = table.remove(queue, 1)
  -- a card about a request that is gone meanwhile is dropped
  if t.key and not ns.Request(t.key) then return Next() end
  ns.SafeCall("toast", Show, t)
  if not (frame and frame:IsShown()) then current = nil end
end

local function Push(t)
  if #queue >= 8 then table.remove(queue, 1) end
  queue[#queue + 1] = t
  Next()
end

ns.On("PLAYER_REGEN_ENABLED", function() ns.After(1, Next) end)

function ns.ToastState() return frame, current, queue end -- (tests)
-- the option blizzLook changed: the card is built again in the other look the next time it shows
function ns.ToastReset()
  if frame then frame:Hide() end
  frame, current = nil, nil
end

local function Sound()
  if ns.db.sound == false or type(PlaySound) ~= "function" then return end
  local kit = type(SOUNDKIT) == "table" and (SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_QUEST_LOG_OPEN) or 3081
  pcall(PlaySound, kit)
end

---------------------------------------------------------------------------
-- What the cards say
---------------------------------------------------------------------------
local function Open(key)
  if ns.OpenTab then ns.OpenTab("groups") end
  if key and ns.SelectRequest then ns.SelectRequest(key) end
end

local function DndAction()
  return { text = L["Do not disturb"], fn = function() ns.SetDND(true, true) end }
end

local function RequestCard(r)
  local title, icon = ns.RequestTitle(r)
  return { key = r.key, icon = icon, kicker = L["%s is looking for a group"]:format(ns.PortraitName(r.owner, r.look)), title = title, sub = SubLine(r),
    actions = {
      { text = L["I'm in"], fn = function()
        if ns.Join(r.key) then ns.Print(L["You joined: %s. %s sees it and can invite you."]:format(title, ns.ShortName(r.owner))) end
        Open(r.key)
      end },
      { text = L["Show"], fn = function() Open(r.key) end },
      DndAction(),
    } }
end

local function Announce(r)
  local title = ns.RequestTitle(r)
  if ns.db.chatLine ~= false then
    ns.Print(L["%s is looking for a group: %s (%s). /gng shows it."]:format(ClassName(r.owner), title, SubLine(r)))
  end
  Sound()
  Push(RequestCard(r))
end

local function Flush()
  quietUntil = nil
  local list = {}
  for _, key in ipairs(burst) do
    local r = ns.Request(key)
    if r and ns.WantsToast(r) then list[#list + 1] = r end
  end
  burst = {}
  if #list == 0 then return end
  if #list == 1 then Announce(list[1]) return end
  if ns.db.chatLine ~= false then ns.Print(L["Open group requests for you: %d. /gng shows them."]:format(#list)) end
  Sound()
  Push({ icon = ns.MODULE.icon, kicker = L["Guildon Groups"], title = L["Open group requests for you: %d"]:format(#list),
    sub = (ns.RequestTitle(list[1])) .. ", " .. (ns.RequestTitle(list[2])) .. (#list > 2 and ", ..." or ""),
    actions = { { text = L["Show"], fn = function() Open() end }, DndAction() } })
end

-- a set of requests arrived: every request not announced yet is announced once
function ns.OnRequestsArrived(owner)
  local now = ns.Now()
  for _, r in ipairs(ns.Requests()) do
    if r.owner == owner and not r.mine and not ns.db.seen[r.key] then
      ns.db.seen[r.key] = now
      if quietUntil then
        burst[#burst + 1] = r.key
      elseif ns.WantsToast(r) then
        Announce(r)
      end
    end
  end
end

-- someone joined (or left): the creator hears about each new member once
function ns.OnJoinsArrived(owner)
  local now = ns.Now()
  for _, r in ipairs(ns.Requests()) do
    if r.mine then
      for _, j in ipairs(r.joiners) do
        local k = "j:" .. r.key .. ":" .. j.name
        if j.name == owner and not ns.db.seen[k] then
          ns.db.seen[k] = now
          local title, icon = ns.RequestTitle(r)
          local role = j.role ~= "" and (" (" .. L[ns.ROLE_TEXT[j.role]] .. ")") or ""
          ns.Print(L["%s is in for %s%s."]:format(ns.PortraitName(j.name, j.look), title, role))
          if not ns.db.dnd then
            Sound()
            Push({ key = r.key, icon = icon, kicker = L["%s is in"]:format(ns.PortraitName(j.name, j.look) .. role), title = title, sub = SubLine(r),
              actions = {
                { text = L["Invite"], fn = function() ns.InviteMember(j.name) end },
                { text = L["Show"], fn = function() Open(r.key) end },
              } })
          end
        end
      end
    end
  end
end

-- a planned request starts soon: its creator and everyone who joined are reminded once
local function Remind()
  local now = ns.Now()
  for _, r in ipairs(ns.Requests()) do
    if not r.now and r.when > now and r.when - now <= REMIND and (r.mine or ns.Joined(r.key) ~= nil) then
      local k = "r:" .. r.key
      if not ns.db.seen[k] then
        ns.db.seen[k] = now
        local title, icon = ns.RequestTitle(r)
        ns.Print(L["%s starts in %d min."]:format(title, math.ceil((r.when - now) / 60)))
        if not ns.db.dnd then
          Sound()
          Push({ key = r.key, icon = icon, kicker = L["Starts in %d min"]:format(math.ceil((r.when - now) / 60)), title = title,
            sub = L["From %s"]:format(ClassName(r.owner)), actions = { { text = L["Show"], fn = function() Open(r.key) end } } })
        end
      end
    end
  end
end
ns.RemindRequests = Remind

ns.On("PLAYER_LOGIN", function()
  quietUntil = true
  -- the hello goes out 8 s after login (Comm.lua), the answers and the fetched sets follow
  ns.After(8 + QUIET, Flush)
end)
ns.OnInit(function()
  ns.NewTicker(30, Remind)
end)
