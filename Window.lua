-- Spell Drawer's options window, after the game's own macro window: the
-- drawers as a grid of slots on top, the selected one's settings below, and
-- Delete and New along the bottom. A drawer is dragged from its slot onto an
-- action bar the way a macro is.
--
-- It is built on first use, and built and filled under pcall: a template or
-- widget call this client turns out not to have costs the window and never
-- the drawers.

local _, ns = ...;

local WIDTH, HEIGHT = 338, 490;
local MARGIN = 29;
local INNER = WIDTH - 2 * MARGIN;
local SLOT, SLOT_GAP, COLUMNS = 40, 8, 6;
-- Eleven, which leaves room at the end of the row for "+3" when there are more
local MINI, MINI_GAP, MINIS = 20, 3, 11;
local PORTRAIT = "Interface\\Icons\\INV_Box_01";

local DIRECTIONS = {
	{ key = "UP", label = "Up" },
	{ key = "DOWN", label = "Down" },
	{ key = "LEFT", label = "Left" },
	{ key = "RIGHT", label = "Right" },
};

local MODES = {
	{
		key = "close",
		label = "Open the drawer",
		note = "The drawer opens, and closes again once you cast from it.",
	},
	{
		key = "open",
		label = "Open it and keep it open",
		note = "The drawer stays open until you press its button again, so you can cast several in a row.",
	},
	{
		key = "cycle",
		label = "Cast the next spell",
		note = "Each press of the action bar button casts the next spell in the drawer. Right-click the button to open the drawer.",
	},
};

local window;
-- Set once building or filling the window has failed; /sd prints help from then on
local failed = false;
-- Id of the drawer whose settings show
local selected;
local Update;

local function Sound(name)
	local id = SOUNDKIT and SOUNDKIT[name];
	if id then
		PlaySound(id);
	end
end

local function SelectedHandle()
	return ns.handles[selected];
end

-- Drops what is on the cursor into the selected drawer.
local function DropOnSelected(position)
	local handle = SelectedHandle();
	if ns.CursorHoldsDrawer() then
		-- A drawer dragged from the grid and let go of inside the window
		ClearCursor();
	elseif handle then
		ns.Drop(handle, position);
	end
end

-- A stock window frame. Which templates exist, and where they keep their
-- title, portrait and close button, differs between clients.
local function CreateWindowFrame()
	local frame;
	for _, template in ipairs({ "ButtonFrameTemplate", "PortraitFrameTemplate", "BasicFrameTemplateWithInset" }) do
		local ok, created = pcall(CreateFrame, "Frame", "SpellDrawerWindow", UIParent, template);
		if ok and created then
			frame = created;
			break;
		end
	end
	if not frame then
		frame = CreateFrame("Frame", "SpellDrawerWindow", UIParent, "BackdropTemplate");
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		});
	end
	frame:Hide();
	frame:SetSize(WIDTH, HEIGHT);
	frame:SetPoint("CENTER", UIParent, "CENTER", -280, 40);
	frame:SetFrameStrata("HIGH");
	frame:SetToplevel(true);
	frame:EnableMouse(true);
	frame:SetMovable(true);
	frame:SetClampedToScreen(true);
	frame:RegisterForDrag("LeftButton");
	frame:SetScript("OnDragStart", frame.StartMoving);
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing);
	-- Escape closes it
	tinsert(UISpecialFrames, "SpellDrawerWindow");

	local close = frame.CloseButton or frame.closeButton
		or (frame.TitleContainer and frame.TitleContainer.CloseButton);
	if not close then
		close = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
		close:SetPoint("TOPRIGHT", -3, -3);
	end
	-- The stock handler closes through the panel manager, which is blocked
	-- in combat; this window is not secure and can simply hide.
	close:SetScript("OnClick", function()
		frame:Hide();
	end);

	local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText);
	if not title then
		title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
		title:SetPoint("TOP", 0, -6);
	end
	title:SetText("Spell Drawer");

	frame.portrait = frame.portrait or (frame.PortraitContainer and frame.PortraitContainer.portrait);
	return frame;
end

-- A square icon in the round portrait. Decoration only, hence its own pcall.
local function DressPortrait(portrait)
	portrait:SetTexture(PORTRAIT);
	portrait:SetTexCoord(0.07, 0.93, 0.07, 0.93);
	local mask = portrait:GetParent():CreateMaskTexture();
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE");
	mask:SetAllPoints(portrait);
	portrait:AddMaskTexture(mask);
