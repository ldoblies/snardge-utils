local _, ns = ...
if not ns.IsEnabled('fishRecast') or not C_AddOns.IsAddOnLoaded('Mastercraft') then
	return
end

-- While the line is out, Mastercraft overrides the fishing key with interact, then gives it back
-- to casting 0.4s after the catch, so a press right after a catch is lost. Its binding owner is
-- a file local, caught here from its own SetOverrideBinding calls, and released as soon as the
-- catching key is let go. Mastercraft's cast button ignores a release without its own press.
local WAIT_ACTION = 'CLICK MastercraftFishWaitButton:LeftButton'

local owner
local keys = {}
local lineOut = false
local fishingSpell, stopAt = nil, 0

hooksecurefunc('SetOverrideBinding', function(frame, _, key, action)
	if action == 'INTERACTTARGET' then
		owner, keys[key], lineOut = frame, true, true
	end
end)
hooksecurefunc('SetOverrideBindingClick', function(frame, _, key, button)
	if button == 'MastercraftFishWaitButton' then
		owner, keys[key], lineOut = frame, true, true
	end
end)

local function KeyHeld()
	for key in pairs(keys) do
		local ok, down = pcall(IsKeyDown, key:match('[^%-]+$'))
		if ok and down then
			return true
		end
	end
	return false
end

local function Release()
	if lineOut or InCombatLockdown() then
		return
	end
	if KeyHeld() then
		return C_Timer.After(0, Release)
	end
	ClearOverrideBindings(owner)
end

-- Mastercraft skips binding the next line while its own 0.4s hand-back is still pending, so a
-- quick recast would leave the key casting instead of catching
local function Rebind()
	if InCombatLockdown() then
		return
	end
	for key in pairs(keys) do
		local action = GetBindingAction(key, true)
		if action ~= 'INTERACTTARGET' and action ~= WAIT_ACTION then
			SetOverrideBinding(owner, true, key, 'INTERACTTARGET')
		end
	end
end

local frame = CreateFrame('Frame')
frame:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_STOP', 'player')
frame:RegisterUnitEvent('UNIT_SPELLCAST_CHANNEL_START', 'player')
frame:SetScript('OnEvent', function(_, event, _, _, spellID)
	if issecretvalue and issecretvalue(spellID) then
		return
	end
	if event == 'UNIT_SPELLCAST_CHANNEL_STOP' then
		if not lineOut then
			return
		end
		lineOut, fishingSpell, stopAt = false, spellID, GetTime()
		C_Timer.After(0, Release)
	elseif spellID == fishingSpell and GetTime() - stopAt < 1 then
		C_Timer.After(0, Rebind)
	end
end)
