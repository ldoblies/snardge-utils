local _, ns = ...
if not ns.IsEnabled('manaRegen') then
	return
end

local PREFIX = '|cff999999SnardgeUtils:|r '

local FIVE_SECOND_RULE = 5
local REFRESH = 0.5
local MANA = Enum.PowerType.Mana

local text
local lastSpend = 0

-- Forever returns the player's own mana as a secret value, so it cannot be compared to
-- decide when mana is full. Evaluate the mana percent through a curve instead and hand the
-- secret result straight to SetAlpha: visible below 100%, hidden at 100%.
local hideWhenFull = C_CurveUtil.CreateCurve()
hideWhenFull:SetType(Enum.LuaCurveType.Step)
hideWhenFull:AddPoint(0, 1)
hideWhenFull:AddPoint(1, 0)

local function Readable(...)
	if not issecretvalue then
		return true
	end
	for i = 1, select('#', ...) do
		if issecretvalue((select(i, ...))) then
			return false
		end
	end
	return true
end

local function InFiveSecondRule()
	return GetTime() - lastSpend < FIVE_SECOND_RULE
end

local function Update()
	if not text then
		return
	end

	if UnitPowerType('player') ~= MANA then
		text:SetText('')
		return
	end

	local notCasting, casting = GetManaRegen()
	if Readable(notCasting, casting) then
		text:SetFormattedText('%.1f/s', InFiveSecondRule() and casting or notCasting)
	end
	text:SetAlpha(UnitPowerPercent('player', MANA, false, hideWhenFull))
end

local function CostsMana(spellID)
	local costs = C_Spell.GetSpellPowerCost(spellID)
	if not costs then
		return false
	end
	for _, cost in ipairs(costs) do
		if cost.type == MANA and Readable(cost.cost) and cost.cost > 0 then
			return true
		end
	end
	return false
end

local function CreateText()
	local bar = PlayerFrame_GetManaBar and PlayerFrame_GetManaBar() or _G.PlayerFrameManaBar
	if text or not bar then
		return
	end

	-- The player frame's border art sits on a higher frame level than the mana bar, so a font
	-- string on the bar itself can paint underneath it. Use a holder above the whole frame.
	local holder = CreateFrame('Frame', nil, PlayerFrame)
	holder:SetAllPoints(bar)
	holder:SetFrameStrata(PlayerFrame:GetFrameStrata())
	holder:SetFrameLevel(PlayerFrame:GetFrameLevel() + 20)

	text = holder:CreateFontString(nil, 'OVERLAY', 'TextStatusBarText')
	text:SetPoint('LEFT', holder, 'RIGHT', 4, 0)

	C_Timer.NewTicker(REFRESH, Update)
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:RegisterUnitEvent('UNIT_POWER_UPDATE', 'player')
frame:RegisterUnitEvent('UNIT_DISPLAYPOWER', 'player')
frame:RegisterUnitEvent('UNIT_SPELLCAST_SUCCEEDED', 'player')
frame:SetScript('OnEvent', function(_, event, _, _, spellID)
	if event == 'UNIT_SPELLCAST_SUCCEEDED' then
		if Readable(spellID) and CostsMana(spellID) then
			lastSpend = GetTime()
		end
	elseif event == 'PLAYER_ENTERING_WORLD' then
		CreateText()
	end
	Update()
end)

SLASH_SUMANA1 = '/sumana'
SlashCmdList.SUMANA = function()
	if not text then
		print(PREFIX .. 'player mana bar not found, nothing to attach the rate to')
		return
	end
	local notCasting, casting = GetManaRegen()
	if not Readable(notCasting, casting) then
		print(PREFIX .. 'mana regen is secret right now, try out of combat')
		return
	end
	print(format('%smana regen %.1f/s not casting, %.1f/s while casting (%d%%), five-second rule %s, showing "%s"',
		PREFIX, notCasting, casting, notCasting > 0 and casting / notCasting * 100 or 0,
		InFiveSecondRule() and 'active' or 'inactive', text:GetText() or ''))
end
