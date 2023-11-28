local function SpriteIsMe()
	local self = {
		version = "1.3",
		name = "Sprite Is Me",
		author = "UTDZac",
		description = "Turns your character into your lead Pokémon, or you can choose the Pokémon you want to become.",
		github = "UTDZac/SpriteIsMe-IronmonExtension",
	}
	self.url = string.format("https://github.com/%s", self.github)

	-- Other internal attributes, no need to change any of these
	self.settingsKey = "SpriteIsMe"
	self.Settings = {
		["ForceUsePokemon"] = {}, -- If provided in options, will use this pokemon instead of your lead pokemon (e.g. "Mr. Mime")
		["DefaultIfNoPokemon"] = {},
		["CustomSpriteName"] = {},
		["CustomSpriteWidth"] = {},
		["CustomSpriteHeight"] = {},
		["CustomSpriteFramesIdle"] = {},
		["CustomSpriteFramesWalk"] = {},
		["CustomSpriteFramesSleep"] = {},
		["CustomSpriteFramesFaint"] = {},
	}
	self.forceUsePokemonId = nil
	self.defaultPokemonId = nil
	local CUSTOM_SPRITE_FOLDER = FileManager.getCustomFolderPath() .. "SpriteIsMeImages"
	local originalWalkSetting, originalAnimationAllowed
	local lastKnownFacing = 1
	local INFINITE_FUSION_EXT

	local SCREEN_CENTER_X = Constants.SCREEN.WIDTH / 2 - 16
	local SCREEN_CENTER_Y = Constants.SCREEN.HEIGHT / 2 - 24

	-- Definite save/load settings functions
	for key, setting in pairs(self.Settings or {}) do
		setting.key = tostring(key)
		if type(setting.load) ~= "function" then
			setting.load = function(this)
				local loadedValue = TrackerAPI.getExtensionSetting(self.settingsKey, this.key)
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
					TrackerAPI.saveExtensionSetting(self.settingsKey, this.key, savedValue)
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

	self.event = EventHandler.IEvent:new({
		Key = "CR_SpriteIsMeChange",
		Type = EventHandler.EventTypes.Reward,
		Name = "[EXT] Change Sprite Is Me",
		IsEnabled = true,
		RewardId = "", -- Loaded later when event is added
		Process = function() return true end,
		Fulfill = function(this, request)
			-- Check if the redeemed Pokémon is valid
			local params = (request.Args or {}).Input or ""
			if Utils.isNilOrEmpty(params, true) then
				return string.format("> Must enter a valid Pokémon name.")
			end
			local id = DataHelper.findPokemonId(params)
			if not PokemonData.isValid(id) then
				return string.format("%s > Can't find a Pokémon with this name.", params)
			end
			-- Set the SpriteIsMe extension to use that Pokémon
			local ext = TrackerAPI.getExtensionSelf(self.settingsKey)
			if ext then
				ext.forceUsePokemonId = id
				local extSettings = ext.Settings and ext.Settings["ForceUsePokemon"]
				if extSettings then
					ext.Settings["ForceUsePokemon"].values = { id }
					ext.Settings["ForceUsePokemon"]:save()
				end
				Program.redraw(true)
			end
			-- Return an empty response, no output necssary if it works
			return ""
		end,
	})

	function self.drawSpriteOnScreen()
		if not Program.isValidMapLocation() or Battle.inBattleScreen or Program.currentOverlay ~= nil then
			return
		end
		-- Check other overlays
		if LogOverlay.isDisplayed or UpdateScreen.showNotes or (StreamConnectOverlay and StreamConnectOverlay.isDisplayed) then
			return
		end
		if INFINITE_FUSION_EXT and INFINITE_FUSION_EXT.isDisplayed then
			return
		end

		local iconKey
		local useCustom = false

		local spriteId = self.forceUsePokemonId
		local spriteName = self.Settings["CustomSpriteName"]:get() or ""
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

		iconKey = iconKey or self.defaultPokemonId
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

		-- Only these two animation types allow for facing different directions.
		if activeIcon.animationType ~= SpriteData.Types.Walk and activeIcon.animationType ~= SpriteData.Types.Idle then
			facingFrame = 1
			lastKnownFacing = 1
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

	function self.openOptionsPopup()
		if not Main.IsOnBizhawk() then return end

		local form = Utils.createBizhawkForm("SpriteIsMe Options", 320, 340, 100, 20)

		local leftX, leftW = 28, 115
		local rightX, rightW = 152, 134
		local boxH = 20
		local nextLineY = 12
		local allPokemonNames = PokemonData.namesToList()
		table.insert(allPokemonNames, 1, Constants.BLANKLINE)

		forms.label(form, "Default if no Pokémon:", leftX, nextLineY, leftW, boxH)
		local defaultPokemonName = PokemonData.isValid(self.defaultPokemonId) and PokemonData.Pokemon[self.defaultPokemonId].name or Constants.BLANKLINE
		local dropdownPokemonDefault = forms.dropdown(form, {["Init"]="Loading Names"}, rightX, nextLineY - 2, rightW, boxH)
		forms.setdropdownitems(dropdownPokemonDefault, allPokemonNames, true) -- true = alphabetize the list
		forms.setproperty(dropdownPokemonDefault, "AutoCompleteSource", "ListItems")
		forms.setproperty(dropdownPokemonDefault, "AutoCompleteMode", "Append")
		forms.settext(dropdownPokemonDefault, defaultPokemonName)
		nextLineY = nextLineY + 27

		local headerText = string.format("%s %s %s", string.rep(Constants.BLANKLINE, 10), Utils.toUpperUTF8("Sprite Override"), string.rep(Constants.BLANKLINE, 10))
		forms.label(form, headerText, leftX - 18, nextLineY, 400, boxH)
		nextLineY = nextLineY + 22

		-- Existing Pokemon Sprites
		local chosenPokemonName = PokemonData.isValid(self.forceUsePokemonId) and PokemonData.Pokemon[self.forceUsePokemonId].name or Constants.BLANKLINE
		-- local textboxPokemonName = forms.textbox(form, chosenPokemonName, rightW, boxH, nil, rightX, nextLineY - 2)
		forms.label(form, "Always use Pokémon:", leftX, nextLineY, leftW, boxH)
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
		local textboxCustomName = forms.textbox(form, self.Settings["CustomSpriteName"]:get() or "", rightW, boxH, nil, rightX, nextLineY - 2)
		nextLineY = nextLineY + 22
		forms.label(form, "Width:", leftX, nextLineY, 50, boxH)
		local textboxCustomWidth = forms.textbox(form, self.Settings["CustomSpriteWidth"]:get() or "", 50, boxH, "UNSIGNED", leftX + 60, nextLineY - 2)
		forms.label(form, "Height:", rightX - 2, nextLineY, 50, boxH)
		local textboxCustomHeight = forms.textbox(form, self.Settings["CustomSpriteHeight"]:get() or "", 50, boxH, "UNSIGNED", rightX + 60, nextLineY - 2)
		nextLineY = nextLineY + 22

		forms.label(form, "* Must add images to /extensions/SpriteIsMeImages/", leftX, nextLineY, 300, boxH)
		nextLineY = nextLineY + 22

		forms.label(form, "Idle frame durations:", leftX, nextLineY, leftW, boxH)
		local textboxCustomIdle = forms.textbox(form, self.Settings["CustomSpriteFramesIdle"]:get() or "", rightW, boxH, nil, rightX, nextLineY - 2)
		nextLineY = nextLineY + 22
		forms.label(form, "Walk frame durations:", leftX, nextLineY, leftW, boxH)
		local textboxCustomWalk = forms.textbox(form, self.Settings["CustomSpriteFramesWalk"]:get() or "", rightW, boxH, nil, rightX, nextLineY - 2)
		nextLineY = nextLineY + 22
		forms.label(form, "Sleep frame durations:", leftX, nextLineY, leftW, boxH)
		local textboxCustomSleep = forms.textbox(form, self.Settings["CustomSpriteFramesSleep"]:get() or "", rightW, boxH, nil, rightX, nextLineY - 2)
		nextLineY = nextLineY + 22
		forms.label(form, "Faint frame durations:", leftX, nextLineY, leftW, boxH)
		local textboxCustomFaint = forms.textbox(form, self.Settings["CustomSpriteFramesFaint"]:get() or "", rightW, boxH, nil, rightX, nextLineY - 2)
		nextLineY = nextLineY + 22

		nextLineY = nextLineY + 5
		forms.button(form, Resources.AllScreens.Save, function()
			local defaultId = PokemonData.getIdFromName(forms.gettext(dropdownPokemonDefault) or "") or 0
			if PokemonData.isValid(defaultId) then
				self.defaultPokemonId = defaultId
				self.Settings["DefaultIfNoPokemon"].values = { defaultId }
			else
				self.defaultPokemonId = nil
				self.Settings["DefaultIfNoPokemon"].values = {}
			end
			self.Settings["DefaultIfNoPokemon"]:save()

			local pokemonId = PokemonData.getIdFromName(forms.gettext(dropdownPokemonNames) or "") or 0
			if PokemonData.isValid(pokemonId) then
				self.forceUsePokemonId = pokemonId
				self.Settings["ForceUsePokemon"].values = { pokemonId }
			else
				self.forceUsePokemonId = nil
				self.Settings["ForceUsePokemon"].values = {}
			end
			self.Settings["ForceUsePokemon"]:save()

			local customNameText = forms.gettext(textboxCustomName) or ""
			if customNameText ~= "" then
				self.Settings["CustomSpriteName"].values = { customNameText }
				self.Settings["CustomSpriteName"]:save()
				self.Settings["CustomSpriteWidth"].values = { forms.gettext(textboxCustomWidth) or "" }
				self.Settings["CustomSpriteWidth"]:save()
				self.Settings["CustomSpriteHeight"].values = { forms.gettext(textboxCustomHeight) or "" }
				self.Settings["CustomSpriteHeight"]:save()

				local customIdleText = forms.gettext(textboxCustomIdle) or ""
				self.Settings["CustomSpriteFramesIdle"].values = Utils.split(customIdleText, ",", true)
				self.Settings["CustomSpriteFramesIdle"]:save()
				local customWalkText = forms.gettext(textboxCustomWalk) or ""
				self.Settings["CustomSpriteFramesWalk"].values = Utils.split(customWalkText, ",", true)
				self.Settings["CustomSpriteFramesWalk"]:save()
				local customSleepText = forms.gettext(textboxCustomSleep) or ""
				self.Settings["CustomSpriteFramesSleep"].values = Utils.split(customSleepText, ",", true)
				self.Settings["CustomSpriteFramesSleep"]:save()
				local customFaintText = forms.gettext(textboxCustomFaint) or ""
				self.Settings["CustomSpriteFramesFaint"].values = Utils.split(customFaintText, ",", true)
				self.Settings["CustomSpriteFramesFaint"]:save()
				self.updateIconData()
			else
				self.Settings["CustomSpriteName"].values = {}
				self.Settings["CustomSpriteName"]:save()
			end
			Utils.closeBizhawkForm(form)
			Program.redraw(true)
		end, 30, nextLineY)
		forms.button(form, Resources.AllScreens.Clear, function()
			forms.settext(dropdownPokemonDefault, Constants.BLANKLINE)
			forms.settext(dropdownPokemonNames, Constants.BLANKLINE)
			forms.settext(textboxCustomName, "")
			forms.settext(textboxCustomWidth, "")
			forms.settext(textboxCustomHeight, "")
			forms.settext(textboxCustomIdle, "")
			forms.settext(textboxCustomWalk, "")
			forms.settext(textboxCustomSleep, "")
			forms.settext(textboxCustomFaint, "")
		end, 121, nextLineY)
		forms.button(form, Resources.AllScreens.Cancel, function()
			Utils.closeBizhawkForm(form)
		end, 212, nextLineY)
	end

	function self.updateIconData()
		local customKey = self.Settings["CustomSpriteName"]:get() or ""
		if customKey == "" then
			return
		end
		SpriteData.IconData[customKey] = {}
		local w = tonumber(self.Settings["CustomSpriteWidth"]:get() or "") or 32
		local h = tonumber(self.Settings["CustomSpriteHeight"]:get() or "") or 32
		local framesToLoad = {
			[SpriteData.Types.Idle] = "CustomSpriteFramesIdle",
			[SpriteData.Types.Walk] = "CustomSpriteFramesWalk",
			[SpriteData.Types.Sleep] = "CustomSpriteFramesSleep",
			[SpriteData.Types.Faint] = "CustomSpriteFramesFaint",
		}
		for typeKey, settingsKey in pairs(framesToLoad) do
			local fileName = self.buildSpritePath(typeKey, customKey, ".png", true)
			if FileManager.fileExists(fileName) and #(self.Settings[settingsKey].values or {}) > 0 then
				SpriteData.IconData[customKey][typeKey] = { w = w, h = h, durations = {} }
				for _, frame in ipairs(self.Settings[settingsKey].values) do
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

	function self.loadSettings()
		for _, setting in pairs(self.Settings or {}) do
			setting:load()
		end
		local id = tonumber(self.Settings["ForceUsePokemon"]:get() or "")
		self.forceUsePokemonId = PokemonData.isValid(id) and id or nil
		id = tonumber(self.Settings["DefaultIfNoPokemon"]:get() or "")
		self.defaultPokemonId = PokemonData.isValid(id) and id or nil
	end

	-- Tracker specific functions, can't rename these functions
	-- Executed only once: when the Tracker finishes starting up and after it loads all other required files and code
	function self.startup()
		if not Main.IsOnBizhawk() then return end

		if not SpriteData.animationAllowed() then
			originalAnimationAllowed = SpriteData.animationAllowed
			local function animationOverride() return true end
			SpriteData.animationAllowed = animationOverride
		end
		if Options["Allow sprites to walk"] ~= true then
			originalWalkSetting = Options["Allow sprites to walk"]
			Options["Allow sprites to walk"] = true
		end

		self.loadSettings()
		self.updateIconData()
		INFINITE_FUSION_EXT = TrackerAPI.getExtensionSelf("InfiniteFusion")
		EventHandler.addNewEvent(self.event)
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
		EventHandler.removeEvent(self.event.Key)
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