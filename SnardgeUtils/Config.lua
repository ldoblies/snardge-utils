local _, ns = ...

local TITLE = 'SnardgeUtils'
local ROW = 20
local COLUMN_GAP = 194
local COLUMN_WIDTH = 200
-- Leatrix Plus labels its own reload button with this
local RELOAD_LABEL = 'Reload'

local reloadValueByKey = {}
local reloadGetterByKey = {}
local reloadNotice

local function ShowTooltip(self)
	GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
	GameTooltip:SetText(self.tooltip, nil, nil, nil, nil, true)
	GameTooltip:Show()
end

local function ReloadPending()
	for key, get in pairs(reloadGetterByKey) do
		if get() ~= reloadValueByKey[key] then
			return true
		end
	end
	return false
end

-- The reload button is greyed out like Leatrix Plus does it until there is something to
-- reload. In Leatrix the button is shared, so it is left alone while Leatrix's own
-- "needs to be reloaded" message (the blocker) is up.
local function RefreshReloadNotice()
	if not reloadNotice then
		return
	end
	local pending = ReloadPending()
	local leatrixPending = reloadNotice.blocker and reloadNotice.blocker:IsShown()
	reloadNotice:SetShown(pending and not leatrixPending)
	local button = reloadNotice.button
	if button and not leatrixPending then
		button:SetEnabled(pending)
		button:SetAlpha(pending and 1 or 0.3)
	end
end

-- Remembers the value the addon loaded with, so the reload notice only shows while
-- something differs from it and goes away again when a change is undone
local function NeedsReload(key, get)
	reloadGetterByKey[key] = get
	reloadValueByKey[key] = get()
end

local function SetActive(control, active)
	if control:GetObjectType() == 'Slider' then
		if active then control:Enable() else control:Disable() end
		control.label:SetFontObject(active and 'GameFontHighlight' or 'GameFontDisable')
	else
		control:SetEnabled(active)
	end
	control.f:SetFontObject(active and 'GameFontHighlight' or 'GameFontDisable')
end

local function MakeHeading(parent, x, y, text)
	local heading = parent:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
	heading:SetPoint('TOPLEFT', x, y)
	heading:SetText(text)
end

local function MakeCheckbox(parent, x, y, label, tooltip, get, set)
	local box = CreateFrame('CheckButton', nil, parent, 'ChatConfigCheckButtonTemplate')
	box:SetPoint('TOPLEFT', x, y)
	box.f = box:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
	box.f:SetPoint('LEFT', 20, 0)
	box.f:SetText(label)
	box:SetHitRectInsets(0, -box.f:GetStringWidth() - 4, 0, 0)
	box.tooltip = tooltip
	box:SetScript('OnEnter', ShowTooltip)
	box:SetScript('OnLeave', GameTooltip_Hide)
	box:SetScript('OnShow', function(self) self:SetChecked(get()) end)
	box:SetScript('OnClick', function(self)
		set(self:GetChecked())
		RefreshReloadNotice()
	end)
	return box
end

