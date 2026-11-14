local ADDON_NAME, ns = ...
if not ns.IsEnabled('bagMarks') or not Bagnon then
	return
end
local SELL_DELAY_SECONDS = 0.2
local MERCHANT_SETTLE_SECONDS = 0.1
local BANK_DELAY_SECONDS = 0.2
local BANK_SETTLE_SECONDS = 0.1
local ATTACH_DELAY_SECONDS = 0.2
local MAIL_SETTLE_SECONDS = 0.3
local MAIL_SUBJECT = 'SnardgeUtils'
local PREFIX = '|cff999999SnardgeUtils:|r '

local RED_X_TEXTURE = 'Interface/Buttons/UI-GroupLoot-Pass-Up'
local RED_X_SIZE = 15
local BANK_TEXTURE = 'Interface/MINIMAP/TRACKING/Banker'
local BANK_SIZE = 13
local BANK_ALWAYS_TEXTURE = 'Interface/Buttons/UI-RefreshButton'
local BANK_ALWAYS_SIZE = 12
local MAIL_TEXTURE = 'Interface/MINIMAP/TRACKING/Mailbox'
local MAIL_SIZE = 13
local POOR_QUALITY = 0
local CONSUMABLE_CLASS = 0
-- includes the reagent bag, which sits one past NUM_BAG_SLOTS
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS

-- nil on clients without the Midnight bank API, where UseContainerItem takes no bank type
local BANK_TYPE = C_Bank and C_Bank.AreAnyBankTypesViewable and Enum.BankType.Character

local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant

local isVendorOnlyByLink = {}
local soldItemIDs = {}
local atMerchant = false
local atBank = false
local depositTried = {}
local atMailbox = false
local mailing = false
local attachTried = {}
local attachedThisMail = {}

local function IsVendorOnly(itemID, link, quality)
	local cached = isVendorOnlyByLink[link]
	if cached ~= nil then
		return cached
	end

	-- ItemTree answers nil for every item until its data loads, so hold off caching until
	-- it is ready; after that a nil answer is its real answer for that item and worth keeping
	if not (ItemTreeAPI and ItemTreeAPI.IsReady()) then
		return false
	end

	local facts = ItemTreeAPI.GetItemFacts(itemID, link)
	if not facts then
		isVendorOnlyByLink[link] = false
		return false
	end

	local tags = facts.keep and facts.keep.tags
	local vendorOnly = tags ~= nil and #tags == 1 and tags[1] == 'vendor'

	-- ItemTree says Vendor for anything with no auction price, and for spare tools and outranked
	-- potions, so its tag alone would grey items worth listing or still usable
	if vendorOnly and quality ~= POOR_QUALITY then
		local price = facts.price
		local classID = select(6, GetItemInfoInstant(itemID))
		vendorOnly = price ~= nil and price.source ~= 'vendor'
			and facts.keep.tool == nil
			and facts.uses.current == 0
			and classID ~= CONSUMABLE_CLASS
	end

	isVendorOnlyByLink[link] = vendorOnly
	return vendorOnly
end

local function Redraw()
	Bagnon.Frames:Update()
end

local function Refresh()
	wipe(isVendorOnlyByLink)
	Redraw()
end

local function ClearFinishedMarks()
	local changed = false
	for itemID in pairs(SnardgeUtilsSellMarks) do
		local soldAll = soldItemIDs[itemID] and GetItemCount(itemID) == 0
		if soldAll or GetItemCount(itemID, true) == 0 then
			SnardgeUtilsSellMarks[itemID] = nil
			soldItemIDs[itemID] = nil
			changed = true
		end
	end
	if changed then
		Refresh()
	end
end

local function ClearFinishedBankMarks()
	local changed = false
	for itemID in pairs(SnardgeUtilsBankMarks) do
		if GetItemCount(itemID) == 0 then
			SnardgeUtilsBankMarks[itemID] = nil
			changed = true
		end
	end
	if changed then
		Redraw()
	end
end

