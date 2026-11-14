local ADDON_NAME, ns = ...
if not ns.IsEnabled('bagMarks') then
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
-- includes the reagent bag, which sits one past NUM_BAG_SLOTS
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS

-- nil on clients without the Midnight bank API, where UseContainerItem takes no bank type
local BANK_TYPE = C_Bank and C_Bank.AreAnyBankTypesViewable and Enum.BankType.Character

local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount

local soldItemIDs = {}
local atMerchant = false
local atBank = false
local depositTried = {}
local atMailbox = false
local mailing = false
local attachTried = {}
local attachedThisMail = {}

local function Redraw()
	if Bagnon then
		Bagnon.Frames:Update()
	end
	if ContainerFrame_UpdateAll then
		ContainerFrame_UpdateAll()
	end
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
		Redraw()
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

-- Without a purchased bank tab there is nowhere to deposit, and UseContainerItem falls back to
-- using the item, which the game blocks for addons
local function HasBankTab()
	if not (BANK_TYPE and C_Bank.FetchNumPurchasedBankTabs) then
		return true
	end
	return C_Bank.FetchNumPurchasedBankTabs(BANK_TYPE) > 0
end

local function HasBankMarkedItems()
	for bag = 0, LAST_BAG do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and (SnardgeUtilsBankMarks[info.itemID] or SnardgeUtilsBankAlwaysMarks[info.itemID]) then
				return true
			end
		end
	end
	return false
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
			print(PREFIX .. 'items are marked for mail, but no recipient is set: click the cog next to Bag marks in /su')
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

local function MarkSell(info)
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
	Redraw()
end

local function MarkBank(info, always)
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
end

local function MarkMail(info)
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
		print(PREFIX .. 'will always mail ' .. info.hyperlink .. ' to ' .. (MailRecipient() or 'your recipient, once you set one with the cog next to Bag marks in /su'))
	end
	Redraw()
end

-- info is the slot's container item info; bag is nil when the slot is not in your own bags
local function OnItemClick(info, bag, mouseButton)
	local sell = ClickIs('sell', mouseButton)
	local bankAlways = ClickIs('bankAlways', mouseButton)
	local bank = ClickIs('bank', mouseButton)
	local mail = ClickIs('mail', mouseButton)
	if not (sell or bankAlways or bank or mail) or not info or not info.hyperlink then
		return
	end

	-- Ctrl is also the dressing room's modified click, so gear opens it on the way through
	if DressUpFrame and DressUpFrame:IsShown() then
		HideUIPanel(DressUpFrame)
	end

	if sell then
		MarkSell(info)
		return
	end
	-- bank, keyring and guild bank slots hold nothing a bank or mail run would move
	if type(bag) ~= 'number' or bag < 0 or bag > LAST_BAG then
		return
	end
	if mail then
		MarkMail(info)
	else
		MarkBank(info, bankAlways)
	end
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

-- Runs after the bag addon has drawn the slot's own border, so a mark's color replaces it
local function Decorate(button, itemID)
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
		if button.IconGlow then
			button.IconGlow:SetVertexColor(r, g, b, 1)
			button.IconGlow:Show()
		end
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

local function AddTooltipLine(tooltip, itemID, reshow)
	if not itemID then
		return
	end
	if SnardgeUtilsSellMarks[itemID] then
		tooltip:AddLine('Marked to sell once' .. UnmarkHint('sell'), 1, 0.2, 0.2)
	elseif SnardgeUtilsBankAlwaysMarks[itemID] then
		tooltip:AddLine('Marked to always bank' .. UnmarkHint('bankAlways'), 0.2, 0.6, 1)
	elseif SnardgeUtilsBankMarks[itemID] then
		tooltip:AddLine('Marked to bank' .. UnmarkHint('bank'), 0.2, 0.6, 1)
	elseif SnardgeUtilsMailMarks[itemID] then
		tooltip:AddLine('Marked to always mail to ' .. (MailRecipient() or 'no recipient set') .. UnmarkHint('mail'), 1, 0.82, 0)
	else
		return
	end
	if reshow then
		tooltip:Show()
	end