end

local function ShowSlotTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:AddLine("Drawer " .. self.id);
	GameTooltip:AddLine("Drag it onto an action bar.", 1, 1, 1);
	GameTooltip:AddLine("Drop a spell, item or macro on it to add that.", 1, 1, 1);
	GameTooltip:Show();
end

-- One drawer in the grid: click to select, drag to an action bar.
local function CreateSlot(parent, index)
	local slot = CreateFrame("Button", nil, parent);
	local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS);
	slot:SetSize(SLOT, SLOT);
	slot:SetPoint("TOPLEFT", parent, "TOPLEFT", column * (SLOT + SLOT_GAP), -row * (SLOT + SLOT_GAP));
	ns.Skin(slot);
	slot.number = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	slot.number:SetPoint("BOTTOMRIGHT", -4, 4);

	slot:RegisterForDrag("LeftButton");
	slot:SetScript("OnClick", function(self)
		selected = self.id;
		if GetCursorInfo() then
			DropOnSelected();
		else
			Sound("IG_MAINMENU_OPTION_CHECKBOX_ON");
			Update();
		end
	end);
	slot:SetScript("OnDragStart", function(self)
		ns.PickupMacro(self.id);
	end);
	slot:SetScript("OnReceiveDrag", function(self)
		selected = self.id;
		DropOnSelected();
	end);
	slot:SetScript("OnEnter", ShowSlotTooltip);
	slot:SetScript("OnLeave", GameTooltip_Hide);
	return slot;
end

-- One of the selected drawer's contents, small.
local function CreateMini(parent, index)
	local mini = CreateFrame("Button", nil, parent);
	mini.position = index;
	mini:SetSize(MINI, MINI);
	mini:SetPoint("LEFT", parent, "LEFT", (index - 1) * (MINI + MINI_GAP), 0);
	mini.icon = mini:CreateTexture(nil, "ARTWORK");
	mini.icon:SetAllPoints();
	mini.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93);

	mini:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	mini:SetScript("OnClick", function(self, mouseButton)
		local handle = SelectedHandle();
		if GetCursorInfo() then
			DropOnSelected(self.position);
		elseif handle and mouseButton == "RightButton" and IsShiftKeyDown() then
			ns.TakeOut(handle, self.position);
		end
	end);
	mini:SetScript("OnReceiveDrag", function(self)
		DropOnSelected(self.position);
	end);
	mini:SetScript("OnEnter", function(self)
		ns.ShowEntryTooltip(self);
		GameTooltip:AddLine("Shift-right-click to take it out.", 0.5, 0.5, 0.5);
		GameTooltip:Show();
	end);
	mini:SetScript("OnLeave", GameTooltip_Hide);
	return mini;
end

-- A checkbox that is one choice of several: Update checks the one in force.
local function CreateRadio(parent, label, onPick)
	local radio = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate");
	radio:SetSize(24, 24);
	local text = radio:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	text:SetPoint("LEFT", radio, "RIGHT", 1, 1);
	text:SetText(label);
	-- The label is part of the click target
	radio:SetHitRectInsets(0, -(text:GetStringWidth() + 4), 0, 0);
	radio:SetScript("OnClick", function()
		Sound("IG_MAINMENU_OPTION_CHECKBOX_ON");
		onPick();
		-- Also when refused: the click itself has toggled the box
		Update();
	end);
	return radio;
end

