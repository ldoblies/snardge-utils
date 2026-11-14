local _, ns = ...
if not ns.IsEnabled('vendorProfit') then
	return
end

local PREFIX = '|cff999999SnardgeUtils:|r '
local COMM = 'SnardgeUtils'
local MAX_MESSAGE = 240
local SEND_GAP = 0.1
local CRAFT_DEPTH = 2

SnardgeUtilsCrafts = SnardgeUtilsCrafts or {}
local store = SnardgeUtilsCrafts
-- chars[guid] = { name, updated, profs = { [profession] = { skill, max, scanned, recipes = { [recipeID] = { out, qty, diff, r = { itemID, qty, ... } } } } } }
store.chars = store.chars or {}
-- vendor[itemID][guid] = copper per unit that character paid, so reputation discounts count
store.vendor = store.vendor or {}
-- partners[name] = true: characters on the other license to sync with by whisper
store.partners = store.partners or {}

local DIFF = { [0] = 'o', [1] = 'y', [2] = 'g', [3] = 'x' }
local DIFF_COLOR = { o = 'ffff8040', y = 'ffffff00', g = 'ff40c040', x = 'ff808080' }

local myGUID
local frame

local function Money(copper)
	copper = math.floor(copper + 0.5)
	local sign = copper < 0 and '-' or ''
	copper = math.abs(copper)
	local gold, silver, cop = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if gold > 0 then
		return format('%s%dg %02ds', sign, gold, silver)
	end
	if silver > 0 then
		return format('%s%ds %02dc', sign, silver, cop)
	end
	return format('%s%dc', sign, cop)
end

local function ItemName(id)
	local name = C_Item.GetItemNameByID(id)
	if not name then
		C_Item.RequestLoadItemDataByID(id)
	end
	local known = ns.recipeItems and ns.recipeItems[id]
	return name or (known and known[1]) or ('item ' .. id)
end

local function SellPrice(id)
	local sell = select(11, C_Item.GetItemInfo(id))
	if sell == nil then
		C_Item.RequestLoadItemDataByID(id)
		local known = ns.recipeItems and ns.recipeItems[id]
		sell = known and known[2]
	end
	return sell
end

-- Skill-up color of a recipe at a skill: learn level is orange, then the yellow, green and grey thresholds
local function DiffAt(entry, skill)
	if not skill or skill < entry.l then
		return nil
	end
	local c = entry.c
	if skill < c[1] then return 'o' end
	if skill < c[2] then return 'y' end
	if skill < c[3] then return 'g' end
	return 'x'
end

local function Char(guid)
	local c = store.chars[guid]
	if not c then
		c = { profs = {}, updated = 0 }
		store.chars[guid] = c
	end
	return c
end

local function Touch(c)
	local newest = 0
	for _, p in pairs(c.profs) do
		newest = math.max(newest, p.scanned or 0)
	end
	c.updated = newest
end

---------------------------------------------------------------------------
-- Known recipes: own scan of the profession window, plus Mastercraft's saved scans
---------------------------------------------------------------------------

-- On Forever the second return of UnitFullName is the surname, not the realm
local function MyName()
	local first, surname = UnitFullName('player')
	if surname and surname ~= '' then
		return first .. ' ' .. surname
	end
	return first or UnitName('player')
end