end

if Bagnon then
	hooksecurefunc(Bagnon.Item, 'SetDesaturated', function(button, gray)
		local itemID = button.info and button.info.itemID
		if not gray and itemID and SnardgeUtilsSellMarks[itemID] then
			SetItemButtonDesaturated(button, true)
		end
	end)
	-- UpdateBorder's last step shows or hides the border and glow, so this runs after it
	hooksecurefunc(Bagnon.Item, 'UpdateBorder', function(button)
		Decorate(button, button.info and button.info.itemID)
	end)
	hooksecurefunc(Bagnon.Item, 'PostClick', function(button, mouseButton)
		-- guild bank buttons have no IsCached
		if not button.hasItem or (button.IsCached and button:IsCached()) then
			return
		end
		OnItemClick(button.info, button.bag, mouseButton)
	end)
	hooksecurefunc(Bagnon.Item, 'ShowTooltip', function(button)
		AddTooltipLine(GameTooltip, button.info and button.info.itemID, true)
	end)
end

-- Blizzard's bag buttons come from a pool and are reused for other slots, so each is hooked
-- once and looks up its current slot when clicked
local function BlizzardItemID(button)
	local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
	return info and info.itemID
end

local function OnBlizzardClick(button, mouseButton)
	local bag = button:GetBagID()
	OnItemClick(C_Container.GetContainerItemInfo(bag, button:GetID()), bag, mouseButton)
end

local function DecorateBlizzardFrame(containerFrame)
	for _, button in containerFrame:EnumerateValidItems() do
		if not button.snardgeHooked then
			button.snardgeHooked = true
			button:HookScript('OnClick', OnBlizzardClick)
		end
		button.snardgeItemID = BlizzardItemID(button)
		Decorate(button, button.snardgeItemID)
		if button.snardgeItemID and SnardgeUtilsSellMarks[button.snardgeItemID] then
			SetItemButtonDesaturated(button, true)
		end
	end
end

if ContainerFrameUtil_EnumerateContainerFrames then
	for _, containerFrame in ContainerFrameUtil_EnumerateContainerFrames() do
		hooksecurefunc(containerFrame, 'UpdateItems', DecorateBlizzardFrame)
	end
	-- Locking and unlocking a slot redraws its saturation outside UpdateItems
	hooksecurefunc('SetItemButtonDesaturated', function(button, desaturated)
		if not desaturated and button and button.snardgeHooked and button.snardgeItemID
			and SnardgeUtilsSellMarks[button.snardgeItemID] then
			SetItemButtonDesaturated(button, true)
		end
	end)
	if TooltipDataProcessor and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
			local owner = tooltip:GetOwner()
			if tooltip == GameTooltip and owner and owner.snardgeHooked then
				AddTooltipLine(tooltip, BlizzardItemID(owner))
			end
		end)
	end
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('BAG_UPDATE_DELAYED')
frame:RegisterEvent('MERCHANT_SHOW')
frame:RegisterEvent('MERCHANT_CLOSED')
frame:RegisterEvent('BANKFRAME_OPENED')
frame:RegisterEvent('BANKFRAME_CLOSED')
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
		if atMerchant then
			ClearFinishedMarks()
		end
		if atBank then
			ClearFinishedBankMarks()
		end
	elseif event == 'MERCHANT_SHOW' then
		atMerchant = true
		ClearFinishedMarks()
		C_Timer.After(MERCHANT_SETTLE_SECONDS, SellNext)
	elseif event == 'MERCHANT_CLOSED' then
		atMerchant = false
	elseif event == 'BANKFRAME_OPENED' then
		atBank = true
		wipe(depositTried)
		ClearFinishedBankMarks()
		if HasBankTab() then
			C_Timer.After(BANK_SETTLE_SECONDS, DepositNext)
		elseif HasBankMarkedItems() then
			print(PREFIX .. 'items are marked for the bank, but you have no bank tab to put them in yet')
		end
	elseif event == 'BANKFRAME_CLOSED' then
		atBank = false
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
