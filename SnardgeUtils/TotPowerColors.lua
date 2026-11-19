local _, ns = ...
if not ns.IsEnabled('totPowerColors') then
	return
end

-- Forever's tintable ...-TargetofTarget-PortraitOn-Bar-Mana-Status atlas is dark and has no
-- blue in it, so no tint gives a blue bar. The classic status bar texture is light grey.
local TINTABLE = 'Interface\\TargetingFrame\\UI-StatusBar'

-- Forever's own target of target art shows mana grey and rage blue, so every power type is
-- tinted, with PowerBarColor's standard color unless one was picked. Both target of target
-- frames redo their power bar every frame while shown, so a color change shows right away.
hooksecurefunc('UnitFrameManaBar_UpdateType', function(manaBar)
	if not (manaBar and manaBar.unitFrame and manaBar.unitFrame.frameType == 'TargetofTarget') then
		return
	end
	local token = manaBar.powerToken
	if token == nil or (issecretvalue and issecretvalue(token)) then
		return
	end
	local color = SnardgeUtilsSettings.totPowerColors[token] or PowerBarColor[token]
	if color and color.r then
		manaBar:SetStatusBarTexture(TINTABLE)
		manaBar:SetStatusBarColor(color.r, color.g, color.b)
	end
end)
