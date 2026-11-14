local _, ns = ...
if not ns.IsEnabled('xpRate') then
	return
end

local PREFIX = '|cff999999SnardgeUtils:|r '

local WINDOW = 600
local REFRESH = 5

local sessionStart = GetTime()
local sessionXP = 0
local samples = {}
local lastXP, lastMax = 0, 0
local initialized = false
local text

local function CurrentXP()
	return UnitXP('player') or 0, UnitXPMax('player') or 0
end

local function Snapshot()
	lastXP, lastMax = CurrentXP()
	initialized = true
end

local function ShortNumber(n)
	if n >= 1000 then
		return format('%.1fk', n / 1000)
	end
	return format('%d', n)
end

local function Prune(now)
	local cutoff = now - WINDOW
	while samples[1] and samples[1].at < cutoff do
		tremove(samples, 1)
	end
end

local function Rates()
	local now = GetTime()
	Prune(now)

	local recentXP = 0
	for i = 1, #samples do
		recentXP = recentXP + samples[i].amount
	end

	-- Early in a session the window has not filled yet, so rate it over the time actually
	-- played rather than the full 10 minutes, which would read far too low.
	local recentSpan = min(WINDOW, now - sessionStart)
	local sessionSpan = now - sessionStart

	local recent = recentSpan > 0 and (recentXP / recentSpan * 3600) or 0
	local average = sessionSpan > 0 and (sessionXP / sessionSpan * 3600) or 0
	return recent, average
end

local function Update()
	if not text then
		return
	end

	local _, max = CurrentXP()
	if max == 0 or (IsXPUserDisabled and IsXPUserDisabled()) then
		text:SetText('')
		return
	end

	local recent, average = Rates()
	text:SetFormattedText('%s now / %s avg', ShortNumber(recent), ShortNumber(average))
end

local function OnXPUpdate()
	local xp, max = CurrentXP()

	if not initialized or max == 0 then
		Snapshot()
		Update()
		return
	end

	local gained
	if max == lastMax and xp >= lastXP then
		gained = xp - lastXP
	else
		-- Levelling resets the bar, so the gain spans what was left of the old level plus
		-- the progress into the new one.
		gained = (lastMax - lastXP) + xp
	end

	lastXP, lastMax = xp, max

	if gained > 0 then
		sessionXP = sessionXP + gained
		samples[#samples + 1] = {at = GetTime(), amount = gained}
	end

	Update()
end

local function CreateText()
	local bar = _G.MainStatusTrackingBarContainer
	if text or not bar then
		return
	end

	-- The status bars are child frames of the container, so a font string on the container
	-- itself paints underneath them. Give it a holder with a higher frame level instead.
	local holder = CreateFrame('Frame', nil, bar)
	holder:SetAllPoints(bar)
	holder:SetFrameLevel(bar:GetFrameLevel() + 10)

	text = holder:CreateFontString(nil, 'OVERLAY', 'TextStatusBarText')
	text:SetPoint('RIGHT', holder, 'RIGHT', -6, 0)

	C_Timer.NewTicker(REFRESH, Update)
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:RegisterEvent('PLAYER_XP_UPDATE')
frame:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_XP_UPDATE' then
		OnXPUpdate()
		return
	end

	CreateText()
	Snapshot()
	Update()
end)

SLASH_SUXP1 = '/suxp'
SlashCmdList.SUXP = function(msg)
	if strlower(strtrim(msg or '')) == 'reset' then
		sessionStart = GetTime()
		sessionXP = 0
		wipe(samples)
		Snapshot()
		Update()
		print(PREFIX .. 'xp rate reset')
		return
	end

	if not _G.MainStatusTrackingBarContainer then
		print(PREFIX .. 'MainStatusTrackingBarContainer not found, nothing to attach the rate to')
		return
	end

	local recent, average = Rates()
	print(format('%sxp/hr recent %s, session %s (%d xp over %s, %d samples)',
		PREFIX, ShortNumber(recent), ShortNumber(average), sessionXP,
		SecondsToTime(GetTime() - sessionStart), #samples))
end
