local _, ns = ...
if not ns.IsEnabled('summonAnnounce') then
	return
end

local summoner

local function Readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- Players only summon members of their own group, so the summoner is one of the group units.
-- Forever's first names repeat across surnames but hardly within one group.
local function FindSummonerUnit(name)
	local firstName = strsplit(' -', name)
	local prefix = IsInRaid() and 'raid' or 'party'
	local count = IsInRaid() and MAX_RAID_MEMBERS or MAX_PARTY_MEMBERS
	for i = 1, count do
		local unit = prefix .. i
		local first = UnitFullName(unit)
		if Readable(first) and strlower(first) == strlower(firstName) then
			return unit
		end
	end
end

-- UnitPosition's instance ID is the continent outdoors and the dungeon's map inside one, the
-- same IDs GetInstanceInfo gives, so a different ID means a loading screen. It returns nothing
-- for a summoner inside an instance, and then the summon is not announced.
local function NeedsLoadingScreen(unit)
	local _, _, _, there = UnitPosition(unit)
	local here = select(8, GetInstanceInfo())
	return Readable(there) and Readable(here) and there ~= here
end

local function Announce(unit)
	local message = strtrim(SnardgeUtilsSettings.summonMessage)
	if message == '' then
		return
	end
	if SnardgeUtilsSettings.summonChannel == 'WHISPER' then
		-- Forever whispers go to "First Surname"
		local first, surname = UnitFullName(unit)
		SendChatMessage(message, 'WHISPER', nil, surname and surname ~= '' and (first .. ' ' .. surname) or first)
	else
		SendChatMessage(message, IsInRaid() and 'RAID' or 'PARTY')
	end
end

-- Hooking the API rather than the popup also catches auto accepts, like Leatrix Plus' one
hooksecurefunc(C_SummonInfo, 'ConfirmSummon', function()
	local unit = summoner and FindSummonerUnit(summoner)
	if unit and NeedsLoadingScreen(unit) then
		Announce(unit)
	end
end)

local frame = CreateFrame('Frame')
frame:RegisterEvent('CONFIRM_SUMMON')
frame:SetScript('OnEvent', function()
	local name = C_SummonInfo.GetSummonConfirmSummoner()
	summoner = Readable(name) and name or nil
end)
