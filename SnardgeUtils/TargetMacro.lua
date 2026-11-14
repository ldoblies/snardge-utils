local ADDON_NAME, ns = ...

local MACRO_NAME = 'SUTarget'
local MACRO_ICON = 'Ability_Hunter_SniperShot'
local MACRO_LIMIT = 255
-- /targetexact also picks corpses, so step back to the previous target if the last match is dead
local DEAD_FALLBACK = '\n/targetlasttarget [dead]'
local REFRESH = 5
local KILL_WINDOW = 1800
local MIN_KILLS = 2

local DEFAULTS = {
	enabled = true,
	radius = 200,
	farm = true,
	announce = true,
}

local kills = {}
local lootedGUIDs = {}
local targets = {}
local announcedNames = {}
local listeners = {}
local ready = false

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

local function Settings()
	return SnardgeUtilsSettings.targetMacro
end

local function Consider(distanceByName, name, distance, radius)
	if distance and distance <= radius and (not distanceByName[name] or distance < distanceByName[name]) then
		distanceByName[name] = distance
	end
end

-- Questie keeps each logged quest's objectives with the spawns of every mob that counts
-- for them, including the mobs that drop a needed item (marked Hostile, unlike objects
-- and vendors). Distances come from Questie's own helper, in world yards.
local function AddQuestTargets(distanceByName, radius)
	if not (QuestieLoader and Questie and Questie.started) then
		return
	end
	local ActiveQuests = QuestieLoader:ImportModule('ActiveQuests')
	local DistanceUtils = QuestieLoader:ImportModule('DistanceUtils')
	if not (ActiveQuests.GetAll and DistanceUtils.GetNearestSpawn) then
		return
	end

	for _, acceptance in pairs(ActiveQuests.GetAll()) do
		local quest = acceptance.quest
		if quest and quest.Objectives and quest:IsComplete() ~= 1 then
			for _, objective in pairs(quest.Objectives) do
				if not objective.Completed and objective.spawnList then
					for _, spawn in pairs(objective.spawnList) do
						if spawn.Hostile and spawn.Name and spawn.Spawns then
							local _, _, distance = DistanceUtils.GetNearestSpawn(spawn.Spawns)
							Consider(distanceByName, spawn.Name, distance, radius)
						end
					end
				end
			end
		end
	end
end

local function PlayerPosition()
	local y, x, _, instance = UnitPosition('player')
	if x and y and Readable(x, y, instance) then
		return x, y, instance
	end
end

local function AddFarmTargets(distanceByName, radius)
	local x, y, instance = PlayerPosition()
	if not x then
		return
	end

	local cutoff = GetTime() - KILL_WINDOW
	local countByName, distanceByKillName = {}, {}
	for _, kill in ipairs(kills) do
		if kill.at >= cutoff and kill.instance == instance then
			local distance = sqrt((kill.x - x) ^ 2 + (kill.y - y) ^ 2)
			if distance <= radius then
				countByName[kill.name] = (countByName[kill.name] or 0) + 1
				Consider(distanceByKillName, kill.name, distance, radius)
			end
		end
	end
	for name, count in pairs(countByName) do
		if count >= MIN_KILLS then
			Consider(distanceByName, name, distanceByKillName[name], radius)
		end
	end
end

