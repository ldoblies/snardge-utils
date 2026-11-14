local _, ns = ...
if not ns.IsEnabled('priceAlert') or not C_AddOns.IsAddOnLoaded('TradeSkillMaster') then
	return
end

local PREFIX = '|cff999999SnardgeUtils:|r '
local MIN_RATIO = 1.2
local MAX_ROWS = 15
local ROW_HEIGHT = 20
local LOGIN_DELAY = 8
local RETRY_DELAY = 20
local POOR_QUALITY = 0

-- Commodities (cloth, ore, herbs) only have region-wide prices on Forever, so each side falls
-- back from the realm's own data to the region's
local NOW_PRICE = 'first(dbrecent, dbmarket, dbregionmarketavg)'
local USUAL_PRICE = 'first(dbhistorical, dbregionhistorical)'

-- includes the reagent bag, which sits one past NUM_BAG_SLOTS
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS

local frame
local rows = {}

local function Price(source, itemID)
	local ok, value = pcall(TSM_API.GetCustomPriceValue, source, 'i:' .. itemID)
	return ok and type(value) == 'number' and value > 0 and value or nil
end

local function AddSellable(countByItemID, info)
	if info and info.itemID and not info.isBound and info.quality ~= POOR_QUALITY then
		countByItemID[info.itemID] = (countByItemID[info.itemID] or 0) + (info.stackCount or 1)
	end
end

local function BankBagIDs()
	if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum.BankType then
		return C_Bank.FetchPurchasedBankTabIDs(Enum.BankType.Character) or {}
	end
	local ids = { BANK_CONTAINER }
	for i = 1, NUM_BANKBAGSLOTS or 0 do
		ids[#ids + 1] = NUM_BAG_SLOTS + i
	end
	return ids
end

-- The bank cannot be read away from a banker, so its contents are remembered from the last visit
local function RememberBank()
	local countByItemID = {}
	for _, bag in ipairs(BankBagIDs()) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			AddSellable(countByItemID, C_Container.GetContainerItemInfo(bag, slot))
		end
	end
	SnardgeUtilsBankItems = countByItemID
end

local function OwnedSellables()
	local countByItemID = {}
	for bag = 0, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			AddSellable(countByItemID, C_Container.GetContainerItemInfo(bag, slot))
		end
	end
	for itemID, count in pairs(SnardgeUtilsBankItems or {}) do
		countByItemID[itemID] = (countByItemID[itemID] or 0) + count
	end
	return countByItemID
end

-- Returns the items selling for at least MIN_RATIO of their usual price, highest ratio first,
-- and whether TSM had a usual price for any owned item at all
local function FindHighPrices()
	local found, priced = {}, false
	for itemID, count in pairs(OwnedSellables()) do
		local usual = Price(USUAL_PRICE, itemID)
		local now = usual and Price(NOW_PRICE, itemID)
		if usual then
			priced = true
		end
		if now and now >= usual * MIN_RATIO then
			found[#found + 1] = { itemID = itemID, count = count, now = now, ratio = now / usual }
		end
	end
	table.sort(found, function(a, b) return a.ratio > b.ratio end)
	return found, priced
end

local function ShowRowTooltip(row)
	GameTooltip:SetOwner(row, 'ANCHOR_RIGHT')
	GameTooltip:SetItemByID(row.itemID)
	GameTooltip:Show()
end

local function BuildFrame()
	frame = CreateFrame('Frame', 'SnardgeUtilsPriceAlertFrame', UIParent, 'BasicFrameTemplateWithInset')
	frame:SetSize(460, 60 + MAX_ROWS * ROW_HEIGHT)
	frame:SetPoint('CENTER')
	frame:SetFrameStrata('DIALOG')
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag('LeftButton')
	frame:SetScript('OnDragStart', frame.StartMoving)
	frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, frame:GetName())

	local title = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	title:SetPoint('TOP', 0, -5)
	title:SetText('Selling high right now')

	frame.header = frame:CreateFontString(nil, 'ARTWORK', 'GameFontNormalSmall')
	frame.header:SetPoint('TOPLEFT', 14, -32)
	frame.header:SetPoint('RIGHT', -14, 0)
	frame.header:SetJustifyH('LEFT')

	for i = 1, MAX_ROWS do
		local row = CreateFrame('Frame', nil, frame)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint('TOPLEFT', 12, -48 - (i - 1) * ROW_HEIGHT)
		row:SetPoint('RIGHT', -12, 0)
		row:EnableMouse(true)
		row:SetScript('OnEnter', ShowRowTooltip)
		row:SetScript('OnLeave', GameTooltip_Hide)
		row.item = row:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
		row.item:SetPoint('LEFT', 2, 0)
		row.item:SetWidth(210)
		row.item:SetJustifyH('LEFT')
		row.item:SetWordWrap(false)
		row.ratio = row:CreateFontString(nil, 'ARTWORK', 'GameFontGreen')
		row.ratio:SetPoint('LEFT', row.item, 'RIGHT', 6, 0)
		row.ratio:SetWidth(50)
		row.ratio:SetJustifyH('RIGHT')
		row.price = row:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
		row.price:SetPoint('RIGHT', -2, 0)
		row.price:SetJustifyH('RIGHT')
		rows[i] = row
	end
end

local function Show(found)
	if not frame then
		BuildFrame()
	end
	frame.header:SetText(format('%d of your items sell for at least %d%% of their usual price. Item, price vs usual, price each.',
		#found, MIN_RATIO * 100))
	for i, row in ipairs(rows) do
		local entry = found[i]
		if entry then
			local name, link = C_Item.GetItemInfo(entry.itemID)
			row.itemID = entry.itemID
			row.item:SetText(format('%s x%d', link or name or ('item ' .. entry.itemID), entry.count))
			row.ratio:SetText(format('%d%%', entry.ratio * 100 + 0.5))
			row.price:SetText(GetMoneyString(entry.now, true))
			row:Show()
		else
			row:Hide()
		end
	end
	frame:SetHeight(60 + math.min(#found, MAX_ROWS) * ROW_HEIGHT)
	frame:Show()
end

-- TSM loads its price data a few seconds after login; with no usual price for anything yet,
-- try once more later
local function Check(retried, fromCommand)
	local found, priced = FindHighPrices()
	if not priced and not retried and not fromCommand then
		C_Timer.After(RETRY_DELAY, function() Check(true) end)
		return
	end
	if #found > 0 then
		Show(found)
	elseif fromCommand then
		print(PREFIX .. (priced and 'none of your items sell for more than usual right now' or 'TSM has no prices yet'))
	end
end

local events = CreateFrame('Frame')
events:RegisterEvent('PLAYER_ENTERING_WORLD')
events:RegisterEvent('BANKFRAME_OPENED')
events:RegisterEvent('BAG_UPDATE_DELAYED')
local atBank = false
events:SetScript('OnEvent', function(_, event, isInitialLogin)
	if event == 'PLAYER_ENTERING_WORLD' then
		if isInitialLogin then
			C_Timer.After(LOGIN_DELAY, function() Check(false) end)
		end
	elseif event == 'BANKFRAME_OPENED' then
		atBank = true
		RememberBank()
	elseif event == 'BAG_UPDATE_DELAYED' and atBank then
		if BankFrame and BankFrame:IsShown() then
			RememberBank()
		else
			atBank = false
		end
	end
end)

SLASH_SUPRICES1 = '/suprices'
SlashCmdList.SUPRICES = function()
	Check(true, true)
end
