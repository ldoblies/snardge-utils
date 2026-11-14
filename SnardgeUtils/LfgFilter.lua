local ADDON_NAME, ns = ...
if not ns.IsEnabled('lfgFilter') then
	return
end
local LFG_ADDON = 'Blizzard_GroupFinder_VanillaStyle'

local CLASSES = { 'WARRIOR', 'PALADIN', 'HUNTER', 'ROGUE', 'PRIEST', 'SHAMAN', 'MAGE', 'WARLOCK', 'DRUID' }
local ROLES = {
	{ key = 'tank', token = 'TANK', label = TANK },
	{ key = 'healer', token = 'HEALER', label = HEALER },
	{ key = 'dps', token = 'DAMAGER', label = DAMAGER },
}

local function IsActive()
	return next(SnardgeUtilsLfgFilter.classes) ~= nil or next(SnardgeUtilsLfgFilter.roles) ~= nil
end

local function MemberMatches(member)
	local filter = SnardgeUtilsLfgFilter
	if next(filter.classes) and not filter.classes[member.classFilename] then
		return false
	end
	if not next(filter.roles) then
		return true
	end
	for _, role in ipairs(ROLES) do
		if filter.roles[role.key] and ((member.lfgRoles and member.lfgRoles[role.key]) or member.assignedRole == role.token) then
			return true
		end
	end
	return false
end

local function ResultMatches(resultID)
	local info = C_LFGList.GetSearchResultInfo(resultID)
	if info.hasSelf then
		return true
	end
	for i = 1, info.numMembers do
		local member = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
		if member and MemberMatches(member) then
			return true
		end
	end
	return false
end

-- Blizzard sorts the fresh result list right before drawing it, so filtering the
-- same table in place here hides entries without replacing any Blizzard method
local function FilterResults(results)
	if not IsActive() then
		return
	end
	for i = #results, 1, -1 do
		if not ResultMatches(results[i]) then
			tremove(results, i)
		end
	end
end

local function LeaderLevel(resultID)
	local leader = C_LFGList.GetSearchResultLeaderInfo(resultID)
	return leader and leader.level or 0
end

-- Re-sorts after Blizzard's sort, keeping its rule that your own listing stays on top and
-- its order among listings of the same level
local function SortByLevel(results)
	if not SnardgeUtilsLfgFilter.sortByLevel then
		return
	end
	local levelByResult, selfByResult, orderByResult = {}, {}, {}
	for i, resultID in ipairs(results) do
		levelByResult[resultID] = LeaderLevel(resultID)
		selfByResult[resultID] = C_LFGList.GetSearchResultInfo(resultID).hasSelf
		orderByResult[resultID] = i
	end
	sort(results, function(a, b)
		if selfByResult[a] ~= selfByResult[b] then
			return selfByResult[a]
		end
		if levelByResult[a] ~= levelByResult[b] then
			return levelByResult[a] > levelByResult[b]
		end
		return orderByResult[a] < orderByResult[b]
	end)
end

local function ProcessResults(results)
	FilterResults(results)
	SortByLevel(results)
end

local function ShowEmptyMessage(browse)
	if browse.searching or browse.searchFailed or not browse.results then
		return
	end
	if browse.totalResults > 0 and #browse.results == 0 then
		browse.NoResultsFound:SetText('No listings match your class and role filter.')
		browse.NoResultsFound:Show()
	end
end

local function Apply()
	if LFGBrowseFrame and LFGBrowseFrame:IsVisible() then
		LFGBrowseFrame:UpdateResultList()
	end
end

local function Toggle(set, key)
	set[key] = not set[key] or nil
	Apply()
end

Menu.ModifyMenu('MENU_LFG_LISTING_SETTINGS', function(_, root)
	local filter = SnardgeUtilsLfgFilter

	root:CreateDivider()
	root:CreateCheckbox('Sort by level, highest first',
		function() return filter.sortByLevel end,
		function() filter.sortByLevel = not filter.sortByLevel; Apply() end)

	root:CreateDivider()
	root:CreateTitle('Roles')
	for _, role in ipairs(ROLES) do
		root:CreateCheckbox(role.label,
			function() return filter.roles[role.key] end,
			function() Toggle(filter.roles, role.key) end)
	end

	root:CreateDivider()
	root:CreateTitle('Classes')
	for _, class in ipairs(CLASSES) do
		local name = RAID_CLASS_COLORS[class]:WrapTextInColorCode(LOCALIZED_CLASS_NAMES_MALE[class])
		root:CreateCheckbox(name,
			function() return filter.classes[class] end,
			function() Toggle(filter.classes, class) end)
	end

	root:CreateDivider()
	root:CreateButton('Clear filters', function()
		wipe(filter.roles)
		wipe(filter.classes)
		Apply()
	end)
end)

local hooked = false

local function HookBrowse()
	if hooked or not LFGBrowseFrame then
		return
	end
	hooksecurefunc('LFGBrowseUtil_SortSearchResults', ProcessResults)
	hooksecurefunc(LFGBrowseFrame, 'UpdateResults', ShowEmptyMessage)
	hooked = true
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('ADDON_LOADED')
frame:SetScript('OnEvent', function(_, _, name)
	if name == ADDON_NAME then
		SnardgeUtilsLfgFilter = SnardgeUtilsLfgFilter or {}
		SnardgeUtilsLfgFilter.classes = SnardgeUtilsLfgFilter.classes or {}
		SnardgeUtilsLfgFilter.roles = SnardgeUtilsLfgFilter.roles or {}
		if SnardgeUtilsLfgFilter.sortByLevel == nil then
			SnardgeUtilsLfgFilter.sortByLevel = true
		end
		if C_AddOns.IsAddOnLoaded(LFG_ADDON) then
			HookBrowse()
		end
	elseif name == LFG_ADDON then
		HookBrowse()
	end
end)