local function SellNext()
	-- UseContainerItem only sells while the merchant window is up; with a trade open it puts the
	-- item into the trade, which cancels the trade and leaves the slot greyed until a reload
	if not atMerchant or not (MerchantFrame and MerchantFrame:IsShown()) then
		return
	end
	if TradeFrame and TradeFrame:IsShown() then
		return
	end

	for bag = 0, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and SnardgeUtilsSellMarks[info.itemID] and not info.isLocked and not info.hasNoValue then
				soldItemIDs[info.itemID] = true
				C_Container.UseContainerItem(bag, slot)
				print(PREFIX .. 'sold ' .. info.hyperlink)
				C_Timer.After(SELL_DELAY_SECONDS, SellNext)
				return
			end
		end
	end
end

local function DepositNext()
	-- UseContainerItem only deposits while the bank is open; anywhere else it uses the item,
	-- and with a trade open it puts the item into the trade
	if not atBank or not (BankFrame and BankFrame:IsShown()) then
		return
	end
	if TradeFrame and TradeFrame:IsShown() then
		return
	end

	for bag = 0, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and (SnardgeUtilsBankMarks[info.itemID] or SnardgeUtilsBankAlwaysMarks[info.itemID]) and not info.isLocked then
				-- a full bank leaves the item in place, so each slot gets one attempt per visit
				local attempt = bag .. ':' .. slot .. ':' .. info.itemID
				if not depositTried[attempt] then
					depositTried[attempt] = true
					C_Container.UseContainerItem(bag, slot, nil, BANK_TYPE)
					print(PREFIX .. 'banked ' .. info.hyperlink)
					C_Timer.After(BANK_DELAY_SECONDS, DepositNext)
					return
				end
			end
		end
	end
end

local function MailRecipient()
	local recipient = strtrim(SnardgeUtilsSettings.mailRecipient or '')
	return recipient ~= '' and recipient or nil
end

-- Forever addresses mail by first name and surname
local function IsMailRecipient(recipient)
	local name, surname = UnitFullName('player')
	return surname ~= nil and strlower(name .. ' ' .. surname) == strlower(recipient)
end

local function IsFullStack(info)
	local maxStack = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(info.itemID)
		or select(8, C_Item.GetItemInfo(info.itemID))
	return not maxStack or info.stackCount >= maxStack
end

local function NextMailable()
	for bag = 0, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			-- an attached item stays in its bag slot, locked, until the mail goes out
			if info and SnardgeUtilsMailMarks[info.itemID] and not info.isLocked and not info.isBound
				and (not SnardgeUtilsSettings.mailFullStacksOnly or IsFullStack(info)) then
				local attempt = bag .. ':' .. slot .. ':' .. info.itemID
				if not attachTried[attempt] then
					return bag, slot, info, attempt
				end
			end
		end
	end
end

local function FreeAttachmentSlot()
	for i = 1, ATTACHMENTS_MAX_SEND do
		if not HasSendMailItem(i) then
			return i
		end
	end
end

