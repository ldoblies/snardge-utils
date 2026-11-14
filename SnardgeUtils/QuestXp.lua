local _, ns = ...
if not ns.IsEnabled('questXp') then
	return
end

local PREFIX = '|cff999999SnardgeUtils:|r '
local CONTAINERS = { 'MainStatusTrackingBarContainer', 'SecondaryStatusTrackingBarContainer' }

local bar, segment, text

local function ShortNumber(n)
	if n >= 1000 then
		return format('%.1fk', n / 1000)
	end
	return format('%d', n)
end

local function RewardXP(questID)
	local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(questID)
	if xp and xp > 0 then
		return xp
	end
	if QuestieLoader then
		local QuestXP = QuestieLoader:ImportModule('QuestXP')
		if QuestXP.GetQuestLogRewardXP then
			return QuestXP:GetQuestLogRewardXP(questID) or 0
		end
	end
	return 0
end

local function CompletedQuests()
	local quests = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID and C_QuestLog.IsComplete(info.questID) then
			quests[#quests + 1] = info.questID
		end
	end
	return quests
end

local function PendingXP()
	local total, count = 0, 0
	for _, questID in ipairs(CompletedQuests()) do
		local xp = RewardXP(questID)
		if xp > 0 then
			total = total + xp
			count = count + 1
		end
	end
	return total, count
end

-- The bars are created by the status tracking manager, so find the experience one by the
-- flag its template sets rather than by a field name
local function FindExpBar()
	for _, name in ipairs(CONTAINERS) do
		local container = _G[name]
		if container then
			for _, child in ipairs({ container:GetChildren() }) do
				if child.isExpBar then
					return child
				end
			end
		end
	end
end

local function Update()
	if not segment then
		return
	end

	local xp, xpMax = UnitXP('player'), UnitXPMax('player')
	local pending, count = PendingXP()
	if xpMax == 0 or pending == 0 or not bar:IsShown() then
		segment:Hide()
		text:SetText('')
		return
	end

	segment:SetWidth(max(1, bar:GetWidth() * min(1, (xp + pending) / xpMax)))
	segment:Show()

	local levels = (xp + pending) >= xpMax and format(', reaches %d', UnitLevel('player') + 1) or ''
	text:SetFormattedText('+%s from %d |4quest:quests; (%d%%%s)', ShortNumber(pending), count, pending / xpMax * 100, levels)
end

-- Anchored like Blizzard's rested prediction (ExhaustionLevelFillBar), one sublevel above it
-- so a smaller quest segment still shows over a longer rested one. The fill itself is a
-- child StatusBar and draws on top of both.
local function Create()
	bar = FindExpBar()
	if not bar or segment then
		return
	end

	segment = bar:CreateTexture(nil, 'ARTWORK', nil, 0)
	segment:SetPoint('TOPLEFT')
	segment:SetPoint('BOTTOMLEFT')
	segment:SetColorTexture(1, 0.75, 0.1, 0.6)
	segment:Hide()

	local holder = CreateFrame('Frame', nil, bar)
	holder:SetAllPoints(bar)
	holder:SetFrameLevel(bar:GetFrameLevel() + 10)
	text = holder:CreateFontString(nil, 'OVERLAY', 'TextStatusBarText')
	text:SetPoint('LEFT', holder, 'LEFT', 6, 0)

	bar:HookScript('OnSizeChanged', Update)
	bar:HookScript('OnShow', Update)
	bar:HookScript('OnHide', Update)
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:RegisterEvent('QUEST_LOG_UPDATE')
frame:RegisterEvent('PLAYER_XP_UPDATE')
frame:RegisterEvent('PLAYER_LEVEL_UP')
frame:SetScript('OnEvent', function(_, event)
	if event == 'PLAYER_ENTERING_WORLD' then
		Create()
	end
	Update()
end)

SLASH_SUQXP1 = '/suqxp'
SlashCmdList.SUQXP = function()
	if not bar then
		print(PREFIX .. 'experience bar not found in the status tracking containers')
		return
	end
	print(PREFIX .. 'completed quests ready to hand in:')
	for _, questID in ipairs(CompletedQuests()) do
		print(format('  %s: %d xp', C_QuestLog.GetTitleForQuestID(questID) or questID, RewardXP(questID)))
	end
	local pending = PendingXP()
	print(format('%stotal %d xp, bar %d / %d', PREFIX, pending, UnitXP('player'), UnitXPMax('player')))
end