local function ScanWindow()
	local T = C_TradeSkillUI
	if not (T and T.GetAllRecipeIDs and T.GetRecipeInfo and T.GetRecipeSchematic) then
		return
	end
	if (T.IsTradeSkillLinked and T.IsTradeSkillLinked()) or (T.IsTradeSkillGuild and T.IsTradeSkillGuild()) then
		return
	end
	local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
	local prof = base and base.professionName
	if not prof or prof == '' then
		return
	end
	local ids = T.GetAllRecipeIDs() or {}
	-- right after switching professions the window can still list the previous one's recipes
	if T.GetProfessionInfoByRecipeID and ids[1] then
		local ok, info = pcall(T.GetProfessionInfoByRecipeID, ids[1])
		if ok and info and info.professionName and info.professionName ~= '' and info.professionName ~= prof
			and info.parentProfessionName ~= prof then
			return
		end
	end
	local recipes, count = {}, 0
	for _, id in ipairs(ids) do
		local info = T.GetRecipeInfo(id)
		local schematic = info and info.learned and T.GetRecipeSchematic(id, false)
		if schematic and schematic.outputItemID then
			local reagents = {}
			for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
				local basic = not Enum.CraftingReagentType or slot.reagentType == Enum.CraftingReagentType.Basic
				local reagent = slot.reagents and slot.reagents[1]
				if basic and reagent and reagent.itemID then
					reagents[#reagents + 1] = reagent.itemID
					reagents[#reagents + 1] = slot.quantityRequired or 1
				end
			end
			local low = schematic.quantityMin and schematic.quantityMin > 0 and schematic.quantityMin or 1
			local high = schematic.quantityMax and schematic.quantityMax >= low and schematic.quantityMax or low
			recipes[id] = { out = schematic.outputItemID, qty = (low + high) / 2, diff = DIFF[info.relativeDifficulty], r = reagents }
			count = count + 1
		end
	end
	if count == 0 then
		return
	end
	local c = Char(myGUID)
	c.name = MyName()
	local ids = {}
	for id, r in pairs(recipes) do
		ids[#ids + 1] = id .. (r.diff or '')
	end
	table.sort(ids)
	local signature = (base.skillLevel or 0) .. ':' .. table.concat(ids, ',')
	local old = c.profs[prof]
	if old and old.signature == signature then
		return false
	end
	c.profs[prof] = { skill = base.skillLevel, max = base.maxSkillLevel, scanned = time(), recipes = recipes, signature = signature }
	Touch(c)
	return true
end

local function ImportMastercraft()
	local db = rawget(_G, 'MastercraftDB')
	if type(db) ~= 'table' or type(db.recipes) ~= 'table' then
		return
	end
	local chars = type(db.chars) == 'table' and db.chars or {}
	for guid, profs in pairs(db.recipes) do
		local info = chars[guid] or {}
		for prof, data in pairs(profs) do
			if type(data) == 'table' and type(data.list) == 'table' then
				local c = Char(guid)
				local have = c.profs[prof]
				if not have or (data.scanned or 0) > (have.scanned or 0) then
					local recipes, count = {}, 0
					for _, r in ipairs(data.list) do
						if r.learned and r.output and r.id then
							local reagents = {}
							for _, rg in ipairs(r.reagents or {}) do
								reagents[#reagents + 1] = rg.itemID
								reagents[#reagents + 1] = rg.qty or 1
							end
							local diff = ({ optimal = 'o', medium = 'y', easy = 'g', trivial = 'x' })[r.diff]
							recipes[r.id] = { out = r.output, qty = r.outputQty or 1, diff = diff, r = reagents }
							count = count + 1
						end
					end
					if count > 0 then
						local skill, max
						for _, p in ipairs(info.professions or {}) do
							if p.name == prof then
								skill, max = p.skill, p.max
							end
						end
						c.profs[prof] = { skill = skill, max = max, scanned = data.scanned or 0, recipes = recipes }
						if info.name then
							c.name = info.surname and (info.name .. ' ' .. info.surname) or info.name
						end
						Touch(c)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

-- Prices are looked up once per refresh: a list evaluates thousands of materials
local priceCache = {}

local function TSMPrice(source, id)
	if not (TSM_API and TSM_API.GetCustomPriceValue) then
		return nil
	end
	local key = source .. id
	local cached = priceCache[key]
	if cached == nil then
		local ok, value = pcall(TSM_API.GetCustomPriceValue, source, 'i:' .. id)
		cached = ok and type(value) == 'number' and value > 0 and value or false
		priceCache[key] = cached
	end
	return cached or nil
end

local function VendorPrice(id)
	local best
	for _, price in pairs(store.vendor[id] or {}) do
		if not best or price < best then
			best = price
		end
	end
	return best or TSMPrice('vendorbuy', id)
end

-- Cheapest way to get one unit: buy it (auction house or vendor) or make it with a recipe from
-- recipesByOut learned at maxLearn or below. Returns cost and the AH and vendor items it comes down to.
local function Source(id, recipesByOut, depth, maxLearn)
	local ah = TSMPrice(SnardgeUtilsSettings.profitPriceSource, id)
	local vendor = VendorPrice(id)
	local best
	if vendor and (not ah or vendor <= ah) then
		best = { cost = vendor, ah = {}, vendor = { [id] = 1 } }
	elseif ah then
		best = { cost = ah, ah = { [id] = 1 }, vendor = {} }
	end
	local recipe = depth < CRAFT_DEPTH and recipesByOut[id]
	if recipe and maxLearn and recipe.l and recipe.l > maxLearn then
		recipe = nil
	end
	if recipe then
		local made = { cost = 0, ah = {}, vendor = {} }
		local r = recipe.r
		for i = 1, #r, 2 do
			local part = Source(r[i], recipesByOut, depth + 1, maxLearn)
			if not part then
				made = nil
				break
			end
			local each = r[i + 1] / recipe.qty
			made.cost = made.cost + part.cost * each
			for k, n in pairs(part.ah) do made.ah[k] = (made.ah[k] or 0) + n * each end
			for k, n in pairs(part.vendor) do made.vendor[k] = (made.vendor[k] or 0) + n * each end
		end
		if made and (not best or made.cost < best.cost) then
			best = made
		end
	end
	return best
end

local function PartsText(parts)
	local list = {}
	for id, n in pairs(parts) do
		list[#list + 1] = format('%s %s', n % 1 == 0 and tostring(n) or format('%.1f', n), ItemName(id))
	end
	table.sort(list)
	return table.concat(list, ' + ')
end

-- One craft of a recipe: what the result sells for and what its materials come down to.
-- Returns nil when a material has no price or the result doesn't sell to a vendor.
local function Price(recipe, recipesByOut, maxLearn)
	local sell = SellPrice(recipe.out)
	if not sell or sell <= 0 then
		return nil
	end
	local ah, vendor, cost = {}, {}, 0
	local r = recipe.r
	for i = 1, #r, 2 do
		local part = Source(r[i], recipesByOut, 1, maxLearn)
		if not part then
			return nil
		end
		cost = cost + part.cost * r[i + 1]
		for k, n in pairs(part.ah) do ah[k] = (ah[k] or 0) + n * r[i + 1] end
		for k, n in pairs(part.vendor) do vendor[k] = (vendor[k] or 0) + n * r[i + 1] end
	end
	local ahCost, vendorCost = 0, 0
	for k, n in pairs(ah) do ahCost = ahCost + n * TSMPrice(SnardgeUtilsSettings.profitPriceSource, k) end
	for k, n in pairs(vendor) do vendorCost = vendorCost + n * VendorPrice(k) end
	local value = sell * recipe.qty
	return { out = recipe.out, value = value, profit = value - cost, ah = ah, vendor = vendor, ahCost = ahCost, vendorCost = vendorCost }
end

-- Where an unlearned recipe comes from, in a few words
local function SourceText(entry)
	if entry.src == 'trainer' then
		return format('trainer at %d, %s', entry.l, Money(entry.cost or 0))
	end
	if entry.src == 'vendor' then
		local faction = (UnitFactionGroup('player') or ''):sub(1, 1)
		for _, v in ipairs(entry.v or {}) do
			local npc = ns.recipeVendors and ns.recipeVendors[v[1]]
			if npc and (npc[3] == '' or npc[3] == 'N' or npc[3] == faction) then
				return format('pattern from %s, %s, %s%s', npc[1], npc[2], Money(v[2]), v[3] == 1 and ', limited' or '')
			end
		end
		return 'pattern from a vendor of the other faction'
	end
	local text = entry.src == 'known' and 'comes with the profession' or entry.src
	if entry.rep then
		text = text .. ', needs reputation'
	end
	if entry.spec then
		text = text .. ', specialization'
	end
	return text
end

local function Evaluate(withUnlearned)
	priceCache = {}
	local rows = {}
	local knownByProf, bestByProf = {}, {}
	for guid, c in pairs(store.chars) do
		for prof, p in pairs(c.profs) do
			knownByProf[prof] = knownByProf[prof] or {}
			local best = bestByProf[prof]
			if not best or (p.skill or 0) > (best.skill or 0) then
				bestByProf[prof] = { guid = guid, name = c.name or guid, skill = p.skill }
			end
			local recipesByOut = {}
			for _, recipe in pairs(p.recipes) do
				recipesByOut[recipe.out] = recipe
			end
			for id, recipe in pairs(p.recipes) do
				knownByProf[prof][id] = true
				local row = Price(recipe, recipesByOut)
				if row then
					local entry = ns.recipeData and ns.recipeData[prof] and ns.recipeData[prof][id]
					row.guid, row.char, row.prof, row.skill, row.diff = guid, c.name or guid, prof, p.skill, recipe.diff
					row.name = entry and entry.n
					rows[#rows + 1] = row
				end
			end
		end
	end
	if withUnlearned and ns.recipeData then
		for prof, entries in pairs(ns.recipeData) do
			local recipesByOut = {}
			for _, entry in pairs(entries) do
				recipesByOut[entry.o] = { out = entry.o, qty = entry.q, r = entry.r, l = entry.l }
			end
			local known = knownByProf[prof] or {}
			local best = bestByProf[prof]
			for id, entry in pairs(entries) do
				if not known[id] then
					-- only intermediates learnable by then count as the cheaper way
					local row = Price({ out = entry.o, qty = entry.q, r = entry.r }, recipesByOut, entry.l)
					if row then
						row.unlearned = true
						row.name, row.prof, row.learn, row.source = entry.n, prof, entry.l, SourceText(entry)
						row.guid = best and best.guid
						row.char = best and best.name or 'none of your characters'
						row.skill = best and best.skill
						row.diff = DiffAt(entry, best and best.skill)
						rows[#rows + 1] = row
					end
				end
			end
		end
	end
	table.sort(rows, function(a, b) return a.profit > b.profit end)
	return rows
end

---------------------------------------------------------------------------
-- Merchant prices actually paid
---------------------------------------------------------------------------

local function ReadMerchant()
	for i = 1, GetMerchantNumItems() do
		local id = GetMerchantItemID(i)
		local price, stack, extended
		if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
			local info = C_MerchantFrame.GetItemInfo(i)
			if info then
				price, stack, extended = info.price, info.stackCount, info.hasExtendedCost
			end
		else
			local _
			_, _, price, stack, _, _, _, extended = GetMerchantItemInfo(i)
		end
		if id and price and price > 0 and not extended then
			store.vendor[id] = store.vendor[id] or {}
			store.vendor[id][myGUID] = price / math.max(1, stack or 1)
		end
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local ROW_HEIGHT = 34
local onlyProfit, onlySkill, withUnlearned = true, false, true
local charFilter
local rowFrames = {}

local function Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	local rows = Evaluate(withUnlearned)
	local shown = {}
	for _, row in ipairs(rows) do
		if (not onlyProfit or row.profit > 0) and (not onlySkill or (row.diff and row.diff ~= 'x'))
			and (not charFilter or row.guid == charFilter) then
			shown[#shown + 1] = row
		end
	end
	local content = frame.content
	for i, row in ipairs(shown) do
		local line = rowFrames[i]
		if not line then
			line = CreateFrame('Frame', nil, content)
			line:SetSize(content:GetWidth(), ROW_HEIGHT)
			line:SetPoint('TOPLEFT', 0, -(i - 1) * ROW_HEIGHT)
			line.top = line:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
			line.top:SetPoint('TOPLEFT', 4, -2)
			line.top:SetPoint('RIGHT', -4, 0)
			line.top:SetJustifyH('LEFT')
			line.bottom = line:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
			line.bottom:SetPoint('TOPLEFT', line.top, 'BOTTOMLEFT', 0, -3)
			line.bottom:SetPoint('RIGHT', -4, 0)
			line.bottom:SetJustifyH('LEFT')
			line.bottom:SetWordWrap(false)
			rowFrames[i] = line
		end
		local profitColor = row.profit > 0 and 'ff40ff40' or 'ffff6060'
		local diffColor = DIFF_COLOR[row.diff] or 'ffffffff'
		local who = format('%s, %s %s', row.char, row.prof, row.skill or '-')
		if row.unlearned then
			who = format('not learned: %s  |  %s', row.source, who)
		end
		line.top:SetText(format('|c%s%s|r  |c%s%s|r  |cff999999%s|r', profitColor, (row.profit > 0 and '+' or '') .. Money(row.profit),
			diffColor, row.name or ItemName(row.out), who))
		local text = format('sells %s', Money(row.value))
		if next(row.ah) then
			text = format('AH: %s = %s, break-even %s  |  %s', PartsText(row.ah), Money(row.ahCost), Money(row.value - row.vendorCost), text)
		end
		if next(row.vendor) then
			text = format('%s  |  vendor: %s = %s', text, PartsText(row.vendor), Money(row.vendorCost))
		end
		line.bottom:SetText(text)
		line:Show()
	end
	for i = #shown + 1, #rowFrames do
		rowFrames[i]:Hide()
	end
	content:SetHeight(math.max(1, #shown * ROW_HEIGHT))
	local who = charFilter and (store.chars[charFilter] and store.chars[charFilter].name or charFilter) or 'All characters'
	frame.charButton:SetText(who)
	frame.status:SetText(#shown == 0 and 'Nothing to show. Open a profession window on each crafter once.' or format('%d recipes', #shown))
end

local function NextChar()
	local guids = {}
	for guid in pairs(store.chars) do
		guids[#guids + 1] = guid
	end
	table.sort(guids, function(a, b) return (store.chars[a].name or a) < (store.chars[b].name or b) end)
	if not charFilter then
		charFilter = guids[1]
		return
	end
	for i, guid in ipairs(guids) do
		if guid == charFilter then
			charFilter = guids[i + 1]
			return
		end
	end
	charFilter = nil
end

local function Checkbox(parent, x, label, get, set)
	local box = CreateFrame('CheckButton', nil, parent, 'ChatConfigCheckButtonTemplate')
	box:SetPoint('TOPLEFT', x, -30)
	box.f = box:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
	box.f:SetPoint('LEFT', 20, 0)
	box.f:SetText(label)
	box:SetChecked(get())
	box:SetScript('OnClick', function(self)
		set(self:GetChecked())
		Refresh()
	end)
	return box
end

local function BuildFrame()
	frame = CreateFrame('Frame', 'SnardgeUtilsProfitFrame', UIParent, 'BasicFrameTemplateWithInset')
	frame:SetSize(720, 460)
	frame:SetPoint('CENTER')
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag('LeftButton')
	frame:SetScript('OnDragStart', frame.StartMoving)
	frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
	frame:SetFrameStrata('DIALOG')
	tinsert(UISpecialFrames, 'SnardgeUtilsProfitFrame')
	frame.TitleText:SetText('Vendor profit per craft')

	Checkbox(frame, 12, 'Profitable only', function() return onlyProfit end, function(v) onlyProfit = v end)
	Checkbox(frame, 125, 'Still gives skill', function() return onlySkill end, function(v) onlySkill = v end)
	Checkbox(frame, 240, 'Unlearned too', function() return withUnlearned end, function(v) withUnlearned = v end)
	local button = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	button:SetSize(150, 22)
	button:SetPoint('TOPLEFT', 350, -28)
	button:SetScript('OnClick', function()
		NextChar()
		Refresh()
	end)
	frame.charButton = button
	local refresh = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
	refresh:SetSize(80, 22)
	refresh:SetPoint('LEFT', button, 'RIGHT', 8, 0)
	refresh:SetText('Refresh')
	refresh:SetScript('OnClick', Refresh)
	frame.status = frame:CreateFontString(nil, 'ARTWORK', 'GameFontDisableSmall')
	frame.status:SetPoint('LEFT', refresh, 'RIGHT', 10, 0)

	local scroll = CreateFrame('ScrollFrame', nil, frame, 'UIPanelScrollFrameTemplate')
	scroll:SetPoint('TOPLEFT', 10, -58)
	scroll:SetPoint('BOTTOMRIGHT', -30, 10)
	local content = CreateFrame('Frame', nil, scroll)
	content:SetSize(670, 1)
	scroll:SetScrollChild(content)
	frame.content = content
	frame:SetScript('OnShow', Refresh)
end

local function Toggle()
	if not frame then
		BuildFrame()
		frame:Show()
		return
	end
	frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- Sync with the other license by addon messages
-- H digest: guid=updated pairs. The receiver whispers back every character it has newer.
---------------------------------------------------------------------------

local queue, sending = {}, false
-- whisperedAt[name] = GetTime() of the last addon whisper, to hide "No player named ..." for an offline partner
local whisperedAt = {}

local function Pump()
	local msg = table.remove(queue, 1)
	if not msg then
		sending = false
		return
	end
	if msg.channel == 'WHISPER' then
		whisperedAt[msg.target] = GetTime()
	end
	C_ChatInfo.SendAddonMessage(COMM, msg.text, msg.channel, msg.target)
	C_Timer.After(SEND_GAP, Pump)
end

local function Send(text, channel, target)
	queue[#queue + 1] = { text = text, channel = channel, target = target }
	if not sending then
		sending = true
		Pump()
	end
end

ChatFrame_AddMessageEventFilter('CHAT_MSG_SYSTEM', function(_, _, message)
	for name, at in pairs(whisperedAt) do
		if GetTime() - at < 5 and message == ERR_CHAT_PLAYER_NOT_FOUND_S:format(name) then
			return true
		end
	end
end)

local function Digest()
	local parts = {}
	for guid, c in pairs(store.chars) do
		if next(c.profs) then
			parts[#parts + 1] = guid .. '=' .. (c.updated or 0)
		end
	end
	return table.concat(parts, ',')
end

local function Hello(kind, channel, target)
	Send(kind .. '\t' .. myGUID .. '\t' .. Digest(), channel, target)
end

local function Broadcast()
	if IsInGuild() then
		Hello('H', 'GUILD')
	end
	if IsInGroup() then
		Hello('H', IsInRaid() and 'RAID' or 'PARTY')
	end
	for name in pairs(store.partners) do
		Hello('H', 'WHISPER', name)
	end
end

local function PushChar(guid, target)
	local c = store.chars[guid]
	Send(format('C\t%s\t%s\t%d', guid, c.name or '', c.updated or 0), 'WHISPER', target)
	for prof, p in pairs(c.profs) do
		Send(format('P\t%s\t%s\t%d\t%d\t%d', guid, prof, p.skill or 0, p.max or 0, p.scanned or 0), 'WHISPER', target)
		local head = format('R\t%s\t%s\t', guid, prof)
		local batch, count = {}, 0
		local size = #head
		for id, r in pairs(p.recipes) do
			local entry = format('%d,%d,%s,%s,%s', id, r.out, tostring(r.qty), r.diff or '-', table.concat(r.r, ':'))
			if size + #entry + 1 > MAX_MESSAGE and #batch > 0 then
				Send(head .. table.concat(batch, ';'), 'WHISPER', target)
				batch, size = {}, #head
			end
			batch[#batch + 1] = entry
			size = size + #entry + 1
			count = count + 1
		end
		if #batch > 0 then
			Send(head .. table.concat(batch, ';'), 'WHISPER', target)
		end
		Send(format('E\t%s\t%s\t%d', guid, prof, count), 'WHISPER', target)
	end
	local batch, size = {}, 0
	for id, byGuid in pairs(store.vendor) do
		local price = byGuid[guid]
		if price then
			local entry = format('%d:%s', id, tostring(math.floor(price * 100 + 0.5) / 100))
			if size + #entry + 1 > MAX_MESSAGE - 50 and #batch > 0 then
				Send(format('V\t%s\t%s', guid, table.concat(batch, ';')), 'WHISPER', target)
				batch, size = {}, 0
			end
			batch[#batch + 1] = entry
			size = size + #entry + 1
		end
	end
	if #batch > 0 then
		Send(format('V\t%s\t%s', guid, table.concat(batch, ';')), 'WHISPER', target)
	end
end

local incoming = {}

local function OnMessage(text, sender)
	local kind, rest = text:match('^(%a)\t(.*)$')
	if not kind then
		return
	end
	if kind == 'H' or kind == 'h' then
		local from
		from, rest = rest:match('^([^\t]+)\t(.*)$')
		if not from or from == myGUID then
			return
		end
		store.partners[sender] = true
		local theirs = {}
		for guid, updated in rest:gmatch('([^,=]+)=(%d+)') do
			theirs[guid] = tonumber(updated)
		end
		for guid, c in pairs(store.chars) do
			if next(c.profs) and (c.updated or 0) > (theirs[guid] or -1) then
				PushChar(guid, sender)
			end
		end
		if kind == 'H' then
			Hello('h', 'WHISPER', sender)
		end
	elseif kind == 'C' then
		local guid, name, updated = rest:match('^([^\t]+)\t([^\t]*)\t(%d+)$')
		if guid and guid ~= myGUID then
			local c = Char(guid)
			if name ~= '' then
				c.name = name
			end
		end
	elseif kind == 'P' then
		local guid, prof, skill, max, scanned = rest:match('^([^\t]+)\t([^\t]+)\t(%d+)\t(%d+)\t(%d+)$')
		if guid and guid ~= myGUID then
			incoming[guid .. '\t' .. prof] = { skill = tonumber(skill), max = tonumber(max), scanned = tonumber(scanned), recipes = {} }
		end
	elseif kind == 'R' then
		local guid, prof, list = rest:match('^([^\t]+)\t([^\t]+)\t(.*)$')
		local pending = guid and incoming[guid .. '\t' .. prof]
		if pending then
			for entry in list:gmatch('[^;]+') do
				local id, out, qty, diff, reagents = entry:match('^(%d+),(%d+),([%d%.]+),(%S),(.*)$')
				if id then
					local r = {}
					for n in reagents:gmatch('%d+') do
						r[#r + 1] = tonumber(n)
					end
					pending.recipes[tonumber(id)] = { out = tonumber(out), qty = tonumber(qty), diff = diff ~= '-' and diff or nil, r = r }
				end
			end
		end
	elseif kind == 'E' then
		local guid, prof, count = rest:match('^([^\t]+)\t([^\t]+)\t(%d+)$')
		local key = guid and (guid .. '\t' .. prof)
		local pending = key and incoming[key]
		if pending then
			local got = 0
			for _ in pairs(pending.recipes) do
				got = got + 1
			end
			local c = Char(guid)
			local have = c.profs[prof]
			if got == tonumber(count) and (not have or (have.scanned or 0) <= pending.scanned) then
				c.profs[prof] = pending
				Touch(c)
			end
			incoming[key] = nil
			if frame and frame:IsShown() then
				C_Timer.After(0.5, Refresh)
			end
		end
	elseif kind == 'V' then
		local guid, list = rest:match('^([^\t]+)\t(.*)$')
		if guid and guid ~= myGUID then
			for id, price in list:gmatch('(%d+):([%d%.]+)') do
				id = tonumber(id)
				store.vendor[id] = store.vendor[id] or {}
				store.vendor[id][guid] = tonumber(price)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Events and slash command
---------------------------------------------------------------------------

local events = CreateFrame('Frame')
local scanPending = false

local function QueueScan()
	if scanPending then
		return
	end
	scanPending = true
	C_Timer.After(0.5, function()
		scanPending = false
		if ScanWindow() then
			Broadcast()
		end
	end)
end

events:RegisterEvent('PLAYER_LOGIN')
events:RegisterEvent('TRADE_SKILL_SHOW')
events:RegisterEvent('TRADE_SKILL_LIST_UPDATE')
events:RegisterEvent('MERCHANT_SHOW')
events:RegisterEvent('MERCHANT_UPDATE')
events:RegisterEvent('CHAT_MSG_ADDON')
events:SetScript('OnEvent', function(_, event, ...)
	if event == 'PLAYER_LOGIN' then
		myGUID = UnitGUID('player')
		C_ChatInfo.RegisterAddonMessagePrefix(COMM)
		ImportMastercraft()
		C_Timer.After(10, Broadcast)
	elseif event == 'TRADE_SKILL_SHOW' or event == 'TRADE_SKILL_LIST_UPDATE' then
		QueueScan()
	elseif event == 'MERCHANT_SHOW' or event == 'MERCHANT_UPDATE' then
		ReadMerchant()
	elseif event == 'CHAT_MSG_ADDON' then
		local prefix, text, _, sender = ...
		if prefix == COMM and sender then
			OnMessage(text, sender)
		end
	end
end)

SLASH_SUPROFIT1 = '/suprofit'
SlashCmdList.SUPROFIT = function(msg)
	local command, arg = (msg or ''):match('^%s*(%S*)%s*(.-)%s*$')
	command = command:lower()
	if command == 'add' and arg ~= '' then
		store.partners[arg] = true
		print(PREFIX .. 'syncing with ' .. arg .. ' whenever both of you are online.')
		Hello('H', 'WHISPER', arg)
	elseif command == 'remove' and arg ~= '' then
		store.partners[arg] = nil
		print(PREFIX .. 'stopped syncing with ' .. arg .. '.')
	elseif command == 'source' then
		if arg ~= '' then
			SnardgeUtilsSettings.profitPriceSource = arg
		end
		print(PREFIX .. 'auction house prices come from TSM: ' .. SnardgeUtilsSettings.profitPriceSource)
		Refresh()
	elseif command == 'sync' then
		Broadcast()
		print(PREFIX .. 'asked your other characters for their recipes.')
	else
		if not TSM_API then
			print(PREFIX .. 'vendor profit needs TradeSkillMaster for auction house prices.')
			return
		end
		Toggle()
	end
end