local function PartStacksKept()
	local kept = {}
	if not SnardgeUtilsSettings.mailFullStacksOnly then
		return kept
	end
	for bag = 0, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and SnardgeUtilsMailMarks[info.itemID] and not info.isBound and not IsFullStack(info) then
				kept[#kept + 1] = info
			end
		end
	end
	return kept
end

-- Stacks of the same item are summed, in the order they were found
local function DescribeStacks(infos)
	local order, countByItemID, linkByItemID = {}, {}, {}
	for _, info in ipairs(infos) do
		if not countByItemID[info.itemID] then
			order[#order + 1] = info.itemID
			countByItemID[info.itemID] = 0
			linkByItemID[info.itemID] = info.hyperlink
		end
		countByItemID[info.itemID] = countByItemID[info.itemID] + (info.stackCount or 1)
	end
	local parts = {}
	for _, itemID in ipairs(order) do
		parts[#parts + 1] = linkByItemID[itemID] .. ' x' .. countByItemID[itemID]
	end
	return table.concat(parts, ', ')
end

local function MailNext()
	if not mailing or not atMailbox or not (SendMailFrame and SendMailFrame:IsShown()) then
		mailing = false
		return
	end

	local attachSlot = FreeAttachmentSlot()
	local bag, slot, info, attempt = NextMailable()
	if attachSlot and bag then
		attachTried[attempt] = true
		ClearCursor()
		C_Container.PickupContainerItem(bag, slot)
		ClickSendMailItemButton(attachSlot)
		if CursorHasItem() then
			ClearCursor()
			print(PREFIX .. 'could not attach ' .. info.hyperlink)
		else
			attachedThisMail[#attachedThisMail + 1] = info
		end
		C_Timer.After(ATTACH_DELAY_SECONDS, MailNext)
		return
	end

	if #attachedThisMail > 0 then
		local recipient = MailRecipient()
		print(format('%smailing to %s: %s', PREFIX, recipient, DescribeStacks(attachedThisMail)))
		attachedThisMail = {}
		SendMail(recipient, MAIL_SUBJECT, '')
	else
		mailing = false
		if MailFrameTab_OnClick then
			MailFrameTab_OnClick(MailFrameTab1, 1)
		end
	end
end

local function StartMailing()
	local recipient = MailRecipient()
	if not atMailbox or (recipient and IsMailRecipient(recipient)) then
		return
	end
	if not recipient then
		if next(SnardgeUtilsMailMarks) then
			print(PREFIX .. 'items are marked for mail, but no recipient is set: type one under Mail in /su')
		end
		return
	end
	local kept = PartStacksKept()
	if #kept > 0 then
		print(format('%skeeping part stacks: %s', PREFIX, DescribeStacks(kept)))
	end
	if not NextMailable() then
		return
	end
	if MailFrameTab_OnClick then
		MailFrameTab_OnClick(MailFrameTab2, 2)
	end
	mailing = true
	attachedThisMail = {}
	C_Timer.After(ATTACH_DELAY_SECONDS, MailNext)
end

local function ClickIs(action, mouseButton)
	return mouseButton == 'LeftButton' and ns.HeldCombo() == SnardgeUtilsSettings.clicks[action]
end

local function UnmarkHint(action)
	local combo = SnardgeUtilsSettings.clicks[action]
	return combo == 'NONE' and '' or ' (' .. ns.ComboLabel(combo) .. ' to unmark)'
end

local function MarkTexture(button, key, texture, size)
	if not button[key] then
		button[key] = button:CreateTexture(nil, 'OVERLAY', nil, 7)
		button[key]:SetTexture(texture)
		button[key]:SetSize(size, size)
		button[key]:SetPoint('TOPLEFT', 1, -1)
	end
	return button[key]
end

local function OnSetDesaturated(button, gray)
	local info = button.info
	if gray or not info or not info.itemID or not info.hyperlink then
		return
	end
	if SnardgeUtilsSellMarks[info.itemID] or IsVendorOnly(info.itemID, info.hyperlink, info.quality) then
		SetItemButtonDesaturated(button, true)
	end
end

-- UpdateBorder's last step shows or hides the border and glow, so this runs after it
local function OnUpdateBorder(button)
	local itemID = button.info and button.info.itemID
	local sell = itemID and SnardgeUtilsSellMarks[itemID]
	local bankOnce = itemID and SnardgeUtilsBankMarks[itemID]
	local bankAlways = itemID and SnardgeUtilsBankAlwaysMarks[itemID]
	local bank = bankOnce or bankAlways
	local mail = itemID and SnardgeUtilsMailMarks[itemID]

	if sell or bank or mail then
		local r, g, b = 1, 0, 0
		if bank then
			r, g, b = 0.2, 0.6, 1
		elseif mail then
			r, g, b = 1, 0.82, 0
		end
		button.IconGlow:SetVertexColor(r, g, b, 1)
		button.IconGlow:Show()
		button.IconBorder:SetVertexColor(r, g, b)
		button.IconBorder:Show()
	end

	if sell then
		MarkTexture(button, 'snardgeSellMark', RED_X_TEXTURE, RED_X_SIZE):Show()
	elseif button.snardgeSellMark then
		button.snardgeSellMark:Hide()
	end

	if bankOnce then
		MarkTexture(button, 'snardgeBankMark', BANK_TEXTURE, BANK_SIZE):Show()
	elseif button.snardgeBankMark then
		button.snardgeBankMark:Hide()
	end

	if bankAlways then
		MarkTexture(button, 'snardgeBankAlwaysMark', BANK_ALWAYS_TEXTURE, BANK_ALWAYS_SIZE):Show()
	elseif button.snardgeBankAlwaysMark then
		button.snardgeBankAlwaysMark:Hide()
	end

	if mail then
		MarkTexture(button, 'snardgeMailMark', MAIL_TEXTURE, MAIL_SIZE):Show()
	elseif button.snardgeMailMark then
		button.snardgeMailMark:Hide()
	end
end

hooksecurefunc(Bagnon.Item, 'SetDesaturated', OnSetDesaturated)
hooksecurefunc(Bagnon.Item, 'UpdateBorder', OnUpdateBorder)

hooksecurefunc(Bagnon.Item, 'PostClick', function(button, mouseButton)
	if not ClickIs('sell', mouseButton) then
		return
	end

	local info = button.info
	-- guild bank buttons have no IsCached
	if not button.hasItem or not info or not info.hyperlink or (button.IsCached and button:IsCached()) then
		return
	end

	-- Ctrl is also the dressing room's modified click, so gear opens it on the way through
	if DressUpFrame and DressUpFrame:IsShown() then
		HideUIPanel(DressUpFrame)
	end

	if SnardgeUtilsSellMarks[info.itemID] then
		SnardgeUtilsSellMarks[info.itemID] = nil
		print(PREFIX .. 'unmarked ' .. info.hyperlink)
	elseif info.hasNoValue then
		print(PREFIX .. info.hyperlink .. ' has no sell price')
		return
	else
		SnardgeUtilsSellMarks[info.itemID] = true
		SnardgeUtilsBankMarks[info.itemID] = nil
		SnardgeUtilsBankAlwaysMarks[info.itemID] = nil
		SnardgeUtilsMailMarks[info.itemID] = nil
		print(PREFIX .. 'will sell ' .. info.hyperlink .. ' at the next merchant')
	end
	Refresh()
end)

hooksecurefunc(Bagnon.Item, 'PostClick', function(button, mouseButton)
	local always
	if ClickIs('bankAlways', mouseButton) then
		always = true
	elseif ClickIs('bank', mouseButton) then
		always = false
	else
		return
	end

	local info = button.info
	local bag = button.bag
	-- bank, keyring and guild bank slots hold nothing a bank run would move
	if type(bag) ~= 'number' or bag < 0 or bag > LAST_BAG then
		return
	end
	if not button.hasItem or not info or not info.hyperlink or (button.IsCached and button:IsCached()) then
		return
	end

	if DressUpFrame and DressUpFrame:IsShown() then
		HideUIPanel(DressUpFrame)
	end

	-- an always mark outlives the item, so it is kept in its own table that no cleanup walks
	local marks = always and SnardgeUtilsBankAlwaysMarks or SnardgeUtilsBankMarks
	local otherMarks = always and SnardgeUtilsBankMarks or SnardgeUtilsBankAlwaysMarks

	if marks[info.itemID] then
		marks[info.itemID] = nil
		print(PREFIX .. 'unmarked ' .. info.hyperlink)
	else
		marks[info.itemID] = true
		otherMarks[info.itemID] = nil
		SnardgeUtilsSellMarks[info.itemID] = nil
		SnardgeUtilsMailMarks[info.itemID] = nil
		if always then
			print(PREFIX .. 'will always bank ' .. info.hyperlink)
		else
			print(PREFIX .. 'will bank ' .. info.hyperlink .. ' at the next bank')
		end
	end

	Redraw()
end)

hooksecurefunc(Bagnon.Item, 'PostClick', function(button, mouseButton)
	if not ClickIs('mail', mouseButton) then
		return
	end

	local info = button.info
	local bag = button.bag
	if type(bag) ~= 'number' or bag < 0 or bag > LAST_BAG then
		return
	end
	if not button.hasItem or not info or not info.hyperlink or (button.IsCached and button:IsCached()) then
		return
	end

	if DressUpFrame and DressUpFrame:IsShown() then
		HideUIPanel(DressUpFrame)
	end

	if SnardgeUtilsMailMarks[info.itemID] then
		SnardgeUtilsMailMarks[info.itemID] = nil
		print(PREFIX .. 'unmarked ' .. info.hyperlink)
	elseif info.isBound then
		print(PREFIX .. info.hyperlink .. ' is soulbound and cannot be mailed')
		return
	else
		SnardgeUtilsMailMarks[info.itemID] = true
		SnardgeUtilsSellMarks[info.itemID] = nil
		SnardgeUtilsBankMarks[info.itemID] = nil
		SnardgeUtilsBankAlwaysMarks[info.itemID] = nil
		print(PREFIX .. 'will always mail ' .. info.hyperlink .. ' to ' .. (MailRecipient() or 'your recipient, once you set one under Mail in /su'))
	end

	Refresh()
end)

hooksecurefunc(Bagnon.Item, 'ShowTooltip', function(button)
	local itemID = button.info and button.info.itemID
	if itemID and SnardgeUtilsSellMarks[itemID] then
		GameTooltip:AddLine('Marked to sell once' .. UnmarkHint('sell'), 1, 0.2, 0.2)
		GameTooltip:Show()
	elseif itemID and SnardgeUtilsBankAlwaysMarks[itemID] then
		GameTooltip:AddLine('Marked to always bank' .. UnmarkHint('bankAlways'), 0.2, 0.6, 1)
		GameTooltip:Show()
	elseif itemID and SnardgeUtilsBankMarks[itemID] then
		GameTooltip:AddLine('Marked to bank' .. UnmarkHint('bank'), 0.2, 0.6, 1)
		GameTooltip:Show()
	elseif itemID and SnardgeUtilsMailMarks[itemID] then
		GameTooltip:AddLine('Marked to always mail to ' .. (MailRecipient() or 'no recipient set') .. UnmarkHint('mail'), 1, 0.82, 0)
		GameTooltip:Show()
	end
end)

if ItemTreeAPI then
	ItemTreeAPI.RegisterReadyCallback(Refresh)
	ItemTreeAPI.RegisterChangeCallback(Refresh)
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('BAG_UPDATE_DELAYED')
frame:RegisterEvent('MERCHANT_SHOW')
frame:RegisterEvent('MERCHANT_CLOSED')
frame:RegisterEvent('BANKFRAME_OPENED')
frame:RegisterEvent('BANKFRAME_CLOSED')
frame:RegisterEvent('AUCTION_HOUSE_CLOSED')
frame:RegisterEvent('MAIL_SHOW')
frame:RegisterEvent('MAIL_CLOSED')
frame:RegisterEvent('MAIL_SEND_SUCCESS')
frame:RegisterEvent('MAIL_FAILED')
frame:SetScript('OnEvent', function(_, event, name)
	if event == 'ADDON_LOADED' then
		if name == ADDON_NAME then
			SnardgeUtilsSellMarks = SnardgeUtilsSellMarks or {}
			SnardgeUtilsBankMarks = SnardgeUtilsBankMarks or {}
			SnardgeUtilsBankAlwaysMarks = SnardgeUtilsBankAlwaysMarks or {}
			SnardgeUtilsMailMarks = SnardgeUtilsMailMarks or {}
		end
	elseif event == 'BAG_UPDATE_DELAYED' then
		-- Verdicts stay cached here: Bagnon redraws every slot on each loot, and asking
		-- ItemTree about a full bag each time stutters
		if atMerchant then
			ClearFinishedMarks()
		end
		if atBank then
			ClearFinishedBankMarks()
		end
	elseif event == 'MERCHANT_SHOW' then
		atMerchant = true
		ClearFinishedMarks()
		Refresh()
		C_Timer.After(MERCHANT_SETTLE_SECONDS, SellNext)
	elseif event == 'MERCHANT_CLOSED' then
		atMerchant = false
	elseif event == 'BANKFRAME_OPENED' then
		atBank = true
		wipe(depositTried)
		ClearFinishedBankMarks()
		C_Timer.After(BANK_SETTLE_SECONDS, DepositNext)
	elseif event == 'BANKFRAME_CLOSED' then
		atBank = false
	elseif event == 'AUCTION_HOUSE_CLOSED' then
		Refresh()
	elseif event == 'MAIL_SHOW' then
		atMailbox = true
		wipe(attachTried)
		C_Timer.After(MAIL_SETTLE_SECONDS, StartMailing)
	elseif event == 'MAIL_CLOSED' then
		atMailbox = false
		mailing = false
	elseif event == 'MAIL_SEND_SUCCESS' then
		if mailing then
			C_Timer.After(MAIL_SETTLE_SECONDS, MailNext)
		end
	elseif event == 'MAIL_FAILED' then
		if mailing then
			mailing = false
			print(PREFIX .. 'mail to ' .. (MailRecipient() or '?') .. ' failed')
		end
	end
end)
