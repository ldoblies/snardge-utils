local _, ns = ...

-- Forever hands addons the player's health only as a secret value, so no addon code can
-- compare it to a threshold. Blizzard's Combat Audio Alerts can: its health pulse starts a
-- sound when health drops below a chosen 10% tier. SnardgeUtils switches that pulse on with
-- every other alert off and its own volume at zero, and plays its warning when the pulse
-- starts. A post hook leaves the alert code untainted; replacing its sound kits instead
-- would taint the health math that runs right after and break it.

local SOUND = SOUNDKIT.RAID_WARNING
local DEFAULTS = {
	threshold = 30,
}

local ENABLED_CVAR = 'CAAEnabled'
local PULSE_CVAR = 'CAAPulsePlayerHealthPercent'
local PULSE_VOLUME_CVAR = 'CAAPulsePlayerHealthVolume'
local PREFIX = '|cff999999SnardgeUtils:|r '

-- These CVars back Blizzard's per-spec settings and ignore a plain '0', so they are turned off
-- through C_CombatAudioAlert.SetSpecSetting instead
local SPEC_CVARS = {
	CAASayIfTargeted = true,
	CAAResource1Percents = true,
	CAAResource2Percents = true,
}

local function Settings()
	return SnardgeUtilsSettings.lowHealth
end

-- The pulse CVar holds a position in Blizzard's tier list: 0 off, 1 for 90%, 2 for 80% ... 9 for 10%
local function PulseIndex(threshold)
	return (100 - threshold) / 10
end

local function TurnOffOtherAlerts()
	if not (CombatAudioAlertConstants and CombatAudioAlertConstants.CVars) then
		return
	end
	for _, cvar in pairs(CombatAudioAlertConstants.CVars) do
		if cvar.refreshEvents and cvar.name ~= ENABLED_CVAR and cvar.name ~= PULSE_CVAR and not SPEC_CVARS[cvar.name] then
			C_CVar.SetCVar(cvar.name, '0')
		end
	end
end

local function SpecSettings()
	local spec = Enum.CombatAudioAlertSpecSetting
	return { spec.SayIfTargeted, spec.Resource1Percent, spec.Resource2Percent }
end

-- "Say if targeted" defaults to Aggro and is kept per spec, so it has to be turned off on
-- every character. The setting persists, so it stays off even in a session where this addon
-- does not load, as long as it loaded once on that character.
local function TurnOffSpecAlerts()
	for _, setting in ipairs(SpecSettings()) do
		if C_CombatAudioAlert.GetSpecSetting(setting) ~= 0 then
			C_CombatAudioAlert.SetSpecSetting(setting, 0)
		end
	end
end

-- Blizzard registers UNIT_TARGET here when "say if targeted" is on. Unregistering it right
-- after silences the alert even if the spec setting did not take, without calling into
-- (and so tainting) the alert code.
local function SilenceTargeted(manager)
	if C_CombatAudioAlert.GetSpecSetting(Enum.CombatAudioAlertSpecSetting.SayIfTargeted) ~= 0 then
		manager:UnregisterEvent('UNIT_TARGET')
	end
end

-- Runs on PLAYER_LOGIN, before the alert manager initialises on PLAYER_ENTERING_WORLD, so its
-- CVar callbacks return early and none of its health code runs from here
local function Apply()
	local settings = Settings()
	if ns.IsEnabled('lowHealth') then
		if not settings.applied then
			settings.restoreVolume = C_CVar.GetCVar(PULSE_VOLUME_CVAR)
			settings.applied = true
		end
		TurnOffOtherAlerts()
		TurnOffSpecAlerts()
		C_CVar.SetCVar(PULSE_VOLUME_CVAR, '0')
		C_CVar.SetCVar(PULSE_CVAR, tostring(PulseIndex(settings.threshold)))
		C_CVar.SetCVar(ENABLED_CVAR, '1')
	elseif settings.applied then
		C_CVar.SetCVar(ENABLED_CVAR, '0')
		C_CVar.SetCVar(PULSE_CVAR, '0')
		if settings.restoreVolume then
			C_CVar.SetCVar(PULSE_VOLUME_CVAR, settings.restoreVolume)
		end
		settings.applied = nil
		settings.restoreVolume = nil
	end
end

local low = false

local function OnPulseSoundKit(_, soundKitID)
	local nowLow = soundKitID ~= nil
	if nowLow and not low then
		PlaySound(SOUND, 'Master')
	end
	low = nowLow
end

SnardgeUtilsSettings.lowHealth = SnardgeUtilsSettings.lowHealth or {}
for key, value in pairs(DEFAULTS) do
	if SnardgeUtilsSettings.lowHealth[key] == nil then
		SnardgeUtilsSettings.lowHealth[key] = value
	end
end

local function Available()
	return C_CombatAudioAlert and C_CombatAudioAlert.GetSpecSetting and CombatAudioAlertManager
		and CombatAudioAlertManager.SetHealthPulseSoundKit and CombatAudioAlertManager.UpdateSpecSpecificSettings
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:SetScript('OnEvent', function(_, event)
	if not Available() then
		return
	end
	if event == 'PLAYER_LOGIN' then
		Apply()
		if ns.IsEnabled('lowHealth') then
			hooksecurefunc(CombatAudioAlertManager, 'SetHealthPulseSoundKit', OnPulseSoundKit)
			hooksecurefunc(CombatAudioAlertManager, 'UpdateSpecSpecificSettings', SilenceTargeted)
		end
	elseif Settings().applied then
		-- Spec data may not be ready at login, so try the spec settings again once in the world
		TurnOffSpecAlerts()
		SilenceTargeted(CombatAudioAlertManager)
	end
end)

SLASH_SULOW1 = '/sulow'
SlashCmdList.SULOW = function()
	if not Available() then
		print(PREFIX .. 'Combat Audio Alerts are not available on this client')
		return
	end
	local spec = Enum.CombatAudioAlertSpecSetting
	local pulse = tonumber(C_CVar.GetCVar(PULSE_CVAR)) or 0
	print(format('%slow health sound %s, alerts %s, pulse below %s, pulse volume %s',
		PREFIX, ns.IsEnabled('lowHealth') and 'on' or 'off', C_CVar.GetCVar(ENABLED_CVAR) == '1' and 'on' or 'off',
		pulse > 0 and (100 - pulse * 10) .. '%' or 'off', C_CVar.GetCVar(PULSE_VOLUME_CVAR)))
	print(format('%ssay if targeted %d (0 off, 1 aggro), listening %s',
		PREFIX, C_CombatAudioAlert.GetSpecSetting(spec.SayIfTargeted),
		CombatAudioAlertManager:IsEventRegistered('UNIT_TARGET') and 'yes' or 'no'))
	local on = {}
	for _, cvar in pairs(CombatAudioAlertConstants.CVars) do
		if cvar.refreshEvents and cvar.name ~= ENABLED_CVAR and cvar.name ~= PULSE_CVAR and not SPEC_CVARS[cvar.name] then
			local value = C_CVar.GetCVar(cvar.name)
			if value and value ~= '0' then
				on[#on + 1] = cvar.name .. '=' .. value
			end
		end
	end
	print(PREFIX .. 'other alerts on: ' .. (#on > 0 and table.concat(on, ', ') or 'none'))
end

ns.lowHealth = {
	Settings = Settings,
}