-- Same atlas parts as Leatrix Plus' configuration slider, built here so the standalone
-- window does not depend on Leatrix's XML template
local function MakeSlider(parent, x, y, label, low, high, step, format, tooltip, get, set)
	local slider = CreateFrame('Slider', nil, parent)
	slider:SetOrientation('HORIZONTAL')
	slider:SetSize(100, 20)
	slider:SetPoint('TOPLEFT', x + 42, y)
	slider:SetHitRectInsets(0, 0, -10, -10)
	slider:SetMinMaxValues(low, high)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	slider:EnableMouseWheel(true)

	local left = slider:CreateTexture(nil, 'ARTWORK')
	left:SetAtlas('Minimal_SliderBar_Left', true)
	left:SetPoint('LEFT')
	local right = slider:CreateTexture(nil, 'ARTWORK')
	right:SetAtlas('Minimal_SliderBar_Right', true)
	right:SetPoint('RIGHT')
	local middle = slider:CreateTexture(nil, 'ARTWORK')
	middle:SetAtlas('_Minimal_SliderBar_Middle', true)
	middle:SetPoint('TOPLEFT', left, 'TOPRIGHT')
	middle:SetPoint('TOPRIGHT', right, 'TOPLEFT')
	local thumb = slider:CreateTexture(nil, 'OVERLAY')
	thumb:SetAtlas('Minimal_SliderBar_Button')
	thumb:SetSize(16, 16)
	slider:SetThumbTexture(thumb)

	slider.label = parent:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
	slider.label:SetPoint('RIGHT', slider, 'LEFT', -8, 0)
	slider.label:SetText(label)
	slider.f = slider:CreateFontString(nil, 'BACKGROUND', 'GameFontHighlight')
	slider.f:SetPoint('LEFT', slider, 'RIGHT', 12, 0)

	slider.tooltip = tooltip
	slider:SetScript('OnEnter', ShowTooltip)
	slider:SetScript('OnLeave', GameTooltip_Hide)
	slider:SetScript('OnMouseWheel', function(self, delta)
		if self:IsEnabled() then
			self:SetValue(Clamp(self:GetValue() + step * delta, low, high))
		end
	end)
	slider:SetScript('OnValueChanged', function(self, value)
		value = floor((value - low) / step + 0.5) * step + low
		self.f:SetFormattedText(format, value)
		set(value)
		RefreshReloadNotice()
	end)
	slider:SetScript('OnShow', function(self) self:SetValue(get()) end)
	return slider
end

-- Mailing belongs to Bag marks, so it greys out while that is off
local function BuildMailOptions(parent, x, y)
	local function active()
		return ns.IsEnabled('bagMarks')
	end

	local heading = parent:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
	heading:SetPoint('TOPLEFT', x, y)
	heading:SetText('Mail to')

	local recipient = CreateFrame('EditBox', nil, parent, 'InputBoxTemplate')
	recipient:SetSize(110, 20)
	recipient:SetPoint('LEFT', heading, 'RIGHT', 12, 0)
	recipient:SetAutoFocus(false)
	recipient:SetMaxLetters(40)
	recipient.tooltip = 'Character that gets items marked with Ctrl+Shift+click, as first name and surname. Mailing runs on its own when you open a mailbox on any other character.'
	recipient:SetScript('OnEnter', ShowTooltip)
	recipient:SetScript('OnLeave', GameTooltip_Hide)
	local function Save(self)
		SnardgeUtilsSettings.mailRecipient = strtrim(self:GetText())
		self:SetText(SnardgeUtilsSettings.mailRecipient)
	end
	recipient:SetScript('OnEnterPressed', function(self) self:ClearFocus() end)
	recipient:SetScript('OnEditFocusLost', Save)
	recipient:SetScript('OnEscapePressed', function(self)
		self:SetText(SnardgeUtilsSettings.mailRecipient)
		self:ClearFocus()
	end)

	local fullStacks = MakeCheckbox(parent, x, y - ROW + 2, 'Full stacks only',
		'Part stacks of items marked for mail stay in your bags until they fill up.',
		function() return SnardgeUtilsSettings.mailFullStacksOnly end,
		function(checked) SnardgeUtilsSettings.mailFullStacksOnly = checked end)

	recipient:SetScript('OnShow', function(self)
		self:SetText(SnardgeUtilsSettings.mailRecipient)
		local on = active()
		self:SetEnabled(on)
		self:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
		heading:SetFontObject(on and 'GameFontNormal' or 'GameFontDisable')
		SetActive(fullStacks, on)
	end)
end

