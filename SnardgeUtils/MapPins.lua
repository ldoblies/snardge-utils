local _, ns = ...
if not ns.IsEnabled('mapPins') then
	return
end

local PREFIX = '|cff999999SnardgeUtils:|r '

-- Questie locks its world map icons to frame levels 2016 through 2024 with SetFixedFrameLevel,
-- so group member pins have to sit above that range or every quest icon paints over the party.
local PIN_FRAME_LEVEL = 2100

-- Blizzard's group pin baseline is 8, the size Leatrix Maps calls 100% on its own slider.
local PIN_SIZE = 16

-- The player arrow is sized on a different scale to the group icons, so it is left alone.
local UNITS = {'party', 'raid'}

local hooked = false

local function GroupProvider()
	local providers = WorldMapFrame and WorldMapFrame.dataProviders
	if type(providers) ~= 'table' then
		return nil
	end
	for provider in pairs(providers) do
		if type(provider) == 'table' and provider.SetUnitPinSize then
			return provider
		end
	end
end

local function Apply()
	local provider = GroupProvider()
	if not provider then
		return
	end

	for _, unit in ipairs(UNITS) do
		pcall(provider.SetUnitPinSize, provider, unit, PIN_SIZE)
	end

	local pin = provider.pin
	if not pin then
		return
	end
	if pin.SynchronizePinSizes then
		pcall(pin.SynchronizePinSizes, pin)
	end

	-- The pin system reassigns frame levels whenever the canvas rebuilds, so release the lock,
	-- set the level, and take the lock back the way Questie does for its own icons.
	if pin.SetFixedFrameLevel then
		pcall(pin.SetFixedFrameLevel, pin, false)
	end
	pcall(pin.SetFrameLevel, pin, PIN_FRAME_LEVEL)
	if pin.SetFixedFrameLevel then
		pcall(pin.SetFixedFrameLevel, pin, true)
	end
end

local function Schedule()
	C_Timer.After(0, Apply)
end

local function HookMap()
	if hooked or not WorldMapFrame or not WorldMapFrame.HookScript then
		return
	end
	hooked = true
	WorldMapFrame:HookScript('OnShow', Schedule)
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:RegisterEvent('GROUP_ROSTER_UPDATE')
frame:SetScript('OnEvent', function()
	HookMap()
	Schedule()
end)

SLASH_SUMAP1 = '/sumap'
SlashCmdList.SUMAP = function()
	local provider = GroupProvider()
	if not provider then
		print(PREFIX .. 'no group member data provider found on WorldMapFrame')
		return
	end
	local pin = provider.pin
	if not pin then
		print(PREFIX .. 'provider found, but its pin does not exist yet; open the map first')
		return
	end
	print(format('%spin frame level %d, wanted %d, group pin size %d',
		PREFIX, pin:GetFrameLevel(), PIN_FRAME_LEVEL, PIN_SIZE))
end
