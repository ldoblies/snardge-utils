local _, ns = ...

-- The TOC loads saved variables before any file runs, so each module can skip itself at
-- load time. Its hooks cannot be undone later, which is why a toggle needs a /reload.
SnardgeUtilsSettings = SnardgeUtilsSettings or {}
SnardgeUtilsSettings.disabled = SnardgeUtilsSettings.disabled or {}
if SnardgeUtilsSettings.mailFullStacksOnly == nil then
	SnardgeUtilsSettings.mailFullStacksOnly = true
end
SnardgeUtilsSettings.mailRecipient = SnardgeUtilsSettings.mailRecipient or ''
-- TSM custom price for materials bought on the auction house
SnardgeUtilsSettings.profitPriceSource = SnardgeUtilsSettings.profitPriceSource or 'first(dbminbuyout, dbmarket)'
SnardgeUtilsSettings.summonMessage = SnardgeUtilsSettings.summonMessage or 'Got the summon, on a loading screen now'
-- GROUP for party or raid chat, WHISPER for the summoner
SnardgeUtilsSettings.summonChannel = SnardgeUtilsSettings.summonChannel or 'GROUP'
-- totPowerColors[powerToken] = { r = r, g = g, b = b }; a missing token uses PowerBarColor's standard color
SnardgeUtilsSettings.totPowerColors = SnardgeUtilsSettings.totPowerColors or {}

ns.modules = {
	{ key = 'bagMarks', label = 'Bag marks', tooltip = 'Ctrl, Alt and Shift clicks on items in your bags mark them to sell, bank or mail. Works with the default bags and with Bagnon.' },
	{ key = 'bankBagIcons', label = 'Bank bag icons', requires = 'Bagnon', tooltip = "Bagnon's bank bags show their own icons instead of question marks." },
	{ key = 'mapPins', label = 'Group pins on top', tooltip = "Group member pins are drawn above Questie's map icons." },
	{ key = 'xpRate', label = 'XP per hour', tooltip = 'The experience bar shows recent and session xp/hr. /suxp prints it.' },
	{ key = 'questXp', label = 'Quest XP on XP bar', tooltip = 'The experience bar shows a gold segment for the XP your completed quests give when handed in, with the total on the left. /suqxp lists them.' },
	{ key = 'manaRegen', label = 'Mana per second', tooltip = 'The player frame shows mana regen next to the mana bar while mana is not full. /sumana prints it.' },
	{ key = 'lfgFilter', label = 'LFG filter and sort', tooltip = "The Looking For Group browser's gear menu filters listings by class and role and sorts them by level, highest first." },
	{ key = 'fishRecast', label = 'Instant fishing recast', requires = 'Mastercraft', tooltip = "Mastercraft's fishing key casts again as soon as you let go of it after a catch, instead of 0.4 seconds later." },
	{ key = 'vendorProfit', label = 'Vendor profit', requires = 'TradeSkillMaster', tooltip = "/suprofit lists the recipes your characters know by what a craft brings at a vendor, with materials at TSM prices or what vendors charged you. Shares recipes with your other license's characters while both are online." },
	{ key = 'priceAlert', label = 'High prices at login', requires = 'TradeSkillMaster', tooltip = 'After logging in, a popup lists items you own that sell for at least 120% of their usual TSM price. /suprices shows it any time.' },
	{ key = 'summonAnnounce', label = 'Summon announce', defaultOff = true, tooltip = 'When you accept a summon to another continent, a chat message tells the group you got it and are on a loading screen.' },
	{ key = 'totPowerColors', label = 'ToT power colors', tooltip = "The target of target power bar shows the standard color for each power type, instead of Forever's grey mana and blue rage. The cog sets your own colors." },
}

for _, module in ipairs(ns.modules) do
	if module.defaultOff and SnardgeUtilsSettings.disabled[module.key] == nil then
		SnardgeUtilsSettings.disabled[module.key] = true
	end
end

-- Modifier combos for left clicks on Bagnon items, as CTRL, ALT and SHIFT joined by '-' in
-- that order, or NONE for off
local CLICK_DEFAULTS = { sell = 'CTRL', bank = 'ALT', bankAlways = 'ALT-SHIFT', mail = 'CTRL-SHIFT' }
SnardgeUtilsSettings.clicks = SnardgeUtilsSettings.clicks or {}
for action, combo in pairs(CLICK_DEFAULTS) do
	if SnardgeUtilsSettings.clicks[action] == nil then
		SnardgeUtilsSettings.clicks[action] = combo
	end
end

ns.clickActions = {
	{ key = 'sell', label = 'Sell at the next merchant' },
	{ key = 'bank', label = 'Bank at the next bank' },
	{ key = 'bankAlways', label = 'Always bank' },
	{ key = 'mail', label = 'Always mail' },
}
ns.clickCombos = { 'CTRL', 'ALT', 'SHIFT', 'CTRL-ALT', 'CTRL-SHIFT', 'ALT-SHIFT', 'CTRL-ALT-SHIFT', 'NONE' }

function ns.HeldCombo()
	local held = {}
	if IsControlKeyDown() then held[#held + 1] = 'CTRL' end
	if IsAltKeyDown() then held[#held + 1] = 'ALT' end
	if IsShiftKeyDown() then held[#held + 1] = 'SHIFT' end
	return table.concat(held, '-')
end

function ns.ComboLabel(combo)
	if combo == 'NONE' then
		return 'Off'
	end
	local label = combo:gsub('CTRL', 'Ctrl'):gsub('ALT', 'Alt'):gsub('SHIFT', 'Shift'):gsub('%-', '+')
	return label .. '+click'
end

-- A combo already taken by another action moves that action to this one's old combo, so
-- two actions never share a click
function ns.SetClick(action, combo)
	local clicks = SnardgeUtilsSettings.clicks
	if combo ~= 'NONE' then
		for other, used in pairs(clicks) do
			if other ~= action and used == combo then
				clicks[other] = clicks[action]
			end
		end
	end
	clicks[action] = combo
end

function ns.IsEnabled(key)
	return not SnardgeUtilsSettings.disabled[key]
end

function ns.SetEnabled(key, enabled)
	SnardgeUtilsSettings.disabled[key] = not enabled
end