-- Opens over the page like Leatrix Plus' configuration panels, with its own Done button
local function BuildClickPanel(parent, x, y)
	local panel = CreateFrame('Frame', nil, parent)
	panel:SetPoint('TOPLEFT', x - 8, y + 8)
	panel:SetPoint('BOTTOMRIGHT', -8, 48)
	panel:SetFrameLevel(parent:GetFrameLevel() + 20)
	panel:EnableMouse(true)
	panel:Hide()
	local background = panel:CreateTexture(nil, 'BACKGROUND')
	background:SetAllPoints()
	background:SetColorTexture(0.05, 0.05, 0.05, 0.97)

	MakeHeading(panel, 8, -8, 'Bag mark clicks')
	local hint = panel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
	hint:SetPoint('TOPLEFT', 8, -28)
	hint:SetPoint('RIGHT', -8, 0)
	hint:SetJustifyH('LEFT')
	hint:SetText('Left clicks on items in your bags. Picking a click another action uses swaps the two.')

	local dropdowns = {}
	for i, action in ipairs(ns.clickActions) do
		local label = panel:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
		label:SetPoint('TOPLEFT', 8, -36 - 28 * i)
		label:SetText(action.label)

		local dropdown = CreateFrame('DropdownButton', nil, panel, 'WowStyle1DropdownTemplate')
		dropdown:SetWidth(150)
		dropdown:SetPoint('LEFT', label, 'LEFT', 180, 0)
		dropdown:SetupMenu(function(_, root)
			for _, combo in ipairs(ns.clickCombos) do
				root:CreateRadio(ns.ComboLabel(combo),
					function() return SnardgeUtilsSettings.clicks[action.key] == combo end,
					function()
						ns.SetClick(action.key, combo)
						for _, other in ipairs(dropdowns) do
							other:GenerateMenu()
						end
					end)
			end
		end)
		dropdowns[#dropdowns + 1] = dropdown
	end

	BuildMailOptions(panel, 8, -36 - 28 * (#ns.clickActions + 1) - 4)

	local done = CreateFrame('Button', nil, panel, 'UIPanelButtonTemplate')
	done:SetSize(80, 22)
	done:SetPoint('BOTTOMRIGHT', -8, 8)
	done:SetText(DONE)
	done:SetScript('OnClick', function() panel:Hide() end)

	panel:SetScript('OnShow', function()
		for _, dropdown in ipairs(dropdowns) do
			dropdown:GenerateMenu()
		end
	end)
	parent:HookScript('OnHide', function() panel:Hide() end)
	return panel
end

-- Same cog as Leatrix Plus' CfgBtn, right of the checkbox label
local function MakeCogButton(box, tooltip, onClick)
	local cog = CreateFrame('Button', nil, box)
	cog:SetSize(20, 20)
	cog:SetPoint('LEFT', box.f, 'RIGHT', 0, 0)
	cog.t = cog:CreateTexture(nil, 'BORDER')
	cog.t:SetAllPoints()
	cog.t:SetTexture('Interface\\WorldMap\\Gear_64.png')
	cog.t:SetTexCoord(0, 0.50, 0, 0.50)
	cog.t:SetVertexColor(1.0, 0.82, 0, 1.0)
	cog:SetHighlightTexture('Interface\\WorldMap\\Gear_64.png')
	cog:GetHighlightTexture():SetTexCoord(0, 0.50, 0, 0.50)
	cog.tooltip = tooltip
	cog:SetScript('OnEnter', ShowTooltip)
	cog:SetScript('OnLeave', GameTooltip_Hide)
	cog:SetScript('OnClick', onClick)
	return cog
end

local function BuildFeatureOptions(parent, x, y)
	MakeHeading(parent, x, y, 'Features')
	local clickPanel = BuildClickPanel(parent, x, y)
	for row, module in ipairs(ns.modules) do
		local function get() return ns.IsEnabled(module.key) end
		NeedsReload(module.key, get)
		local box = MakeCheckbox(parent, x, y - ROW * row, module.label, module.tooltip, get,
			function(checked) ns.SetEnabled(module.key, checked) end)
		local missing = module.requires and not C_AddOns.IsAddOnLoaded(module.requires)
		if missing then
			box.f:SetText(module.label .. ' (needs ' .. module.requires .. ')')
			box:HookScript('OnShow', function() SetActive(box, false) end)
		elseif module.key == 'bagMarks' then
			MakeCogButton(box, 'Choose the clicks that mark items, and who gets the mail.', function() clickPanel:Show() end)
		end
	end
end

local function BuildLowHealthOptions(parent, x, y)
	local settings = ns.lowHealth.Settings
	local function enabled() return ns.IsEnabled('lowHealth') end
	NeedsReload('lowHealth', enabled)
	NeedsReload('lowHealthThreshold', function() return settings().threshold end)

	MakeHeading(parent, x, y, 'Low health')
	local threshold
	local box = MakeCheckbox(parent, x, y - ROW, 'Warning sound',
		'Plays the raid warning sound once each time your health drops below the threshold.',
		enabled,
		function(checked)
			ns.SetEnabled('lowHealth', checked)
			SetActive(threshold, checked)
		end)
	threshold = MakeSlider(parent, x + 20, y - ROW * 2 - 4, 'Below', 10, 50, 10, '%d%%',
		'Blizzard checks your health in 10% steps, so the threshold moves in 10% steps too.',
		function() return settings().threshold end,
		function(value) settings().threshold = value end)
	box:HookScript('OnShow', function() SetActive(threshold, enabled()) end)
end

local function BuildTargetMacroOptions(parent, x, y)
	local macro = ns.targetMacro
	local settings = macro.Settings

	MakeHeading(parent, x, y, 'Target macro')
	local farm, announce, range
	local box = MakeCheckbox(parent, x, y - ROW, 'Update ' .. macro.name .. ' macro',
		'Fills the ' .. macro.name .. ' macro with the nearest mobs your quests need, using Questie spawn data. Drag it from /macro onto an action bar once.',
		function() return settings().enabled end,
		function(checked)
			settings().enabled = checked
			macro.Update()
			SetActive(farm, checked)
			SetActive(announce, checked)
			SetActive(range, checked)
		end)
	farm = MakeCheckbox(parent, x, y - ROW * 2, 'Include farmed mobs',
		'Also targets mobs you looted at least twice in the last 30 minutes near where you are.',
		function() return settings().farm end,
		function(checked) settings().farm = checked; macro.Update() end)
	announce = MakeCheckbox(parent, x, y - ROW * 3, 'Announce changes',
		'Lists newly added mobs in chat, like RestedXP does. Each mob is announced once per session.',
		function() return settings().announce end,
		function(checked) settings().announce = checked end)
	range = MakeSlider(parent, x + 20, y - ROW * 4 - 4, 'Range', 50, 500, 25, '%d yd',
		'Mobs whose nearest spawn or kill spot is further away are left out.',
		function() return settings().radius end,
		function(value)
			if settings().radius ~= value then
				settings().radius = value
				macro.Update()
			end
		end)
	box:HookScript('OnShow', function()
		SetActive(farm, settings().enabled)
		SetActive(announce, settings().enabled)
		SetActive(range, settings().enabled)
	end)

	local now = parent:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
	now:SetPoint('TOPLEFT', x, y - ROW * 6 + 4)
	now:SetWidth(COLUMN_WIDTH)
	now:SetJustifyH('LEFT')

	local function ShowTargets(targets)
		now:SetText('Now targeting: ' .. (#targets > 0 and table.concat(targets, ', ') or 'nothing in range'))
	end
	macro.OnChange(ShowTargets)
	parent:HookScript('OnShow', function() ShowTargets(macro.Targets()) end)
end

-- Two columns, at the spacing Leatrix Plus uses for its own pages
local function BuildOptions(parent, x, y)
	BuildFeatureOptions(parent, x, y)
	BuildLowHealthOptions(parent, x + COLUMN_GAP, y)
	BuildTargetMacroOptions(parent, x + COLUMN_GAP, y - ROW * 4)
	parent:HookScript('OnShow', RefreshReloadNotice)
end

local function MakeReloadNotice(parent)
	reloadNotice = parent:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	reloadNotice:SetText('Reload to apply your changes.')
	reloadNotice:Hide()
	return reloadNotice
end

local function FindLeatrixReloadButton(panel)
	for _, child in ipairs({ panel:GetChildren() }) do
		if child:GetObjectType() == 'Button' and child.GetText and child:GetText() == RELOAD_LABEL then
			return child
		end
	end
end

local function IsLeatrixPage(frame)
	return frame:GetObjectType() == 'Frame' and type(frame.s) == 'table'
		and frame.s.GetObjectType and frame.s:GetObjectType() == 'FontString'
end

-- Leatrix Plus keeps its panel in a local table under a random global name, so find it by
-- its title among the escape-closable frames
local function FindLeatrixPanel()
	if not C_AddOns.IsAddOnLoaded('Leatrix_Plus') then
		return
	end
	for _, name in ipairs(UISpecialFrames) do
		local frame = _G[name]
		if frame and type(frame.mt) == 'table' and frame.mt.GetText and frame.mt:GetText() == 'Leatrix Plus' then
			return frame
		end
	end
end

-- Mirrors Leatrix's own page and menu button (MakePage and MakeMN). The slot between
-- System and Settings is the free one that still sits above the panel's footer.
local function AttachToLeatrix(panel)
	local page = CreateFrame('Frame', nil, panel)
	page:SetAllPoints(panel)
	page:Hide()

	local title = page:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
	title:SetPoint('TOPLEFT', 146, -16)
	title:SetText(TITLE)

	local button = CreateFrame('Button', nil, panel)
	button:SetSize(112, 20)
	button:SetPoint('TOPLEFT', 16, -252)
	button.t = button:CreateTexture(nil, 'BACKGROUND')
	button.t:SetAllPoints()
	button.t:SetColorTexture(0.3, 0.3, 0.00, 0.8)
	button.t:SetAlpha(0.7)
	button.t:Hide()
	button.s = button:CreateTexture(nil, 'BACKGROUND')
	button.s:SetAllPoints()
	button.s:SetColorTexture(0.3, 0.3, 0.00, 0.8)
	button.s:Hide()
	button.f = button:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
	button.f:SetPoint('LEFT', 16, 0)
	button.f:SetText(TITLE)
	button:SetScript('OnEnter', function() button.t:Show() end)
	button:SetScript('OnLeave', function() button.t:Hide() end)

	local leatrixPages = {}
	for _, child in ipairs({ panel:GetChildren() }) do
		if IsLeatrixPage(child) then
			leatrixPages[#leatrixPages + 1] = child
			child:HookScript('OnShow', function() page:Hide() end)
		end
	end

	button:SetScript('OnClick', function()
		for _, leatrixPage in ipairs(leatrixPages) do
			leatrixPage:Hide()
		end
		page:Show()
	end)
	page:SetScript('OnShow', function() button.s:Show() end)
	page:SetScript('OnHide', function() button.s:Hide() end)
	-- Leatrix hides the whole panel before showing a page, so reset here or this page
	-- would come back on top of Leatrix's next one
	panel:HookScript('OnHide', function() page:Hide() end)

	BuildOptions(page, 146, -72)

	local notice = MakeReloadNotice(page)
	local reloadButton = FindLeatrixReloadButton(panel)
	if reloadButton then
		notice:SetPoint('RIGHT', reloadButton, 'LEFT', -10, 0)
		notice.blocker = reloadButton.f
		notice.button = reloadButton
	else
		notice:SetPoint('BOTTOMRIGHT', -100, 18)
	end

	return function()
		if page:IsVisible() then
			panel:Hide()
		else
			panel:Show()
			button:Click()
		end
	end
end

local function CreateWindow()
	local window = CreateFrame('Frame', 'SnardgeUtilsConfigFrame', UIParent, 'BasicFrameTemplateWithInset')
	window:SetSize(440, 310)
	window:SetPoint('CENTER')
	window:SetFrameStrata('DIALOG')
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag('LeftButton')
	window:SetScript('OnDragStart', window.StartMoving)
	window:SetScript('OnDragStop', window.StopMovingOrSizing)
	window:Hide()
	tinsert(UISpecialFrames, window:GetName())

	local title = window:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	title:SetPoint('TOP', 0, -5)
	title:SetText(TITLE)

	BuildOptions(window, 16, -36)

	local reload = CreateFrame('Button', nil, window, 'UIPanelButtonTemplate')
	reload:SetSize(80, 22)
	reload:SetPoint('BOTTOMRIGHT', -10, 10)
	reload:SetText(RELOAD_LABEL)
	reload:SetScript('OnClick', ReloadUI)
	local notice = MakeReloadNotice(window)
	notice:SetPoint('RIGHT', reload, 'LEFT', -10, 0)
	notice.button = reload
	RefreshReloadNotice()

	return function()
		window:SetShown(not window:IsShown())
	end
end

local toggle

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:SetScript('OnEvent', function()
	local panel = FindLeatrixPanel()
	toggle = panel and AttachToLeatrix(panel) or CreateWindow()
end)

SLASH_SNARDGEUTILS1 = '/su'
SlashCmdList.SNARDGEUTILS = function()
	if toggle then
		toggle()
	end
end