local function CreateLabel(parent, text, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	label:SetPoint("TOPLEFT", MARGIN, y);
	label:SetText(text);
	return label;
end

local function Build()
	local frame = CreateWindowFrame();
	if frame.portrait then
		pcall(DressPortrait, frame.portrait);
	end

	-- Everything of ours goes on a layer above the template's own parts: its
	-- inset has a background that would otherwise cover what is drawn on the
	-- frame itself.
	local body = CreateFrame("Frame", nil, frame);
	body:SetAllPoints();
	body:SetFrameLevel(frame:GetFrameLevel() + 5);

	local hintLeft = frame.portrait and 70 or MARGIN;
	local hint = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	hint:SetPoint("TOPLEFT", hintLeft, -30);
	hint:SetWidth(WIDTH - hintLeft - MARGIN);
	hint:SetJustifyH("LEFT");
	hint:SetText("Drag a drawer onto an action bar to open it from there. Drop spells on a drawer to fill it.");

	local grid = CreateFrame("Frame", nil, body);
	grid:SetPoint("TOPLEFT", MARGIN, -72);
	grid:SetSize(INNER, 2 * SLOT + SLOT_GAP);
	frame.slots = {};
	for index = 1, ns.MAX_DRAWERS do
		frame.slots[index] = CreateSlot(grid, index);
	end

	local divider = body:CreateTexture(nil, "ARTWORK");
	divider:SetColorTexture(1, 1, 1, 0.12);
	divider:SetPoint("TOPLEFT", MARGIN, -170);
	divider:SetSize(INNER, 1);

	frame.empty = body:CreateFontString(nil, "OVERLAY", "GameFontDisable");
	frame.empty:SetPoint("TOP", 0, -250);
	frame.empty:SetText("No drawers. New Drawer makes one.");

	-- The selected drawer's settings
	local detail = CreateFrame("Frame", nil, body);
	detail:SetPoint("TOPLEFT", 0, -178);
	detail:SetPoint("BOTTOMRIGHT", 0, 30);
	frame.detail = detail;

	detail.name = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
	detail.name:SetPoint("TOPLEFT", MARGIN, 0);
	detail.status = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	detail.status:SetPoint("TOPRIGHT", -MARGIN, -4);

	CreateLabel(detail, "Contents", -26);
	local contents = CreateFrame("Button", nil, detail);
	contents:SetPoint("TOPLEFT", MARGIN, -40);
	contents:SetSize(INNER, MINI + 4);
	contents:SetScript("OnClick", function()
		if GetCursorInfo() then
			DropOnSelected();
		end
	end);
	contents:SetScript("OnReceiveDrag", function()
		DropOnSelected();
	end);
	detail.minis = {};
	for index = 1, MINIS do
		detail.minis[index] = CreateMini(contents, index);
	end
	detail.more = contents:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	detail.more:SetPoint("RIGHT");
	detail.none = contents:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
	detail.none:SetPoint("LEFT");
	detail.none:SetText("Empty. Drop spells, items or macros here.");

	CreateLabel(detail, "Opens", -74);
	detail.directions = {};
	for index, direction in ipairs(DIRECTIONS) do
		local radio = CreateRadio(detail, direction.label, function()
			ns.SetDirection(selected, direction.key);
		end);
		radio:SetPoint("TOPLEFT", MARGIN - 4 + (index - 1) * 70, -86);
		detail.directions[direction.key] = radio;
	end

	CreateLabel(detail, "When pressed", -120);
	detail.modes = {};
	for index, mode in ipairs(MODES) do
		local radio = CreateRadio(detail, mode.label, function()
			ns.SetMode(selected, mode.key);
		end);
		radio:SetPoint("TOPLEFT", MARGIN - 4, -132 - (index - 1) * 22);
		detail.modes[mode.key] = radio;
	end

	detail.note = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	detail.note:SetPoint("TOPLEFT", MARGIN, -206);
	detail.note:SetWidth(INNER);
	detail.note:SetJustifyH("LEFT");
	detail.note:SetJustifyV("TOP");
	detail.note:SetWordWrap(true);

	StaticPopupDialogs["SPELLDRAWER_DELETE"] = {
		text = "Delete drawer %s, its contents and its macro?",
		button1 = YES,
		button2 = NO,
		OnAccept = function(self, data)
			ns.DeleteDrawer(data or self.data);
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	};

	frame.delete = CreateFrame("Button", nil, body, "UIPanelButtonTemplate");
	frame.delete:SetSize(96, 22);
	frame.delete:SetPoint("BOTTOMLEFT", 6, 4);
	frame.delete:SetText("Delete");
	frame.delete:SetScript("OnClick", function()
		StaticPopup_Show("SPELLDRAWER_DELETE", selected, nil, selected);
	end);

	frame.add = CreateFrame("Button", nil, body, "UIPanelButtonTemplate");
	frame.add:SetSize(110, 22);
	frame.add:SetPoint("BOTTOMRIGHT", -6, 4);
	frame.add:SetText("New Drawer");
	frame.add:SetScript("OnClick", function()
		local data = ns.AddDrawer();
		if data then
			selected = data.id;
			Update();
		end
	end);

	frame:SetScript("OnShow", function()
		Sound("IG_CHARACTER_INFO_OPEN");
		Update();
	end);
	frame:SetScript("OnHide", function()
		Sound("IG_CHARACTER_INFO_CLOSE");
	end);
	return frame;
end

-- What the cycling mode's note adds about this drawer in particular.
local function CycleRemarks(data, handle)
	local spells = 0;
	for _, entry in ipairs(data.entries) do
		if entry.kind == "spell" then
			spells = spells + 1;
		end
	end
	local cycling = handle and handle.sequence or 0;
	local remarks = "";
	if spells == 0 then
		remarks = " There are no spells in this drawer to cycle through yet.";
	elseif cycling < spells then
		remarks = (" Only the first %d of its %d spells fit in the macro."):format(cycling, spells);
	elseif spells < #data.entries then
		remarks = " Items and macros are left out of the cycle.";
	end
	if not (handle and handle.dock) then
		remarks = remarks .. " This drawer is not on an action bar yet.";
	end
	return remarks;
end

local function Fill()
	local drawers = ns.Drawers();
	if not ns.FindDrawer(selected) then
		selected = drawers[1] and drawers[1].id;
	end

	for index, slot in ipairs(window.slots) do
		local data = drawers[index];
		ns.StyleAsSlot(slot, SLOT);
		slot.id = data and data.id;
		slot:EnableMouse(data ~= nil);
		slot.icon:SetTexture(data and (ns.EntryIcon(data.entries[1]) or ns.QUESTION_MARK) or nil);
		slot.number:SetText(data and data.id or "");
		if data and data.id == selected then
			slot:LockHighlight();
		else
			slot:UnlockHighlight();
		end
	end

	local data = ns.FindDrawer(selected);
	local detail = window.detail;
	detail:SetShown(data ~= nil);
	window.empty:SetShown(data == nil);
	window.delete:SetEnabled(data ~= nil);
	window.add:SetEnabled(#drawers < ns.MAX_DRAWERS);
	if not data then
		return;
	end

	local handle = SelectedHandle();
	local entries = data.entries;
	detail.name:SetText("Drawer " .. data.id);
	detail.status:SetText(handle and handle.dock and "On an action bar" or "Floating");
	for index, mini in ipairs(detail.minis) do
		local entry = entries[index];
		mini.entry = entry;
		mini:SetShown(entry ~= nil);
		if entry then
			mini.icon:SetTexture(ns.EntryIcon(entry) or ns.QUESTION_MARK);
		end
	end
	detail.more:SetText(#entries > MINIS and "+" .. (#entries - MINIS) or "");
	detail.none:SetShown(#entries == 0);

	for key, radio in pairs(detail.directions) do
		radio:SetChecked(data.dir == key);
	end
	for _, mode in ipairs(MODES) do
		detail.modes[mode.key]:SetChecked(data.mode == mode.key);
		if data.mode == mode.key then
			detail.note:SetText(mode.note .. (mode.key == "cycle" and CycleRemarks(data, handle) or ""));
		end
	end
end

-- Brings the window in line with the drawers. It runs in the middle of the
-- drawers' own work (after every refresh of them), so a failure in here must
-- not get out: it closes the window for good instead.
Update = function()
	local ok, problem = pcall(Fill);
	if not ok then
		failed = true;
		window:Hide();
		ns.Print("could not fill the options window: " .. tostring(problem));
	end
end

-- Runs after every refresh of the drawers.
function ns.UpdateWindow()
	if window and not failed and window:IsShown() then
		Update();
	end
end

function ns.ToggleWindow()
	if not window and not failed then
		local ok, result = pcall(Build);
		if ok then
			window = result;
		else
			failed = true;
			ns.Print("could not build the options window: " .. tostring(result));
		end
	end
	if window and not failed then
		window:SetShown(not window:IsShown());
	end
	-- Not an else: showing the window is what fills it for the first time
	if failed then
		ns.PrintHelp();
	end
end

-- The minimap's addon menu
function SpellDrawer_OnAddonCompartmentClick()
	ns.ToggleWindow();
end
