-- Runs the addon's plain Lua against a stand-in for the WoW API: saved data,
-- drawers, macros, docking, styling and the options window. It cannot cover
-- what only the game does: the secure click handling, casting, and how things
-- look.
--
-- From the repository root:  tests/run.sh   (Lua 5.1)
--
-- One script, several scenarios chosen by environment variable:
--   (none)            the full walk-through
--   OLD_OPEN=1        saved data from before per-drawer modes, close-after-cast off
--   REFUSE=a,b        frame templates the client refuses to create
--   BARE=1            fresh install on a client with no known action buttons
--   SUB=n NOSLOT=1    variations of the action button art being copied
local CORE = arg[1] or "SpellDrawer.lua"
local combat, cursor, shift = false, nil, false
local function widget(kind, name)
  local w = { _kind = kind, _name = name, _attr = {}, _scripts = {}, _shown = true, _points = {} }
  local mt = {}
  mt.__index = function(t, k)
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    if k == "CloseButton" or k == "TitleContainer" or k == "TitleText" or k == "PortraitContainer" or k == "Inset" then return nil end
    local f = function() end
    if k == "SetAttribute" then f = function(s, a, v) assert(not combat, "protected in combat"); s._attr[a] = v end
    elseif k == "GetAttribute" then f = function(s, a) return s._attr[a] end
    elseif k == "SetScript" or k == "HookScript" then f = function(s, n, fn) s._scripts[n] = fn end
    elseif k == "Show" then f = function(s) local was = s._shown; s._shown = true; if not was and s._scripts.OnShow then s._scripts.OnShow(s) end end
    elseif k == "Hide" then f = function(s) local was = s._shown; s._shown = false; if was and s._scripts.OnHide then s._scripts.OnHide(s) end end
    elseif k == "SetShown" then f = function(s, v) assert(type(v) == "boolean", "SetShown needs boolean"); local was = s._shown; s._shown = v; if v and not was and s._scripts.OnShow then s._scripts.OnShow(s) end; if was and not v and s._scripts.OnHide then s._scripts.OnHide(s) end end
    elseif k == "IsShown" or k == "IsVisible" then f = function(s) return s._shown end
    elseif k == "CreateTexture" or k == "CreateFontString" then f = function() return widget("Texture") end
    elseif k == "SetPoint" then f = function(s, ...) s._points[#s._points + 1] = { ... } end
    elseif k == "ClearAllPoints" then f = function(s) s._points = {} end
    elseif k == "GetPoint" then f = function(s, i) if i then return unpack(s._points[i], 1, 5) end return "BOTTOMLEFT", nil, "BOTTOMLEFT", 100, 200 end
    elseif k == "GetNumPoints" then f = function(s) return #s._points end
    elseif k == "GetSize" then f = function(s) if s._boom then error("boom") end return s._w or 45, s._h or 45 end
    elseif k == "GetAtlas" then f = function(s) return s._atlas end
    elseif k == "SetAtlas" then f = function(s, a) STYLE_CALLS = STYLE_CALLS + 1; s._atlas = a end
    elseif k == "GetTexture" then f = function(s) return s._tex end
    elseif k == "GetTexCoord" then f = function() return 0, 0, 0, 1, 1, 0, 1, 1 end
    elseif k == "SetTexCoord" then f = function(s, ...) s._coords = select("#", ...) end
    elseif k == "GetDrawLayer" then f = function(s) return s._layer or "ARTWORK", s._sub or 0 end
    elseif k == "SetDrawLayer" then f = function(s, l, sub) s._layer = l; s._sub = sub end
    elseif k == "GetBlendMode" then f = function(s) return s._blend or "BLEND" end
    elseif k == "SetBlendMode" then f = function(s, b) s._blend = b end
    elseif k == "SetAllPoints" then f = function(s, r) s._points = { { "ALL", r } } end
    elseif k == "GetFrameLevel" then f = function() return 1 end
    elseif k == "GetStringWidth" then f = function() return 40 end
    elseif k == "GetParent" then f = function(s) return s._parent end
    elseif k == "SetText" then f = function(s, t) s._text = t end
    elseif k == "SetChecked" then f = function(s, v) assert(type(v) == "boolean"); s._checked = v end
    elseif k == "SetEnabled" then f = function(s, v) assert(type(v) == "boolean"); s._enabled = v end
    elseif k == "LockHighlight" then f = function(s) s._locked = true end
    elseif k == "UnlockHighlight" then f = function(s) s._locked = false end
    elseif k == "EnableMouse" then f = function(s, v) s._mouse = v end
    elseif k == "WrapScript" then f = function(s, target, script, pre, post) target._wraps = target._wraps or {}; target._wraps[script] = { pre = pre, post = post } end
    elseif k == "CreateMaskTexture" then f = function() return widget("Mask") end
    elseif k == "AddMaskTexture" then f = function(s, m) s._mask = m end
    elseif k:match("^Set(%a+)Atlas$") then local st = k:match("^Set(%a+)Atlas$"); f = function(s, a) STYLE_CALLS = STYLE_CALLS + 1; s["_st" .. st] = s["_st" .. st] or widget("Texture"); s["_st" .. st]._atlas = a end
    elseif k:match("^Set(%a+)Texture$") then local st = k:match("^Set(%a+)Texture$"); f = function(s, a) s["_st" .. st] = s["_st" .. st] or widget("Texture"); s["_st" .. st]._tex = a end
    elseif k:match("^Get(%a+)Texture$") then local st = k:match("^Get(%a+)Texture$"); f = function(s) return s["_st" .. st] end
    elseif k == "SetTexture" then f = function(s, t) s._tex = t end
    elseif k == "SetSize" then f = function(s, w2, h) assert(w2 >= 0 and h >= 0, "bad size"); s._w, s._h = w2, h end
    elseif k == "GetWidth" then f = function(s) return s._w or 45 end
    elseif k == "GetName" then f = function(s) return s._name end
    elseif k == "SetParent" then f = function(s, p) assert(not combat); s._parent = p end
    elseif k == "SetCooldown" then f = function(s, a, b) assert(a and b, "nil cooldown") s._cd = { a, b } end
    end
    return f
  end
  return setmetatable(w, mt)
end
frames = {}
STYLE_CALLS = 0
local BARE = os.getenv("BARE")
SUB = tonumber(os.getenv("SUB") or "0")
local NOSLOT = os.getenv("NOSLOT")
local REFUSE = {}
for t in (os.getenv("REFUSE") or ""):gmatch("[^,]+") do REFUSE[t] = true end
function CreateFrame(kind, name, parent, template) if template and REFUSE[template] then error("Couldn't find inherited node: " .. template) end local f = widget(kind, name); f._template = template; f._parent = parent;
  if template == "ButtonFrameTemplate" then
    rawset(f, "CloseButton", widget("Button")); local tc = widget("Frame"); rawset(tc, "TitleText", widget("FontString")); rawset(f, "TitleContainer", tc)
    local pc = widget("Frame"); pc.portrait = widget("Texture"); pc.portrait._parent = pc; rawset(f, "PortraitContainer", pc)
  end frames[#frames + 1] = f; if name then _G[name] = f end; return f end
UIParent = widget("Frame", "UIParent"); GameTooltip = widget("GameTooltip"); function GameTooltip_Hide() end
function InCombatLockdown() return combat end
function GetCursorInfo() if cursor then return unpack(cursor) end end
function ClearCursor() cursor = nil end
function IsShiftKeyDown() return shift end
function IsAltKeyDown() return true end
C_Spell = { GetSpellName = function(id) return "Spell" .. id end, GetSpellTexture = function(id) return 1000 + id, 1 end,
  GetSpellCooldown = function(id) if id == 99 then return nil end return { startTime = 0, duration = 0, modRate = 1 } end,
  PickupSpell = function(id) cursor = { "spell", 0, "spell", id } end }
C_Item = { GetItemIconByID = function(id) return 2000 + id end, GetItemCooldown = function() return 0, 0, 1 end, PickupItem = function(id) cursor = { "item", id } end }
-- macros
local macros, edits, macroFull = { Mount = { icon = 3000 } }, 0, false
function GetMacroInfo(x) if x == 3 then x = "Mount" end local m = macros[x]; if m then return x, m.icon, m.body end end
function CreateMacro(n, icon, body, perChar) assert(not combat); if macroFull then error("full") end macros[n] = { icon = icon, body = body, perChar = perChar } end
function EditMacro(n, newName, icon, body) assert(not combat and macros[n] and newName == nil and body); edits = edits + 1; macros[n].icon = icon; macros[n].body = body end
function DeleteMacro(n) assert(macros[n], "no such macro"); macros[n] = nil end
function PickupMacro(n) cursor = { "macro", n } end
-- action bars: slot -> macro name
local slots = {}
function GetActionText(a) return slots[a] end
local function art(b)
  b._w, b._h = 45, 45
  b.icon = widget("Texture"); b.icon._points = { { "TOPLEFT", b, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0 } }; b.icon._layer = "BACKGROUND"; b.icon._sub = SUB
  b.IconMask = widget("Mask"); b.IconMask._atlas = "IconFrame-Mask"; b.IconMask._w, b.IconMask._h = 64, 64; b.IconMask._points = { { "CENTER", b.icon, "CENTER", 0, 0 } }
  local sb = widget("Texture"); b.SlotBackground = not NOSLOT and sb; sb._atlas = "IconFrame-Background"   -- no points: all-points fallback
  b.cooldown = widget("Cooldown"); b.cooldown._w, b.cooldown._h = 39, 40; b.cooldown._points = { { "TOPLEFT", b.icon, "TOPLEFT", 3, -2 }, { "BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -3, 3 } }
  for st, atlas in pairs({ Normal = "IconFrame", Pushed = "IconFrame-Down", Highlight = "IconFrame-Mouseover" }) do
    local t = widget("Texture"); t._atlas = atlas; t._w, t._h = 46, 45; t._points = { { "TOPLEFT", b, "TOPLEFT", 0, 0 } }; if st == "Highlight" then t._blend = "ADD" end
    b["_st" .. st] = t
  end
end
if not BARE then for i = 1, 12 do local b = CreateFrame("Button", "MultiBarBottomLeftButton" .. i); b.action = 60 + i; art(b); local c = CreateFrame("Button", "ActionButton" .. i); c.action = i; art(c) end end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function flush() local t = timers; timers = {}; for _, fn in ipairs(t) do fn() end; return #t end
strsplit = function(sep, s) local out = {}; for w in s:gmatch("[^" .. sep .. "]+") do out[#out + 1] = w end; return unpack(out) end
strlower, strupper = string.lower, string.upper
SlashCmdList = {}
UISpecialFrames = {}; tinsert = table.insert; StaticPopupDialogs = {}; YES, NO = "Yes", "No"
local sounds = 0
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_CHARACTER_INFO_OPEN = 2, IG_CHARACTER_INFO_CLOSE = 3 }; function PlaySound() sounds = sounds + 1 end
function StaticPopup_Show(which, a1, a2, data) local d = StaticPopupDialogs[which]; assert(d and d.text:format(a1)); d.OnAccept({}, data) end
NS = {}
local WINDOW = CORE:gsub("SpellDrawer%.lua$", "Window.lua")
local printed = {}
local realprint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
local function said(s) for _, m in ipairs(printed) do if m:find(s, 1, true) then return true end end end

if BARE then
  local n = #frames
  assert(loadfile(CORE))("SpellDrawer", NS); assert(loadfile(WINDOW))("SpellDrawer", NS)
  local ev = frames[n + 1]; ev._scripts.OnEvent(ev, "PLAYER_LOGIN")
  local db, h = SpellDrawerDB, SpellDrawerHandle1
  assert(#db.drawers == 1 and db.drawers[1].id == 1 and h and h._shown and h.styleSource == nil and h._stNormal == nil and STYLE_CALLS == 0)
  cursor = { "spell", 1, "spell", 11 }; h._scripts.OnReceiveDrag(h); assert(#db.drawers[1].entries == 1 and h.drawer.buttons[1]._w == 40 and h.drawer.buttons[1].mask == nil)
  SlashCmdList.SPELLDRAWER("macro 1"); cursor = nil; ev._scripts.OnEvent(ev, "ACTIONBAR_SLOT_CHANGED"); for _, fn in ipairs(timers) do fn() end
  assert(h.dock == nil and said("your first drawer") and not said("could not"))
  realprint("BARE_OK"); return
end
-- saved data in the 1.0 format (no ids)
SpellDrawerDB = { size = 40, autoClose = true, drawers = {
  { dir = "UP", point = "CENTER", relativePoint = "CENTER", x = 5, y = 6, entries = { { kind = "spell", id = 11, name = "Spell11" }, { kind = "item", id = 22 } } },
  { dir = "LEFT", point = "CENTER", relativePoint = "CENTER", x = 0, y = 0, entries = {} },
  { dir = "UP", point = "CENTER", relativePoint = "CENTER", x = 0, y = 0, entries = { { kind = "macro", name = "Mount" } } },
} }
if os.getenv("OLD_OPEN") then SpellDrawerDB.autoClose = false end
local nframes = #frames
assert(loadfile(CORE))("SpellDrawer", NS); assert(loadfile(WINDOW))("SpellDrawer", NS)
local ev = frames[nframes + 1]
local function fire(e) ev._scripts.OnEvent(ev, e) end
fire("PLAYER_LOGIN")
local db = SpellDrawerDB
assert(db.autoClose == nil and db.drawers[3].mode == (os.getenv("OLD_OPEN") and "open" or "close") and SpellDrawerHandle1.drawer._attr.autoclose == not os.getenv("OLD_OPEN"), "mode migration")
assert(db.drawers[1].id == 1 and db.drawers[2].id == 2 and db.drawers[3].id == 3 and #db.drawers[1].entries == 2, "migration")
local h1, h2, h3 = SpellDrawerHandle1, SpellDrawerHandle2, SpellDrawerHandle3
assert(h1 and h2 and h3 and SpellDrawerMacro1 and SpellDrawerMacro3 and SpellDrawerMacro1._attr._onclick == h1._attr._onclick)
local d1, d2 = h1.drawer, h2.drawer
assert(h1._shown and d1._parent == h1 and d1._w == 40 and d1._h == 82 and h1.icon._tex == 1011)
assert(d2._w == 40 and d2._h == 40 and d2.plus._shown == true and d1.plus._shown == false, "plus on empty only")
assert(d1.plus._points[1][5] == 84)
local ref, b1 = MultiBarBottomLeftButton1, d1.buttons[1]
local k = 40 / 45
assert(h1.styleSource == ref and b1.styleSource == ref and b1.styleScale == k and d1.plus.styleSource == ref, "floating takes the stock look")
assert(b1._stNormal._atlas == "IconFrame" and b1._stPushed._atlas == "IconFrame-Down" and b1._stHighlight._atlas == "IconFrame-Mouseover" and b1._stHighlight._blend == "ADD")
assert(b1._stNormal._w == 46 * k and b1._stNormal._points[1][2] == b1 and b1.plainHighlight._shown == false)
assert(b1.mask and b1.icon._mask == b1.mask and b1.mask._atlas == "IconFrame-Mask" and b1.mask._w == 64 * k and b1.mask._points[1][2] == b1.icon)
assert(b1.background._layer == "BACKGROUND" and b1.background._sub < b1.icon._sub and b1.icon._sub >= -7 and b1.background._sub >= -8, "background under icon")
assert(b1.icon._layer == "BACKGROUND" and b1.icon._coords == 8 and #b1.icon._points == 2 and b1.icon._points[1][2] == b1)
assert(NOSLOT and b1.background._atlas == nil or b1.background._atlas == "IconFrame-Background" and b1.background._points[1][1] == "ALL")
assert(b1.cooldown._points[1][2] == b1.icon and b1.cooldown._points[1][4] == 3 * k and b1.cooldown._points[2][5] == 3 * k)
assert(h1._stNormal._atlas == "IconFrame" and h1.mask and d1.plus._stNormal and not said("could not"))
local calls = STYLE_CALLS; fire("PLAYER_REGEN_ENABLED"); assert(STYLE_CALLS == calls, "no restyle when nothing changed")
-- cursor makes the plus appear on open drawers; combat hides it
d1:Show(); cursor = { "spell", 1, "spell", 33 }; fire("CURSOR_CHANGED"); assert(d1.plus._shown)
d1.plus._scripts.OnClick(d1.plus); assert(#db.drawers[1].entries == 3 and db.drawers[1].entries[3].id == 33 and cursor == nil and d1.plus._shown == false)
d2.plus._scripts.OnClick(d2.plus); assert(#db.drawers[2].entries == 0, "plus click without cursor is a no-op")
fire("PLAYER_REGEN_DISABLED"); assert(d2.plus._shown == false); fire("PLAYER_REGEN_ENABLED"); assert(d2.plus._shown == true)

-- macro: create, pick up, icon synced once
SlashCmdList.SPELLDRAWER("macro 1")
assert(macros["Drawer 1"] and macros["Drawer 1"].body == "/click SpellDrawerMacro1" and macros["Drawer 1"].perChar == true and cursor[2] == "Drawer 1")
assert(macros["Drawer 1"].icon == 1011 and edits == 1, "icon synced")
cursor = nil
for i = 1, 5 do fire("UPDATE_MACROS") end; assert(flush() == 1 and edits == 1, "coalesced, no re-edit")
-- dock: macro placed on MultiBarBottomLeftButton4
slots[64] = "Drawer 1"; fire("ACTIONBAR_SLOT_CHANGED"); fire("ACTIONBAR_SLOT_CHANGED"); assert(flush() == 1)
local dock = MultiBarBottomLeftButton4
assert(h1._shown == false and h1.dock == dock and d1._parent == dock and d1._points[1][2] == dock and d1._points[1][1] == "BOTTOM" and d1._points[1][3] == "TOP")
assert(d1.buttons[1]._w == 45 and d1._h == 45 + 2 * 47, "docked size follows bar button")
assert(h2._shown and h2.dock == nil)
assert(b1.styleSource == dock and b1.styleScale == 1 and b1._stNormal._w == 46 and b1.mask._w == 64 and d1.plus.styleSource == dock and h1.styleSource == ref, "docked takes the dock's look")
calls = STYLE_CALLS; fire("UPDATE_MACROS"); flush(); assert(STYLE_CALLS == calls)
dock._stNormal._atlas = "IconFrame-AddRow"; fire("UPDATE_MACROS"); flush(); assert(b1._stNormal._atlas == "IconFrame-AddRow" and h2._stNormal._atlas == "IconFrame", "art swap picked up")
-- drop / take out while docked
cursor = { "spell", 1, "spell", 44 }; d1.buttons[1]._scripts.OnReceiveDrag(d1.buttons[1]); assert(db.drawers[1].entries[1].id == 44 and edits == 2 and macros["Drawer 1"].icon == 1044)
shift = true; d1.buttons[1]._scripts.PostClick(d1.buttons[1], "RightButton", false); shift = false
assert(db.drawers[1].entries[1].id == 11 and cursor[4] == 44 and edits == 3); cursor = nil
-- click-drop still blanks and restores the wildcard action
cursor = { "money", 1 }; local b = d1.buttons[2]
b._scripts.PreClick(b, "LeftButton", false); assert(b._attr["*type1"] == nil); b._scripts.PostClick(b, "LeftButton", false); assert(b._attr["*type1"] == "item" and b._attr["*item1"] == "item:22"); cursor = nil
-- in combat nothing protected is touched; catches up afterwards
combat = true; slots[64] = nil; fire("ACTIONBAR_SLOT_CHANGED"); flush(); assert(h1.dock == dock)
SlashCmdList.SPELLDRAWER("macro 2"); assert(not macros["Drawer 2"])
combat = false; fire("PLAYER_REGEN_ENABLED"); assert(h1.dock == nil and h1._shown and d1._parent == h1 and d1.buttons[1]._w == 40, "undock")
slots[64] = "Drawer 1"; fire("PLAYER_ENTERING_WORLD"); flush(); assert(h1.dock == dock)
-- hidden bar loses to a visible one
slots[3] = "Drawer 1"; ActionButton3._shown = false; fire("ACTIONBAR_PAGE_CHANGED"); flush(); assert(h1.dock == dock)
ActionButton3._shown = true; fire("ACTIONBAR_PAGE_CHANGED"); flush(); assert(h1.dock == ActionButton3); slots[3] = nil; fire("UPDATE_BONUS_ACTIONBAR"); flush(); assert(h1.dock == dock)
-- macro slots: character full -> account; all full -> message
SlashCmdList.SPELLDRAWER("macro 3"); assert(macros["Drawer 3"]); cursor = nil; slots[70] = "Drawer 3"; fire("ACTIONBAR_SLOT_CHANGED"); flush(); assert(h3.dock == MultiBarBottomLeftButton10 and macros["Drawer 3"].icon == 3000)
macroFull = true; SlashCmdList.SPELLDRAWER("macro 2"); assert(not macros["Drawer 2"] and said("could not make the macro") and cursor == nil); macroFull = false
-- delete the middle drawer: others keep ids, macros and docks
SlashCmdList.SPELLDRAWER("del 2")
assert(#db.drawers == 2 and db.drawers[2].id == 3 and h2._shown == false and h2.data == nil and h1.dock == dock and h3.dock == MultiBarBottomLeftButton10 and macros["Drawer 1"] and macros["Drawer 3"])
SlashCmdList.SPELLDRAWER("dir 3 down"); assert(db.drawers[2].dir == "DOWN" and h3.drawer._points[1][1] == "TOP")
SlashCmdList.SPELLDRAWER("dir 2 down"); SlashCmdList.SPELLDRAWER("del 2"); assert(#db.drawers == 2)
-- delete a docked drawer: macro goes, frames parked
SlashCmdList.SPELLDRAWER("del 3"); slots[70] = nil
assert(#db.drawers == 1 and not macros["Drawer 3"] and h3.drawer._parent == h3 and h3.drawer._shown == false)
-- add reuses the lowest free id
SlashCmdList.SPELLDRAWER("add"); assert(db.drawers[2].id == 2 and h2._shown and h2.data == db.drawers[2] and #h2.data.entries == 0)
SlashCmdList.SPELLDRAWER("add"); assert(db.drawers[3].id == 3 and h3._shown and h3.dock == nil)
-- handle paths still work
cursor = { "item", 77 }; h2._scripts.OnReceiveDrag(h2); assert(h2.data.entries[1].id == 77 and h2.icon._tex == 2077)
h2._scripts.OnDragStart(h2); h2._scripts.OnDragStop(h2); assert(db.drawers[2].point == "BOTTOMLEFT" and db.drawers[2].x == 100)
h2._scripts.OnEnter(h2); d1.plus._scripts.OnEnter(d1.plus); d1.buttons[1]._scripts.OnEnter(d1.buttons[1])
SlashCmdList.SPELLDRAWER("size 30"); assert(h2._w == 30 and d1.buttons[1]._w == 45)
ref.icon._boom = true; SlashCmdList.SPELLDRAWER("size 50"); SlashCmdList.SPELLDRAWER("size 55")
local count = 0; for _, m in ipairs(printed) do if m:find("could not copy the action bar look", 1, true) then count = count + 1 end end
assert(count == 1 and h2._w == 55 and h2._shown, "style failure reported once")

-- ===== modes and cycling =====
ref.icon._boom = nil; printed = {}   -- undo the deliberate style failure above
local D1 = db.drawers[1]
assert(macros["Drawer 1"].body == "/click SpellDrawerMacro1" and D1.mode ~= "cycle")
local before = edits
SlashCmdList.SPELLDRAWER("mode 1 cycle")
local seq = "#showtooltip\n/click [btn:2] SpellDrawerMacro1\n/castsequence [nobtn:2] reset=6 Spell11, Spell33"
assert(D1.mode == "cycle" and macros["Drawer 1"].body == seq and macros["Drawer 1"].icon == 134400 and h1.sequence == 2 and edits == before + 1, "cycle body: " .. macros["Drawer 1"].body)
assert(d1._attr.autoclose == true and h1.dock == dock, "still docked by name")
for i = 1, 4 do fire("UPDATE_MACROS") end; flush(); assert(edits == before + 1, "no edit loop")
SlashCmdList.SPELLDRAWER("mode 1 open"); assert(d1._attr.autoclose == false and macros["Drawer 1"].body == "/click SpellDrawerMacro1" and macros["Drawer 1"].icon == 1011 and h1.sequence == 0)
SlashCmdList.SPELLDRAWER("mode 1 nonsense"); SlashCmdList.SPELLDRAWER("mode 9 cycle"); assert(D1.mode == "open" and said("the modes are") and said("there is no drawer 9"))
-- the 255 limit keeps whole names
local long = {}; for i = 1, 6 do long[i] = { kind = "spell", id = 500 + i, name = ("Long Name %d "):format(i) .. string.rep("x", 40) } end
local keep = D1.entries; D1.entries = long; SlashCmdList.SPELLDRAWER("mode 1 cycle")
local body = macros["Drawer 1"].body
assert(#body <= 255 and h1.sequence == 3 and body:sub(-#long[3].name) == long[3].name and not body:find("Long Name 4", 1, true), "cap: " .. #body .. " " .. h1.sequence)
-- only items and macros: nothing to cycle, plain macro
D1.entries = { { kind = "item", id = 22 }, { kind = "macro", name = "Mount" } }; NS.SetMode(1, "close"); NS.SetMode(1, "cycle")
assert(macros["Drawer 1"].body == "/click SpellDrawerMacro1" and macros["Drawer 1"].icon == 2022 and h1.sequence == 0)
D1.entries = keep; NS.SetMode(1, "cycle"); assert(macros["Drawer 1"].body == seq)

-- ===== the secure snippets: compiled and run against stand-ins, as the game would =====
do
  local b = d1.buttons[1]
  local function snippet(args, body) return assert(loadstring("local " .. args .. " = ...; " .. body)) end
  -- toggle, from the handle and from the macro's click target alike
  local shown = false
  local ref = { IsShown = function() return shown end, Show = function() shown = true end, Hide = function() shown = false end }
  local toggle = snippet("self", h1._attr._onclick); local me = { GetFrameRef = function(_, n) assert(n == "drawer"); return ref end }
  toggle(me); assert(shown); toggle(me); assert(not shown)
  assert(SpellDrawerMacro1._attr._onclick == h1._attr._onclick)
  -- close after a cast: left release only, and only when set to
  local pre, post = snippet("self, button, down, owner", b._wraps.OnClick.pre), snippet("self, message, button, down, owner", b._wraps.OnClick.post)
  local function owner(autoclose) local o = { hidden = false }
    function o:GetAttribute(a) assert(a == "autoclose"); return autoclose end
    function o:Hide() self.hidden = true end
    return o end
  local o = owner(true)
  assert(select(2, pre(b, "LeftButton", false, o)) == "close" and pre(b, "LeftButton", true, o) == nil and select("#", pre(b, "RightButton", false, o)) == 0)
  assert(select("#", pre(b, "LeftButton", false, owner(false))) == 0)
  post(b, "close", "LeftButton", false, o); assert(o.hidden)
end

-- ===== the window =====
assert(SpellDrawerWindow == nil); sounds = 0
SlashCmdList.SPELLDRAWER("")
local w = SpellDrawerWindow
if os.getenv("REFUSE") == "UICheckButtonTemplate" then
  assert(said("could not build the options window") and said("/sd opens the options"), "clean failure")
  local n = #printed; SlashCmdList.SPELLDRAWER(""); local c = 0; for _, m in ipairs(printed) do if m:find("could not build", 1, true) then c = c + 1 end end; assert(c == 1)
  SlashCmdList.SPELLDRAWER("mode 1 close"); assert(D1.mode == "close"); realprint("NOWINDOW_OK"); return
end
assert(w and w._shown and UISpecialFrames[1] == "SpellDrawerWindow" and sounds >= 1 and #w.slots == 12 and not said("could not build"))
assert(w._template == (os.getenv("REFUSE") and "BackdropTemplate" or "ButtonFrameTemplate"))
if not os.getenv("REFUSE") then
  assert(w.TitleContainer.TitleText._text == "Spell Drawer" and w.portrait._tex == "Interface\\Icons\\INV_Box_01" and w.portrait._mask, "template parts used")
  w.CloseButton._scripts.OnClick(w.CloseButton); assert(w._shown == false); SlashCmdList.SPELLDRAWER(""); assert(w._shown)
end
local s1, s2, s3 = w.slots[1], w.slots[2], w.slots[3]
assert(s1.id == 1 and s1._locked and s2.id == 2 and not s2._locked and s3.id == 3 and w.slots[4].id == nil and w.slots[4]._mouse == false and s1._mouse == true)
assert(s1.icon._tex == 1011 and s1._stNormal and s1._stNormal._atlas == "IconFrame" and s1.number._text == 1)
local det = w.detail
assert(det._shown and w.empty._shown == false and det.name._text == "Drawer 1" and det.status._text == "On an action bar")
assert(det.directions.UP._checked and not det.directions.LEFT._checked and det.modes.cycle._checked and not det.modes.close._checked)
assert(det.note._text:find("casts the next spell", 1, true) and det.note._text:find("Items and macros are left out", 1, true) and not det.note._text:find("not on an action bar", 1, true), det.note._text)
assert(det.minis[1]._shown and det.minis[1].icon._tex == 1011 and det.minis[3]._shown and det.minis[4]._shown == false and det.none._shown == false)
-- radios
det.directions.LEFT._scripts.OnClick(det.directions.LEFT); assert(D1.dir == "LEFT" and det.directions.LEFT._checked and det.directions.UP._checked == false and d1._points[1][1] == "RIGHT")
det.modes.close._scripts.OnClick(det.modes.close); assert(D1.mode == "close" and det.modes.close._checked and det.modes.cycle._checked == false and det.note._text:find("closes again", 1, true) and macros["Drawer 1"].body == "/click SpellDrawerMacro1")
-- select another drawer; floating + empty
s2._scripts.OnClick(s2); assert(s2._locked and s1._locked == false and det.name._text == "Drawer 2" and det.status._text == "Floating")
det.modes.cycle._scripts.OnClick(det.modes.cycle); assert(db.drawers[2].mode == "cycle" and det.note._text:find("not on an action bar yet", 1, true))
-- drag slot to bar: macro made and picked up, cycling body from the start
s2._scripts.OnDragStart(s2); assert(cursor[2] == "Drawer 2" and macros["Drawer 2"] and macros["Drawer 2"].body == "/click SpellDrawerMacro2" and macros["Drawer 2"].icon == 2077 and det.note._text:find("no spells in this drawer", 1, true), "an item-only drawer has nothing to cycle"); cursor = nil
cursor = { "spell", 1, "spell", 55 }; s2._scripts.OnClick(s2); assert(macros["Drawer 2"].body:find("/castsequence [nobtn:2] reset=6 Spell55", 1, true) and macros["Drawer 2"].icon == 134400 and det.note._text:find("Items and macros are left out", 1, true))
-- drop a spell on a slot, on the contents strip, on a mini; take one out
cursor = { "spell", 1, "spell", 61 }; s3._scripts.OnReceiveDrag(s3); assert(det.name._text == "Drawer 3" and db.drawers[3].entries[1].id == 61 and cursor == nil)
local contents = det.minis[1]._parent
cursor = { "spell", 1, "spell", 62 }; contents._scripts.OnClick(contents); assert(db.drawers[3].entries[2].id == 62)
cursor = { "spell", 1, "spell", 63 }; det.minis[1]._scripts.OnReceiveDrag(det.minis[1]); assert(db.drawers[3].entries[1].id == 63 and #db.drawers[3].entries == 3 and det.minis[3]._shown)
contents._scripts.OnClick(contents); assert(#db.drawers[3].entries == 3, "click without cursor is nothing")
shift = true; det.minis[2]._scripts.OnClick(det.minis[2], "RightButton"); shift = false; assert(#db.drawers[3].entries == 2 and cursor[4] == 61 and det.minis[3]._shown == false); cursor = nil
det.minis[1]._scripts.OnEnter(det.minis[1]); s1._scripts.OnEnter(s1)
-- a drawer dragged from the grid and let go of inside the window is not filed as an entry
local n3 = #db.drawers[3].entries
s1._scripts.OnDragStart(s1); assert(cursor[2] == "Drawer 1" and NS.CursorHoldsDrawer()); s3._scripts.OnReceiveDrag(s3); assert(cursor == nil and #db.drawers[3].entries == n3)
s1._scripts.OnDragStart(s1); contents._scripts.OnClick(contents); assert(cursor == nil and #db.drawers[3].entries == n3)
s1._scripts.OnDragStart(s1); det.minis[1]._scripts.OnClick(det.minis[1], "LeftButton"); assert(cursor == nil and #db.drawers[3].entries == n3)
cursor = { "macro", "Mount" }; assert(not NS.CursorHoldsDrawer()); contents._scripts.OnClick(contents); assert(#db.drawers[3].entries == n3 + 1 and db.drawers[3].entries[n3 + 1].name == "Mount"); table.remove(db.drawers[3].entries)
-- new and delete
local count = #db.drawers
w.add._scripts.OnClick(w.add); assert(#db.drawers == count + 1 and det.name._text == "Drawer " .. db.drawers[count + 1].id and w.slots[count + 1]._locked)
local gone = db.drawers[count + 1].id
w.delete._scripts.OnClick(w.delete); assert(#db.drawers == count and not NS.FindDrawer(gone) and det.name._text == "Drawer 1" and s1._locked)
-- limit
while #db.drawers < 12 do assert(NS.AddDrawer()) end; assert(w.add._enabled == false and w.slots[12].id and not NS.AddDrawer() and said("12 drawers is the limit"))
while #db.drawers > count do NS.DeleteDrawer(db.drawers[#db.drawers].id) end; assert(w.add._enabled == true)
-- in combat every control is callable and changes nothing
combat = true; local snapshot = D1.dir .. D1.mode .. #db.drawers .. #db.drawers[3].entries
det.directions.UP._scripts.OnClick(det.directions.UP); det.modes.open._scripts.OnClick(det.modes.open)
assert(det.name._text == "Drawer 1" and det.directions.LEFT._checked and det.directions.UP._checked == false and det.modes.close._checked and det.modes.open._checked == false, "refused click re-synced")
w.add._scripts.OnClick(w.add); w.delete._scripts.OnClick(w.delete)
s1._scripts.OnDragStart(s1); s2._scripts.OnClick(s2); cursor = { "spell", 1, "spell", 64 }; s3._scripts.OnReceiveDrag(s3); contents._scripts.OnClick(contents); cursor = nil
shift = true; det.minis[1]._scripts.OnClick(det.minis[1], "RightButton"); shift = false
assert(snapshot == D1.dir .. D1.mode .. #db.drawers .. #db.drawers[3].entries and said("locked in combat"), "combat safe")
combat = false; fire("PLAYER_REGEN_ENABLED")
-- close, reopen, no drawers at all
SlashCmdList.SPELLDRAWER(""); assert(w._shown == false); SpellDrawer_OnAddonCompartmentClick(); assert(w._shown)
while #db.drawers > 0 do NS.DeleteDrawer(db.drawers[1].id) end
assert(det._shown == false and w.empty._shown and w.delete._enabled == false and w.slots[1].id == nil and not macros["Drawer 1"])
w.add._scripts.OnClick(w.add); assert(det._shown and det.name._text == "Drawer 1" and det.none._shown)
printed = {}; SlashCmdList.SPELLDRAWER("help")
assert(not said("could not"), "no failures reported")
-- a widget call that fails after a good build: the window goes, the drawers carry on
do
  local hd = NS.handles[1]; cursor = { "spell", 1, "spell", 71 }; NS.Drop(hd); assert(w._shown and #db.drawers[1].entries == 1)
  rawset(det.name, "SetText", function() error("boom") end)
  shift = true; local mini = det.minis[1]; mini._scripts.OnClick(mini, "RightButton"); shift = false
  assert(#db.drawers[1].entries == 0 and cursor and cursor[4] == 71, "take-out still lands on the cursor"); cursor = nil
  assert(w._shown == false and said("could not fill the options window"))
  NS.SetDirection(1, "DOWN"); NS.AddDrawer(); assert(db.drawers[1].dir == "DOWN" and #db.drawers == 2)
  local c = 0; for _, m in ipairs(printed) do if m:find("could not fill", 1, true) then c = c + 1 end end; assert(c == 1, "reported once")
  local n = #printed; SlashCmdList.SPELLDRAWER(""); assert(w._shown == false and #printed > n and printed[n + 1]:find("/sd opens the options", 1, true))
end
realprint("ALL_OK; /sd help output:"); for _, m in ipairs(printed) do realprint("  " .. m) end
