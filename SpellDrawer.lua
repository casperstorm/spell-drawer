-- Spell Drawer: a button that opens a row of extra spell buttons.
--
-- A drawer opens from its own floating handle, or, once its macro
-- (/sd macro <number>) sits on an action bar, from that bar button.
--
-- The handle, the macro's click target and the drawer buttons are secure
-- frames, so opening and casting work in combat. Filling, emptying, moving,
-- docking and the options only work out of it.
--
-- This file is the drawers themselves and the slash command. The options
-- window (Window.lua) works through the `ns` functions at the end.

local _, ns = ...;

local QUESTION_MARK = 134400;
local GAP = 2;
-- As many as the options window has room for
local MAX_DRAWERS = 12;
-- Seconds without a press before a cycling drawer starts over
local CYCLE_RESET = 6;
local MACRO_LIMIT = 255;

-- What pressing a drawer's button does, as `/sd` words it.
local MODES = {
	close = "closes after a cast",
	open = "stays open",
	cycle = "casts the next spell",
};

-- from: the drawer edge that sits against its anchor. to: the anchor edge it sits on.
local DIRECTIONS = {
	UP = { from = "BOTTOM", to = "TOP", x = 0, y = 1 },
	DOWN = { from = "TOP", to = "BOTTOM", x = 0, y = -1 },
	LEFT = { from = "RIGHT", to = "LEFT", x = -1, y = 0 },
	RIGHT = { from = "LEFT", to = "RIGHT", x = 1, y = 0 },
};

-- Blizzard's action buttons, twelve to a bar. A name this client lacks is skipped.
local BARS = {
	"ActionButton",
	"MultiBarBottomLeftButton",
	"MultiBarBottomRightButton",
	"MultiBarRightButton",
	"MultiBarLeftButton",
	"MultiBar5Button",
	"MultiBar6Button",
	"MultiBar7Button",
};

-- Forever namespaces these; the globals are the fallback for older clients.
local GetSpellName = C_Spell and C_Spell.GetSpellName or function(id) return (GetSpellInfo(id)); end;
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture or GetSpellTexture;
local GetItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon;
local GetItemCooldown = C_Item and C_Item.GetItemCooldown
	or C_Container and C_Container.GetItemCooldown
	or GetItemCooldown;
local PickupSpell = C_Spell and C_Spell.PickupSpell or PickupSpell;
local PickupItem = C_Item and C_Item.PickupItem or PickupItem;
local GetActionText = C_ActionBar and C_ActionBar.GetActionText or GetActionText;

local TOGGLE = [[
	local drawer = self:GetFrameRef("drawer")
	if drawer:IsShown() then
		drawer:Hide()
	else
		drawer:Show()
	end
]];

-- Wrapped around each drawer button's click. The cast fires on press or on
-- release depending on the cast-on-key-down setting; release is at or after
-- the cast either way, so that is when the drawer closes.
local CLOSE_PRE = [[
	if button == "LeftButton" and not down and owner:GetAttribute("autoclose") then
		return nil, "close"
	end
]];
local CLOSE_POST = [[
	owner:Hide()
]];

local db;
-- By drawer id. A deleted drawer's frames stay, hidden, for the id's next use.
local handles = {};
local Refresh;

local function Print(text)
	print("|cffffd100Spell Drawer:|r " .. text);
end

local function MacroName(id)
	return "Drawer " .. id;
end

local FindDrawer;

-- Whether the cursor holds one of the drawers' own macros.
function ns.CursorHoldsDrawer()
	local kind, index = GetCursorInfo();
	if kind ~= "macro" then
		return false;
	end
	local id = (GetMacroInfo(index) or ""):match("^Drawer (%d+)$");
	return id ~= nil and FindDrawer(tonumber(id)) ~= nil;
end

FindDrawer = function(id)
	for index, data in ipairs(db.drawers) do
		if data.id == id then
			return data, index;
		end
	end
end