local function CollectTargets()
	local settings = Settings()
	local distanceByName = {}
	AddQuestTargets(distanceByName, settings.radius)
	if settings.farm then
		AddFarmTargets(distanceByName, settings.radius)
	end

	local names = {}
	for name in pairs(distanceByName) do
		names[#names + 1] = name
	end
	sort(names, function(a, b) return distanceByName[a] < distanceByName[b] end)
	return names
end

-- Later /targetexact lines win when they find their mob, so the nearest name goes last.
-- Names that do not fit in the macro are dropped from the far end.
local function BuildBody(names)
	local lines = {}
	local length = #DEAD_FALLBACK
	local kept = {}
	for _, name in ipairs(names) do
		local line = '/targetexact ' .. name
		local added = #line + (#lines > 0 and 1 or 0)
		if length + added > MACRO_LIMIT then
			break
		end
		tinsert(lines, 1, line)
		kept[#kept + 1] = name
		length = length + added
	end
	if #lines == 0 then
		return '', kept
	end
	return table.concat(lines, '\n') .. DEAD_FALLBACK, kept
end

local function Notify()
	for _, listener in ipairs(listeners) do
		listener(targets)
	end
end

-- Like RestedXP, each mob is announced once per session, so walking in and out of range of
-- the same mobs stays quiet
local function Announce(names)
	if not Settings().announce then
		return
	end
	local fresh = {}
	for _, name in ipairs(names) do
		if not announcedNames[name] then
			announcedNames[name] = true
			fresh[#fresh + 1] = name
		end
	end
	if #fresh > 0 then
		local color = ChatTypeInfo and ChatTypeInfo.SYSTEM
		DEFAULT_CHAT_FRAME:AddMessage(MACRO_NAME .. ' macro updated with: ' .. table.concat(fresh, ', '),
			color and color.r, color and color.g, color and color.b)
	end
end

local function Update()
	if not ready or not Settings().enabled or InCombatLockdown() then
		return
	end

	local body, kept = BuildBody(CollectTargets())
	targets = kept
	Announce(kept)

	if not GetMacroInfo(MACRO_NAME) then
		if GetNumMacros() >= (MAX_ACCOUNT_MACROS or 120) then
			return
		end
		CreateMacro(MACRO_NAME, MACRO_ICON, body)
	elseif GetMacroBody(MACRO_NAME) ~= body then
		EditMacro(MACRO_NAME, nil, nil, body)
	end
	Notify()
end

local function NpcName(guid, npcID)
	for _, unit in ipairs({ 'target', 'mouseover' }) do
		local unitGUID = UnitGUID(unit)
		if unitGUID and Readable(unitGUID) and unitGUID == guid then
			local name = UnitName(unit)
			if name and Readable(name) then
				return name
			end
		end
	end
	if QuestieLoader then
		local QuestieDB = QuestieLoader:ImportModule('QuestieDB')
		if QuestieDB.QueryNPCSingle then
			return QuestieDB.QueryNPCSingle(npcID, 'name')
		end
	end
end

local function RecordKill(guid)
	if lootedGUIDs[guid] then
		return
	end
	local unitType, _, _, _, _, npcID = strsplit('-', guid)
	if unitType ~= 'Creature' then
		return
	end
	lootedGUIDs[guid] = true

	local name = NpcName(guid, tonumber(npcID))
	local x, y, instance = PlayerPosition()
	if name and x then
		kills[#kills + 1] = { name = name, x = x, y = y, instance = instance, at = GetTime() }
	end
end

local function PruneKills()
	local cutoff = GetTime() - KILL_WINDOW
	while kills[1] and kills[1].at < cutoff do
		tremove(kills, 1)
	end
end

-- The combat log is closed to addons on Forever, so a kill is counted when its corpse is
-- looted: the loot source GUID names the mob, and looting happens out of combat where
-- GUIDs and names read normally.
local function OnLootOpened()
	if not GetLootSourceInfo then
		return
	end
	for slot = 1, GetNumLootItems() do
		local guid = GetLootSourceInfo(slot)
		if guid and Readable(guid) then
			RecordKill(guid)
		end
	end
end

ns.targetMacro = {
	name = MACRO_NAME,
	Update = Update,
	Settings = Settings,
	Targets = function() return targets end,
	OnChange = function(listener) listeners[#listeners + 1] = listener end,
}

local frame = CreateFrame('Frame')
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:RegisterEvent('PLAYER_REGEN_ENABLED')
frame:RegisterEvent('LOOT_OPENED')
frame:SetScript('OnEvent', function(_, event, name)
	if event == 'ADDON_LOADED' then
		if name ~= ADDON_NAME then
			return
		end
		SnardgeUtilsSettings = SnardgeUtilsSettings or {}
		SnardgeUtilsSettings.targetMacro = SnardgeUtilsSettings.targetMacro or {}
		for key, value in pairs(DEFAULTS) do
			if SnardgeUtilsSettings.targetMacro[key] == nil then
				SnardgeUtilsSettings.targetMacro[key] = value
			end
		end
		C_Timer.NewTicker(REFRESH, function()
			PruneKills()
			Update()
		end)
	elseif event == 'LOOT_OPENED' then
		OnLootOpened()
	else
		-- Creating the macro before the game has loaded the macro list would add a duplicate
		ready = ready or event == 'PLAYER_ENTERING_WORLD'
		Update()
	end
end)
