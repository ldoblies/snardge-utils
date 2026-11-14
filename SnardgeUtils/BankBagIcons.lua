local _, ns = ...
if not ns.IsEnabled('bankBagIcons') or not Bagnon then
	return
end

-- Forever reports every bank slot as a tab with the question mark icon, and Bagnon draws the tab
-- icon instead of the bag's. The first tab is the base bank, whose "bag" is a placeholder item.
local QUESTION_MARK_ICON = 134400

local function OnUpdateInfo(bag)
	if bag.icon ~= QUESTION_MARK_ICON then
		return
	end

	if bag:GetID() == Bagnon.NumBags + 1 then
		bag.icon = Bagnon.Bag.StaticIcons[BANK_CONTAINER]
	elseif bag:IsCached() then
		local link = bag:GetInfo().link
		local icon = link and select(5, C_Item.GetItemInfoInstant('item:' .. link))
		bag.icon = icon or bag.icon
	else
		bag.icon = GetInventoryItemTexture('player', bag.slot) or bag.icon
	end
end

-- Bagnon_Bank is load on demand. ADDON_LOADED fires inside its LoadAddOn call, before the bank
-- frame builds its buttons, which is the last moment a class hook still reaches them.
local function Hook()
	hooksecurefunc(Bagnon.BankBag, 'UpdateInfo', OnUpdateInfo)
end

if C_AddOns.IsAddOnLoaded('Bagnon_Bank') then
	Hook()
else
	local frame = CreateFrame('Frame')
	frame:RegisterEvent('ADDON_LOADED')
	frame:SetScript('OnEvent', function(self, _, name)
		if name == 'Bagnon_Bank' then
			self:UnregisterEvent('ADDON_LOADED')
			Hook()
		end
	end)
end