-- Ids are never renumbered: a drawer's macro and key binding go by its id.
local function NewDrawer()
	local id = 1;
	while FindDrawer(id) do
		id = id + 1;
	end
	return {
		id = id, dir = "UP", mode = "close",
		point = "CENTER", relativePoint = "CENTER", x = 0, y = 0,
		entries = {},
	};
end

local function EntryIcon(entry)
	if not entry then
		return nil;
	end
	if entry.kind == "spell" then
		return (GetSpellTexture(entry.id));
	elseif entry.kind == "item" then
		return GetItemIcon(entry.id);
	end
	local _, icon = GetMacroInfo(entry.name);
	return icon;
end

-- The icon and body a drawer's macro should have, and how many spells its
-- cast sequence holds.
--
-- A cycling drawer's macro casts the drawer's spells one per press, and opens
-- the drawer on a right-click instead. Its icon is the question mark, which
-- makes the game show the spell that is up next. Only spells cycle: a macro
-- cannot go in a cast sequence. Whole names only, up to the macro size limit.
local function MacroFor(id, data)
	local click = "/click SpellDrawerMacro" .. id;
	if data.mode == "cycle" then
		local body = ("#showtooltip\n/click [btn:2] SpellDrawerMacro%d\n/castsequence [nobtn:2] reset=%d "):format(id, CYCLE_RESET);
		local count = 0;
		for _, entry in ipairs(data.entries) do
			if entry.kind == "spell" then
				local longer = body .. (count > 0 and ", " or "") .. entry.name;
				if #longer > MACRO_LIMIT then
					break;
				end
				body, count = longer, count + 1;
			end
		end
		if count > 0 then
			return QUESTION_MARK, body, count;
		end
	end
	return EntryIcon(data.entries[1]) or QUESTION_MARK, click, 0;
end

local function EntryFromCursor()
	local kind, id, _, spellID = GetCursorInfo();
	if kind == "spell" and spellID then
		local name = GetSpellName(spellID);
		return name and { kind = "spell", id = spellID, name = name };
	elseif kind == "item" then
		return { kind = "item", id = id };
	elseif kind == "macro" then
		local name = GetMacroInfo(id);
		return name and { kind = "macro", name = name };
	end
end

-- The action buttons that show a macro, by macro name. One on screen wins
-- over one on a hidden bar.
local function FindDocks()
	local docks = {};
	if not GetActionText then
		return docks;
	end
	for _, bar in ipairs(BARS) do
		for i = 1, 12 do
			local button = _G[bar .. i];
			local action = button and (button.action or button:GetAttribute("action"));
			local name = type(action) == "number" and action > 0 and GetActionText(action);
			if name and not (docks[name] and docks[name]:IsVisible()) then
				docks[name] = button;
			end
		end
	end
	return docks;
end

-- Runs under pcall: the numbers are nil for a spell the character does not
-- have, and are handed straight to the widget without being looked at.
local function ApplyCooldown(button)
	local entry = button.entry;
	if entry.kind == "spell" then
		if C_Spell and C_Spell.GetSpellCooldown then
			local info = C_Spell.GetSpellCooldown(entry.id);
			button.cooldown:SetCooldown(info.startTime, info.duration, info.modRate);
		else
			local start, duration, _, modRate = GetSpellCooldown(entry.id);
			button.cooldown:SetCooldown(start, duration, modRate);
		end
	elseif entry.kind == "item" then
		local start, duration = GetItemCooldown(entry.id);
		button.cooldown:SetCooldown(start, duration);
	else
		button.cooldown:SetCooldown(0, 0);
	end
end

local function UpdateCooldowns(drawer)
	for _, button in ipairs(drawer.buttons) do
		if button:IsShown() and not pcall(ApplyCooldown, button) then
			button.cooldown:SetCooldown(0, 0);
		end
	end
end

