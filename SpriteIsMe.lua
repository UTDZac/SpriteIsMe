local function SpriteIsMe()
	local self = {
		version = "1.0",
		name = "Sprite Is Me",
		author = "UTDZac",
		description = "Turns your character into your lead Pokémon, or you can choose the Pokémon you want to become.",
		github = "UTDZac/SpriteIsMe-IronmonExtension",
	}
	self.url = string.format("https://github.com/%s", self.github)

	-- Other internal attributes, no need to change any of these
	local extSettingsKey = "SpriteIsMe"
	local settings = {
		["ForceUsePokemon"] = {}, -- If provided in options, will use this pokemon instead of your lead pokemon (e.g. "Mr. Mime")
		["CustomSpriteName"] = {},
		["CustomSpriteWidth"] = {},
		["CustomSpriteHeight"] = {},
		["CustomSpriteFramesIdle"] = {},
		["CustomSpriteFramesWalk"] = {},
		["CustomSpriteFramesSleep"] = {},
		["CustomSpriteFramesFaint"] = {},
	}
	local CUSTOM_SPRITE_FOLDER = FileManager.getCustomFolderPath() .. "SpriteIsMeImages"
	local originalWalkSetting, originalAnimationAllowed
	local lastKnownFacing = 1

	local SCREEN_CENTER_X = Constants.SCREEN.WIDTH / 2 - 16
	local SCREEN_CENTER_Y = Constants.SCREEN.HEIGHT / 2 - 24

	-- Definite save/load settings functions
	for key, setting in pairs(settings or {}) do
		setting.key = tostring(key)
		if type(setting.load) ~= "function" then
			setting.load = function(this)
				local loadedValue = TrackerAPI.getExtensionSetting(extSettingsKey, this.key)
				if loadedValue ~= nil then
					this.values = Utils.split(loadedValue, ",", true)
				end
				return this.values
			end
		end
		if type(setting.save) ~= "function" then
			setting.save = function(this)
				if this.values ~= nil then
					local savedValue = table.concat(this.values, ",") or ""
					TrackerAPI.saveExtensionSetting(extSettingsKey, this.key, savedValue)
				end
			end
		end
		if type(setting.get) ~= "function" then
			setting.get = function(this)
				if this.values ~= nil and #this.values > 0 then
					return table.concat(this.values, ",")
				else
					return nil
				end
			end
		end
	end

	function self.drawSpriteOnScreen()
		if not Program.isValidMapLocation() or Battle.inBattleScreen or Program.currentOverlay ~= nil then
			return
		end

		local iconKey
		local useCustom = false

		local spriteId = self.getPokemonIDFromSettings()
		local spriteName = settings["CustomSpriteName"]:get() or ""
		if spriteId then
			-- First try using an internal pokemon sprite, if chosen by user
			iconKey = spriteId
		elseif spriteName ~= "" then
			-- Otherwise try using custom defined sprite data
			iconKey = spriteName
			useCustom = true
			if not SpriteData.IconData[iconKey] then
				self.updateIconData()
			end
		else
			-- Finally, try using the lead pokemon instead
			local pokemon = Tracker.getPokemon(1, true) or {}
			if PokemonData.isValid(pokemon.pokemonID) then
				iconKey = pokemon.pokemonID
			end
		end

		if not iconKey then
			return
		end

		local requiredAnimType = SpriteData.Types.Walk or SpriteData.DefaultType

		-- Check if the player is actively walking or idle
		local facingFrame = self.getSpriteFacingDirection(requiredAnimType)
		if facingFrame ~= -1 then
			-- If the facing frame changed, use that going forward
			lastKnownFacing = facingFrame
			requiredAnimType = SpriteData.Types.Walk
		else
			-- If no change (no new directional input), use the previous known direction
			facingFrame = lastKnownFacing
			requiredAnimType = SpriteData.Types.Idle
		end

		-- SpriteData.getOrAddActiveIcon
		local activeIcon = SpriteData.ActiveIcons[iconKey] or SpriteData.createActiveIcon(iconKey, requiredAnimType)
		if not activeIcon then
			return
		end

		-- If a required animation type is being requested, change to that (if able)
		if activeIcon.animationType ~= requiredAnimType and not activeIcon.inUse and SpriteData.IconData[iconKey][requiredAnimType] then
			-- Create a new or replacement active icon with the updated animationType
			SpriteData.createActiveIcon(iconKey, requiredAnimType)
		end

		local icon = SpriteData.IconData[iconKey][activeIcon.animationType]
		if not icon then
			return
		end

		-- Mark that this sprite animation is being used
		activeIcon.inUse = true

		-- Determine source index frame to draw
		local imagePath = self.buildSpritePath(activeIcon.animationType, tostring(iconKey), ".png", useCustom)
		local indexFrame = activeIcon.indexFrame or 1
		local sourceX = icon.w * (indexFrame - 1)
		local sourceY = icon.h * (facingFrame - 1)
		local x = SCREEN_CENTER_X + (icon.x or 0)
		local y = SCREEN_CENTER_Y + (icon.y or 0)
		Drawing.drawImageRegion(imagePath, sourceX, sourceY, icon.w, icon.h, x, y)
	end

	function self.getSpriteFacingDirection(animationType)
		if animationType ~= SpriteData.Types.Walk and animationType ~= SpriteData.Types.Idle then
			return 1
		end
		local joypad = Input.getJoypadInputFormatted()
		if joypad["Right"] and joypad["Down"] then return 2
		elseif joypad["Right"] and joypad["Up"] then return 4
		elseif joypad["Left"] and joypad["Up"] then return 6
		elseif joypad["Left"] and joypad["Down"] then return 8
		elseif joypad["Down"] then return 1
		elseif joypad["Right"] then return 3
		elseif joypad["Up"] then return 5
		elseif joypad["Left"] then return 7
		else return -1
		end
	end

	function self.buildSpritePath(animationType, imageName, imageExtension, useCustom)
		local listOfPaths = {}
		if useCustom then
			table.insert(listOfPaths, CUSTOM_SPRITE_FOLDER)
		else
			table.insert(listOfPaths, FileManager.dir)
			table.insert(listOfPaths, FileManager.Folders.TrackerCode)
			table.insert(listOfPaths, FileManager.Folders.Images)
			if Options.getIconSet().isAnimated then
				table.insert(listOfPaths, Options.getIconSet().folder)
			else
				table.insert(listOfPaths, Options.IconSetMap[SpriteData.DefaultIconSetIndex].folder)
			end
		end
		table.insert(listOfPaths, tostring(animationType))
		table.insert(listOfPaths, tostring(imageName) .. (imageExtension or ""))
		return table.concat(listOfPaths, FileManager.slash)
	end

	-- If its set, returns a proper pokemon id, otherwise nil
	function self.getPokemonIDFromSettings()
		local idFromSettings = tonumber(settings["ForceUsePokemon"]:get() or "") or 0
		return PokemonData.isValid(idFromSettings) and idFromSettings or nil
	end

	function self.openOptionsPopup()
		if not Main.IsOnBizhawk() then return end

		local form = Utils.createBizhawkForm("Choose Your Sprite", 320, 290, 100, 25)

		local leftX, leftW = 28, 115
		local rightX, rightW = 152, 134
		local boxH = 20
		local nextLineY = 20

		-- Existing Pokemon Sprites
		local idFromSettings = tonumber(settings["ForceUsePokemon"]:get() or "") or 0
		local chosenPokemonName = PokemonData.isValid(idFromSettings) and PokemonData.Pokemon[idFromSettings].name or Constants.BLANKLINE
		local allPokemonNames = PokemonData.namesToList()
		table.insert(allPokemonNames, 1, Constants.BLANKLINE)
		-- local textboxPokemonName = forms.textbox(form, chosenPokemonName, rightW, boxH, nil, rightX, nextLineY - 2)
		forms.label(form, "Pokémon name:", leftX, nextLineY, leftW, boxH)
		local dropdownPokemonNames = forms.dropdown(form, {["Init"]="Loading Names"}, rightX, nextLineY - 2, rightW, boxH)
		forms.setdropdownitems(dropdownPokemonNames, allPokemonNames, true) -- true = alphabetize the list
		forms.setproperty(dropdownPokemonNames, "AutoCompleteSource", "ListItems")
		forms.setproperty(dropdownPokemonNames, "AutoCompleteMode", "Append")
		forms.settext(dropdownPokemonNames, chosenPokemonName)
		nextLineY = nextLineY + 25

		forms.label(form, "OR", 135, nextLineY, 30, boxH)
		nextLineY = nextLineY + 25

		-- Custom Sprite
		forms.label(form, "Custom sprite name: *", leftX, nextLineY, leftW, boxH)
		local textboxCustomName = forms.textbox(form, settings["CustomSpriteName"]:get() or "", rightW, boxH, nil, rightX, nextLineY - 2)
		nextLineY = nextLineY + 22
		forms.label(form, "Width:", leftX, nextLineY, 50, boxH)
		local textboxCustomWidth = forms.textbox(form, settings["CustomSpriteWidth"]:get() or "", 50, boxH, "UNSIGNED", leftX + 60, nextLineY - 2)
		forms.label(form, "Height:", rightX - 2, nextLineY, 50, boxH)
		local textboxCustomHeight = forms.textbox(form, settings["CustomSpriteHeight"]:get() or "", 50, boxH, "UNSIGNED", rightX + 60, nextLineY - 2)
		nextLineY = nextLineY + 22

		forms.label(form, "* Must add images to /extensions/SpriteIsMeImages/", leftX, nextLineY, 300, boxH)
		nextLineY = nextLineY + 22

		forms.label(form, "Idle frame durations:", leftX, nextLineY, leftW, boxH)
		local textboxCustomIdle = forms.textbox(form, settings["CustomSpriteFramesIdle"]:get() or "", rightW, boxH, nil, rightX, nextLineY - 2)
		nextLineY = nextLineY + 22
		forms.label(form, "Walk frame durations:", leftX, nextLineY, leftW, boxH)
		local textboxCustomWalk = forms.textbox(form, settings["CustomSpriteFramesWalk"]:get() or "", rightW, boxH, nil, rightX, nextLineY - 2)
		nextLineY = nextLineY + 22
		forms.label(form, "Sleep frame durations:", leftX, nextLineY, leftW, boxH)
		local textboxCustomSleep = forms.textbox(form, settings["CustomSpriteFramesSleep"]:get() or "", rightW, boxH, nil, rightX, nextLineY - 2)
		nextLineY = nextLineY + 22
		forms.label(form, "Faint frame durations:", leftX, nextLineY, leftW, boxH)
		local textboxCustomFaint = forms.textbox(form, settings["CustomSpriteFramesFaint"]:get() or "", rightW, boxH, nil, rightX, nextLineY - 2)
		nextLineY = nextLineY + 22

		nextLineY = nextLineY + 5
		forms.button(form, Resources.AllScreens.Save, function()
			local pokemonText = forms.gettext(dropdownPokemonNames) or ""
			local pokemonID = PokemonData.getIdFromName(pokemonText) or 0
			if PokemonData.isValid(pokemonID) then
				settings["ForceUsePokemon"].values = { pokemonID }
			else
				settings["ForceUsePokemon"].values = {}
			end
			settings["ForceUsePokemon"]:save()

			local customNameText = forms.gettext(textboxCustomName) or ""
			if customNameText ~= "" then
				settings["CustomSpriteName"].values = { customNameText }
				settings["CustomSpriteName"]:save()
				settings["CustomSpriteWidth"].values = { forms.gettext(textboxCustomWidth) or "" }
				settings["CustomSpriteWidth"]:save()
				settings["CustomSpriteHeight"].values = { forms.gettext(textboxCustomHeight) or "" }
				settings["CustomSpriteHeight"]:save()

				local customIdleText = forms.gettext(textboxCustomIdle) or ""
				settings["CustomSpriteFramesIdle"].values = Utils.split(customIdleText, ",", true)
				settings["CustomSpriteFramesIdle"]:save()
				local customWalkText = forms.gettext(textboxCustomWalk) or ""
				settings["CustomSpriteFramesWalk"].values = Utils.split(customWalkText, ",", true)
				settings["CustomSpriteFramesWalk"]:save()
				local customSleepText = forms.gettext(textboxCustomSleep) or ""
				settings["CustomSpriteFramesSleep"].values = Utils.split(customSleepText, ",", true)
				settings["CustomSpriteFramesSleep"]:save()
				local customFaintText = forms.gettext(textboxCustomFaint) or ""
				settings["CustomSpriteFramesFaint"].values = Utils.split(customFaintText, ",", true)
				settings["CustomSpriteFramesFaint"]:save()
				self.updateIconData()
			else
				settings["CustomSpriteName"].values = {}
				settings["CustomSpriteName"]:save()
			end
			Utils.closeBizhawkForm(form)
			Program.redraw(true)
		end, 30, nextLineY)
		forms.button(form, Resources.AllScreens.Clear, function()
			forms.settext(dropdownPokemonNames, Constants.BLANKLINE)
			forms.settext(textboxCustomName, "")
			forms.settext(textboxCustomWidth, "")
			forms.settext(textboxCustomHeight, "")
			forms.settext(textboxCustomIdle, "")
			forms.settext(textboxCustomWalk, "")
			forms.settext(textboxCustomSleep, "")
			forms.settext(textboxCustomFaint, "")
		end, 120, nextLineY)
		forms.button(form, Resources.AllScreens.Cancel, function()
			Utils.closeBizhawkForm(form)
		end, 210, nextLineY)
	end

	function self.updateIconData()
		local customKey = settings["CustomSpriteName"]:get() or ""
		if customKey == "" then
			return
		end
		SpriteData.IconData[customKey] = {}
		local w = tonumber(settings["CustomSpriteWidth"]:get() or "") or 32
		local h = tonumber(settings["CustomSpriteHeight"]:get() or "") or 32
		local framesToLoad = {
			[SpriteData.Types.Idle] = "CustomSpriteFramesIdle",
			[SpriteData.Types.Walk] = "CustomSpriteFramesWalk",
			[SpriteData.Types.Sleep] = "CustomSpriteFramesSleep",
			[SpriteData.Types.Faint] = "CustomSpriteFramesFaint",
		}
		for typeKey, settingsKey in pairs(framesToLoad) do
			local fileName = self.buildSpritePath(typeKey, customKey, ".png", true)
			if FileManager.fileExists(fileName) and #(settings[settingsKey].values or {}) > 0 then
				SpriteData.IconData[customKey][typeKey] = { w = w, h = h, durations = {} }
				for _, frame in ipairs(settings[settingsKey].values) do
					local frameValue = tonumber(frame)
					if frameValue then
						table.insert(SpriteData.IconData[customKey][typeKey].durations, frameValue)
					end
				end
			end
		end
		-- Recreate the sprite to refresh any changes
		SpriteData.createActiveIcon(customKey)
	end

	-- Tracker specific functions, can't rename these functions
	-- Executed only once: when the Tracker finishes starting up and after it loads all other required files and code
	function self.startup()
		if not Main.IsOnBizhawk() then return end
		-- Load all settings
		for _, setting in pairs(settings or {}) do
			setting:load()
		end

		if not SpriteData.animationAllowed() then
			originalAnimationAllowed = SpriteData.animationAllowed
			local function animationOverride() return true end
			SpriteData.animationAllowed = animationOverride
		end
		if Options["Allow sprites to walk"] ~= true then
			originalWalkSetting = Options["Allow sprites to walk"]
			Options["Allow sprites to walk"] = true
		end

		self.updateIconData()
	end

	-- Executed only once: When the extension is disabled by the user, necessary to undo any customizations, if able
	function self.unload()
		if not Main.IsOnBizhawk() then return end

		if originalAnimationAllowed ~= nil then
			SpriteData.animationAllowed = originalAnimationAllowed
		end
		if originalWalkSetting ~= nil then
			Options["Allow sprites to walk"] = originalWalkSetting
		end
	end

	-- Executed when the user clicks the "Options" button while viewing the extension details within the Tracker's UI
	function self.configureOptions()
		if not Main.IsOnBizhawk() then return end

		self.openOptionsPopup()
	end

	-- Executed when the user clicks the "Check for Updates" button while viewing the extension details within the Tracker's UI
	function self.checkForUpdates()
		local versionCheckUrl = string.format("https://api.github.com/repos/%s/releases/latest", self.github)
		local versionResponsePattern = '"tag_name":%s+"%w+(%d+%.%d+)"' -- matches "1.0" in "tag_name": "v1.0"
		local downloadUrl = string.format("https://github.com/%s/releases/latest", self.github)
		local compareFunc = function(a, b) return a ~= b and not Utils.isNewerVersion(a, b) end -- if current version is *older* than online version
		local isUpdateAvailable = Utils.checkForVersionUpdate(versionCheckUrl, self.version, versionResponsePattern, compareFunc)
		return isUpdateAvailable, downloadUrl
	end

	-- Executed once every 30 frames or after any redraw event is scheduled (i.e. most button presses)
	function self.afterRedraw()
		if not Main.IsOnBizhawk() then return end

		self.drawSpriteOnScreen()
	end

	return self
end
return SpriteIsMe