-- The "+" slot at the end of a drawer is where a drop lands when there is no
-- handle to drop on. It only shows when it is of use: out of combat, with
-- something on the cursor or nothing in the drawer yet.
local function UpdatePlus(drawer)
	local data = drawer.handle.data;
	drawer.plus:SetShown(data ~= nil and not InCombatLockdown()
		and (#data.entries == 0 or GetCursorInfo() ~= nil));
end

-- Puts what is on the cursor into a drawer, at `position` or at the end.
local function Drop(handle, position)
	local entry = not InCombatLockdown() and EntryFromCursor();
	if entry then
		ClearCursor();
		local entries = handle.data.entries;
		table.insert(entries, position or #entries + 1, entry);
	else
		Print("a drawer takes spells, items and macros, and only out of combat.");
	end
	-- Also when refused: a drawer button blanks its action for the drop click
	Refresh();
	if entry then
		handle.drawer:Show();
	end
end

-- Takes an entry out of a drawer and onto the cursor, to drop elsewhere or discard.
local function TakeOut(handle, position)
	if InCombatLockdown() then
		return;
	end
	local entry = table.remove(handle.data.entries, position);
	Refresh();
	if entry.kind == "spell" then
		pcall(PickupSpell, entry.id);
	elseif entry.kind == "item" then
		pcall(PickupItem, entry.id);
	else
		pcall(PickupMacro, entry.name);
	end
end

-- The plain look: a square icon on black. It stays only where there is no
-- action button to copy the bar look from (see Style).
local function Skin(button)
	button.background = button:CreateTexture(nil, "BACKGROUND");
	button.background:SetAllPoints();
	button.background:SetColorTexture(0, 0, 0, 0.85);

	button.icon = button:CreateTexture(nil, "ARTWORK");
	button.icon:SetPoint("TOPLEFT", 1, -1);
	button.icon:SetPoint("BOTTOMRIGHT", -1, 1);
	button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93);

	button.plainHighlight = button:CreateTexture(nil, "HIGHLIGHT");
	button.plainHighlight:SetAllPoints(button.icon);
	button.plainHighlight:SetColorTexture(1, 1, 1, 0.25);
	button.plainHighlight:SetBlendMode("ADD");
end

-- The bar look is copied at run time from a Blizzard action button, piece by
-- piece, instead of naming the art here: that follows whatever this client's
-- bars look like. `source` is that action button, `scale` our size over its.

local function CopyArt(to, from)
	local atlas = from:GetAtlas();
	if atlas then
		to:SetAtlas(atlas);
	else
		to:SetTexture(from:GetTexture());
		to:SetTexCoord(from:GetTexCoord());
	end
end

-- Size and anchors. What was anchored to the source's icon goes on ours,
-- anything else on the button.
local function CopyPlacement(to, from, source, button, scale)
	local width, height = from:GetSize();
	local points = from:GetNumPoints();
	to:ClearAllPoints();
	to:SetSize(width * scale, height * scale);
	for i = 1, points do
		local point, relativeTo, relativePoint, x, y = from:GetPoint(i);
		to:SetPoint(point, relativeTo == source.icon and button.icon or button, relativePoint, x * scale, y * scale);
	end
	if points == 0 then
		to:SetAllPoints(button);
	end
end

-- state: "Normal" (the border), "Pushed" or "Highlight"
local function CopyStateTexture(button, source, state, scale)
	local from = source["Get" .. state .. "Texture"](source);
	local atlas = from and from:GetAtlas();
	local file = from and from:GetTexture();
	if atlas then
		button["Set" .. state .. "Atlas"](button, atlas);
	elseif file then
		button["Set" .. state .. "Texture"](button, file);
	else
		return;
	end
	local to = button["Get" .. state .. "Texture"](button);
	if not atlas then
		to:SetTexCoord(from:GetTexCoord());
	end
	to:SetBlendMode(from:GetBlendMode());
	CopyPlacement(to, from, source, button, scale);
end

local function Style(button, source, scale)
	local icon, mask, slot = source.icon, source.IconMask, source.SlotBackground;
	button.plainHighlight:Hide();
	if icon then
		CopyPlacement(button.icon, icon, source, button, scale);
		button.icon:SetTexCoord(icon:GetTexCoord());
		-- The background goes one sublevel under the icon, whatever layer that
		-- is: within one sublevel the draw order is not ours to choose.
		local layer, sublevel = icon:GetDrawLayer();
		sublevel = math.max(sublevel or 0, -7);
		button.icon:SetDrawLayer(layer, sublevel);
		button.background:SetDrawLayer(layer, sublevel - 1);
	end
	if mask then
		if not button.mask then
			button.mask = button:CreateMaskTexture();
			button.icon:AddMaskTexture(button.mask);
		end
		CopyArt(button.mask, mask);
		CopyPlacement(button.mask, mask, source, button, scale);
	end
	if slot then
		CopyArt(button.background, slot);
		CopyPlacement(button.background, slot, source, button, scale);
	end
	CopyStateTexture(button, source, "Normal", scale);
	CopyStateTexture(button, source, "Pushed", scale);
	CopyStateTexture(button, source, "Highlight", scale);
	if button.cooldown and source.cooldown then
		CopyPlacement(button.cooldown, source.cooldown, source, button, scale);
	end
end

local styleFailed = false;

-- Styles a button unless it already has this look. `look` is the source's
-- border art, which the client can swap after login. A failure is reported
-- once and leaves the button usable, if not pretty.
local function TryStyle(button, source, scale, look)
	if not source or (button.styleSource == source and button.styleScale == scale
		and button.styleLook == look) then
		return;
	end
	button.styleSource, button.styleScale, button.styleLook = source, scale, look;
	local ok, problem = pcall(Style, button, source, scale);
	if not ok and not styleFailed then
		styleFailed = true;
		Print("could not copy the action bar look: " .. tostring(problem));
	end
end

local function ShowEntryTooltip(self)
	local entry = self.entry;
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	if entry.kind == "spell" then
		GameTooltip:SetSpellByID(entry.id);
	elseif entry.kind == "item" then
		GameTooltip:SetItemByID(entry.id);
	else
		GameTooltip:SetText(entry.name);
	end
	GameTooltip:Show();
end

local function ShowHandleTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:AddLine("Spell Drawer " .. self.id);
	GameTooltip:AddLine("Click to open or close.", 1, 1, 1);
	GameTooltip:AddLine("Drop a spell, item or macro here to add it.", 1, 1, 1);
	GameTooltip:AddLine("Shift-right-click a button in the drawer to take it out.", 1, 1, 1);
	GameTooltip:AddLine("Alt-drag to move. /sd for options.", 1, 1, 1);
	GameTooltip:AddLine(("/sd macro %d puts it on an action bar."):format(self.id), 1, 1, 1);
	GameTooltip:Show();
end

local function ShowPlusTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:AddLine("Spell Drawer " .. self.handle.id);
	GameTooltip:AddLine("Drop a spell, item or macro here to add it.", 1, 1, 1);
	GameTooltip:Show();
end

local function CreateButton(drawer, position)
	local handle = drawer.handle;
	local button = CreateFrame("Button", nil, drawer, "SecureActionButtonTemplate");
	button.position = position;
	-- Both edges, so the cast works whichever one the client casts on
	button:RegisterForClicks("AnyDown", "AnyUp");
	Skin(button);
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate");
	button.cooldown:SetAllPoints(button.icon);
	drawer:WrapScript(button, "OnClick", CLOSE_PRE, CLOSE_POST);

	button:SetScript("PreClick", function(self, mouseButton)
		-- Something on the cursor makes this click a drop, which must not cast.
		-- PostClick's Drop puts the action back.
		if mouseButton == "LeftButton" and GetCursorInfo() and not InCombatLockdown() then
			self.dropping = true;
			self:SetAttribute("*type1", nil);
		end
	end);
	button:SetScript("PostClick", function(self, mouseButton, down)
		if down then
			return;
		end
		if self.dropping then
			self.dropping = nil;
			Drop(handle, self.position);
		elseif mouseButton == "RightButton" and IsShiftKeyDown() then
			TakeOut(handle, self.position);
		end
	end);
	button:SetScript("OnReceiveDrag", function(self)
		Drop(handle, self.position);
	end);
	button:SetScript("OnEnter", ShowEntryTooltip);
	button:SetScript("OnLeave", GameTooltip_Hide);

	drawer.buttons[position] = button;
	return button;
end

local function CreateHandle(id)
	local handle = CreateFrame("Button", "SpellDrawerHandle" .. id, UIParent, "SecureHandlerClickTemplate");
	handle.id = id;
	handle.macro = MacroName(id);
	-- One edge only: on both, every click would open the drawer and shut it again
	handle:RegisterForClicks("LeftButtonUp");
	handle:RegisterForDrag("LeftButton");
	handle:SetMovable(true);
	handle:SetClampedToScreen(true);
	Skin(handle);
	-- Gold bar on the edge the drawer opens from
	handle.arrow = handle:CreateTexture(nil, "OVERLAY");
	handle.arrow:SetColorTexture(1, 0.82, 0);

	local drawer = CreateFrame("Frame", nil, handle, "SecureHandlerBaseTemplate");
	drawer.handle = handle;
	drawer.buttons = {};
	drawer:Hide();
	drawer:HookScript("OnShow", function(self)
		UpdateCooldowns(self);
		UpdatePlus(self);
	end);
	handle.drawer = drawer;
	handle:SetFrameRef("drawer", drawer);
	handle:SetAttribute("_onclick", TOGGLE);

	-- What the drawer's macro clicks. It has no place on screen, so nothing
	-- else clicks it and each run of the macro is one click. Both edges,
	-- because which one /click sends is the client's choice.
	local target = CreateFrame("Button", "SpellDrawerMacro" .. id, UIParent, "SecureHandlerClickTemplate");
	target:RegisterForClicks("AnyDown", "AnyUp");
	target:SetFrameRef("drawer", drawer);
	target:SetAttribute("_onclick", TOGGLE);

	-- Not secure, so it can come and go with the cursor
	local plus = CreateFrame("Button", nil, drawer);
	plus.handle = handle;
	Skin(plus);
	local label = plus:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
	label:SetPoint("CENTER");
	label:SetText("+");
	plus:SetScript("OnClick", function()
		if GetCursorInfo() then
			Drop(handle);
		end
	end);
	plus:SetScript("OnReceiveDrag", function()
		Drop(handle);
	end);
	plus:SetScript("OnEnter", ShowPlusTooltip);
	plus:SetScript("OnLeave", GameTooltip_Hide);
	drawer.plus = plus;

	handle:SetScript("PostClick", function(self)
		if GetCursorInfo() then
			Drop(self);
		end
	end);
	handle:SetScript("OnReceiveDrag", Drop);
	handle:SetScript("OnDragStart", function(self)
		if IsAltKeyDown() and not InCombatLockdown() then
			self.moving = true;
			self:StartMoving();
		end
	end);
	handle:SetScript("OnDragStop", function(self)
		if not self.moving then
			return;
		end
		self.moving = nil;
		self:StopMovingOrSizing();
		local data = self.data;
		local point, _, relativePoint, x, y = self:GetPoint();
		data.point, data.relativePoint, data.x, data.y = point, relativePoint, x, y;
	end);
	handle:SetScript("OnEnter", ShowHandleTooltip);
	handle:SetScript("OnLeave", GameTooltip_Hide);

	handles[id] = handle;
	return handle;
end

-- dock: the action button showing this drawer's macro, if there is one.
local function Layout(handle, data, dock)
	local anchor = dock or handle;
	-- The drawer becomes a child of the bar button, so that button's own width
	-- is the size that matches the bar, whatever the bar's scale.
	local size = dock and dock:GetWidth() or db.size;
	local step = size + GAP;
	local dir = DIRECTIONS[data.dir];
	local entries = data.entries;
	local drawer = handle.drawer;
	local icon = EntryIcon(entries[1]) or QUESTION_MARK;
	-- Whose look to copy: a floating drawer takes a stock bar button's
	local source = dock or _G.MultiBarBottomLeftButton1 or _G.ActionButton1;
	local scale = source and size / source:GetWidth();
	local border = source and source:GetNormalTexture();
	local look = border and (border:GetAtlas() or border:GetTexture());

	handle.data = data;
	handle.dock = dock;
	if dock then
		handle:Hide();
	else
		handle:SetSize(size, size);
		TryStyle(handle, source, scale, look);
		-- Not mid-drag: that would pull the handle out from under the cursor
		if not handle.moving then
			handle:ClearAllPoints();
			handle:SetPoint(data.point, UIParent, data.relativePoint, data.x, data.y);
		end
		handle.icon:SetTexture(icon);
		handle.arrow:ClearAllPoints();
		handle.arrow:SetPoint(dir.to);
		handle.arrow:SetSize(dir.x == 0 and size / 2 or 3, dir.y == 0 and size / 2 or 3);
		handle:Show();
	end

	-- Keeps the macro in step with the drawer. The edit fires UPDATE_MACROS,
	-- which comes back here, so only ever edit on a change.
	local macroIcon, macroBody, sequence = MacroFor(handle.id, data);
	handle.sequence = sequence;
	if (handle.macroIcon ~= macroIcon or handle.macroBody ~= macroBody) and GetMacroInfo(handle.macro) then
		handle.macroIcon, handle.macroBody = macroIcon, macroBody;
		EditMacro(handle.macro, nil, macroIcon, macroBody);
	end

	local span = math.max(#entries - 1, 0) * step;
	drawer:SetParent(anchor);
	drawer:SetFrameStrata("HIGH");
	drawer:SetAttribute("autoclose", data.mode ~= "open");
	drawer:ClearAllPoints();
	drawer:SetPoint(dir.from, anchor, dir.to, dir.x * GAP, dir.y * GAP);
	drawer:SetSize(size + math.abs(dir.x) * span, size + math.abs(dir.y) * span);

	for i, entry in ipairs(entries) do
		local button = drawer.buttons[i] or CreateButton(drawer, i);
		local offset = (i - 1) * step;
		button.entry = entry;
		-- Left button with any modifier held (a plain "type1" would only match
		-- with none), which leaves shift-right-click free for taking out.
		-- A spell goes by name, so it casts the highest rank the character has.
		button:SetAttribute("*type1", entry.kind);
		button:SetAttribute("*spell1", entry.kind == "spell" and entry.name or nil);
		button:SetAttribute("*item1", entry.kind == "item" and "item:" .. entry.id or nil);
		button:SetAttribute("*macro1", entry.kind == "macro" and entry.name or nil);
		button.icon:SetTexture(EntryIcon(entry) or QUESTION_MARK);
		button:SetSize(size, size);
		TryStyle(button, source, scale, look);
		button:ClearAllPoints();
		button:SetPoint(dir.from, drawer, dir.from, dir.x * offset, dir.y * offset);
		button:Show();
	end
	for i = #entries + 1, #drawer.buttons do
		drawer.buttons[i]:Hide();
	end

	drawer.plus:SetSize(size, size);
	TryStyle(drawer.plus, source, scale, look);
	drawer.plus:ClearAllPoints();
	drawer.plus:SetPoint(dir.from, drawer, dir.from, dir.x * #entries * step, dir.y * #entries * step);
	UpdatePlus(drawer);
	UpdateCooldowns(drawer);
end

-- Brings every frame in line with the saved drawers and with where their
-- macros are. Secure frames cannot be changed in combat; the end of combat
-- runs this again.
Refresh = function()
	if InCombatLockdown() then
		return;
	end
	local docks = FindDocks();
	for _, handle in pairs(handles) do
		handle.data = nil;
	end
	for _, data in ipairs(db.drawers) do
		local handle = handles[data.id] or CreateHandle(data.id);
		Layout(handle, data, docks[handle.macro]);
	end
	for _, handle in pairs(handles) do
		if not handle.data then
			handle.drawer:SetParent(handle);
			handle.drawer:Hide();
			handle:Hide();
		end
	end
	if ns.UpdateWindow then
		ns.UpdateWindow();
	end
end

-- Action bar events come in bursts; one refresh on the next frame covers them.
local refreshQueued = false;

local function RunQueuedRefresh()
	refreshQueued = false;
	Refresh();
end

local function QueueRefresh()
	if not refreshQueued then
		refreshQueued = true;
		C_Timer.After(0, RunQueuedRefresh);
	end
end

local function Load()
	SpellDrawerDB = SpellDrawerDB or {};
	db = SpellDrawerDB;
	db.size = db.size or 40;
	if not db.drawers then
		db.drawers = {};
		table.insert(db.drawers, NewDrawer());
		Print("your first drawer is in the middle of the screen. Drop spells on it, Alt-drag to move it, /sd for options.");
	end
	for index, data in ipairs(db.drawers) do
		-- Drawers saved by 1.0 have no id; they were known by their place in the list
		data.id = data.id or index;
		-- Up to 1.2 closing after a cast was one setting for all drawers
		data.mode = data.mode or (db.autoClose == false and "open" or "close");
	end
	db.autoClose = nil;
	Refresh();
end

local events = CreateFrame("Frame");
events:RegisterEvent("PLAYER_LOGIN");
events:SetScript("OnEvent", function(self, event)
	if event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
		for _, handle in pairs(handles) do
			if handle.drawer:IsVisible() then
				UpdateCooldowns(handle.drawer);
			end
		end
	elseif event == "CURSOR_CHANGED" then
		for _, handle in pairs(handles) do
			if handle.drawer:IsVisible() then
				UpdatePlus(handle.drawer);
			end
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		for _, handle in pairs(handles) do
			handle.drawer.plus:Hide();
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		Refresh();
	elseif event == "PLAYER_LOGIN" then
		Load();
		self:RegisterEvent("PLAYER_REGEN_DISABLED");
		self:RegisterEvent("PLAYER_REGEN_ENABLED");
		self:RegisterEvent("SPELL_UPDATE_COOLDOWN");
		self:RegisterEvent("BAG_UPDATE_COOLDOWN");
		self:RegisterEvent("CURSOR_CHANGED");
		-- Icons may have changed
		self:RegisterEvent("SPELLS_CHANGED");
		self:RegisterEvent("UPDATE_MACROS");
		-- A drawer's macro may have moved onto, off or along the bars
		self:RegisterEvent("PLAYER_ENTERING_WORLD");
		self:RegisterEvent("ACTIONBAR_SLOT_CHANGED");
		self:RegisterEvent("ACTIONBAR_PAGE_CHANGED");
		self:RegisterEvent("UPDATE_BONUS_ACTIONBAR");
	else
		QueueRefresh();
	end
end);

-- Names for the keys in Bindings.xml
for id = 1, 4 do
	_G["BINDING_NAME_CLICK SpellDrawerHandle" .. id .. ":LeftButton"] = "Open or close drawer " .. id;
end

-- The changes the slash command and the options window make. Each returns
-- a true value when made, and says why when not.

local function Locked()
	if InCombatLockdown() then
		Print("drawers are locked in combat.");
		return true;
	end
end

local function Known(id)
	local data, index = FindDrawer(id);
	if not data then
		Print(("there is no drawer %s."):format(tostring(id)));
	end
	return data, index;
end

function ns.AddDrawer()
	if Locked() then
		return;
	end
	if #db.drawers >= MAX_DRAWERS then
		Print(("%d drawers is the limit."):format(MAX_DRAWERS));
		return;
	end
	local data = NewDrawer();
	table.insert(db.drawers, data);
	Refresh();
	return data;
end

-- Its macro goes with it.
function ns.DeleteDrawer(id)
	local data, index = Known(id);
	if not data or Locked() then
		return;
	end
	table.remove(db.drawers, index);
	pcall(DeleteMacro, MacroName(id));
	Refresh();
	return true;
end

function ns.SetDirection(id, direction)
	local data = Known(id);
	if not data or Locked() then
		return;
	end
	if not DIRECTIONS[direction] then
		Print("a drawer opens up, down, left or right.");
		return;
	end
	data.dir = direction;
	Refresh();
	return true;
end

function ns.SetMode(id, mode)
	local data = Known(id);
	if not data or Locked() then
		return;
	end
	if not MODES[mode] then
		Print("the modes are close, open and cycle.");
		return;
	end
	data.mode = mode;
	Refresh();
	return true;
end

-- Makes the drawer's macro if need be and puts it on the cursor, to be
-- dropped on an action bar.
function ns.PickupMacro(id)
	if not Known(id) or Locked() then
		return;
	end
	local name = MacroName(id);
	local body = "/click SpellDrawerMacro" .. id;
	if not GetMacroInfo(name) then
		-- A character macro first, as drawers are per character
		pcall(CreateMacro, name, QUESTION_MARK, body, true);
	end
	if not GetMacroInfo(name) then
		pcall(CreateMacro, name, QUESTION_MARK, body);
	end
	if not GetMacroInfo(name) then
		Print("could not make the macro. Are all macro slots in use?");
		return;
	end
	if handles[id] then
		-- Unknown from here on; the refresh sets icon and body
		handles[id].macroIcon, handles[id].macroBody = nil, nil;
	end
	Refresh();
	PickupMacro(name);
	return true;
end

local function SetSize(size)
	if not Locked() then
		db.size = math.min(math.max(size, 20), 80);
		Refresh();
	end
end

local function PrintHelp()
	Print("/sd opens the options. As commands:");
	print("  /sd add - new drawer");
	print("  /sd del <number> - delete a drawer");
	print("  /sd macro <number> - get a drawer's macro, to put it on an action bar");
	print("  /sd dir <number> up|down|left|right - which way a drawer opens");
	print("  /sd mode <number> close|open|cycle - close after a cast, stay open, or cast the next spell per press");
	print("  /sd size <20-80> - button size of floating drawers, now " .. db.size);
	for _, data in ipairs(db.drawers) do
		local handle = handles[data.id];
		local dock = handle and handle.dock;
		print(("  drawer %d: %d buttons, opens %s, %s, %s"):format(
			data.id, #data.entries, strlower(data.dir), MODES[data.mode],
			dock and "on " .. (dock:GetName() or "an action bar") or "floating"));
	end
end

SLASH_SPELLDRAWER1 = "/spelldrawer";
SLASH_SPELLDRAWER2 = "/sd";
SlashCmdList.SPELLDRAWER = function(message)
	local command, first, second = strsplit(" ", strlower(message));
	local number = tonumber(first);
	if (command or "") == "" and ns.ToggleWindow then
		ns.ToggleWindow();
	elseif command == "add" then
		local data = ns.AddDrawer();
		if data then
			Print(("drawer %d is in the middle of the screen."):format(data.id));
		end
	elseif command == "del" and number then
		if ns.DeleteDrawer(number) then
			Print(("drawer %d and its macro deleted."):format(number));
		end
	elseif command == "macro" and number then
		if ns.PickupMacro(number) then
			Print(("put the \"%s\" macro on an action bar. The drawer then opens from that button."):format(MacroName(number)));
		end
	elseif command == "dir" and number then
		ns.SetDirection(number, strupper(second or ""));
	elseif command == "mode" and number then
		ns.SetMode(number, second);
	elseif command == "size" and number then
		SetSize(number);
	else
		PrintHelp();
	end
end

-- For the options window

ns.QUESTION_MARK = QUESTION_MARK;
ns.MAX_DRAWERS = MAX_DRAWERS;
ns.handles = handles;
ns.Print = Print;
ns.Skin = Skin;
ns.EntryIcon = EntryIcon;
ns.FindDrawer = FindDrawer;
ns.Drop = Drop;
ns.TakeOut = TakeOut;
ns.ShowEntryTooltip = ShowEntryTooltip;
ns.PrintHelp = PrintHelp;

function ns.Drawers()
	return db.drawers;
end

-- Gives a button of ours, `size` wide, the look of the stock action buttons.
function ns.StyleAsSlot(button, size)
	local source = _G.MultiBarBottomLeftButton1 or _G.ActionButton1;
	local border = source and source:GetNormalTexture();
	TryStyle(button, source, source and size / source:GetWidth(), border and (border:GetAtlas() or border:GetTexture()));
end
