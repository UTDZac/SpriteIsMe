local function SpriteIsMe()
	-- Define descriptive attributes of the custom extension that are displayed on the Tracker settings
	local self = {
		version = "0.2",
		name = "Sprite Is Me",
		author = "UTDZac",
		description = "You become the Pokémon! Requires Walking Pals icons to be turned on.",
		github = "UTDZac/SpriteIsMe-IronmonExtension",
	}
	self.url = string.format("https://github.com/%s", self.github)

	-- Other internal attributes, no need to change any of these
	local extSettingsKey = "SpriteIsMe"
	local settings = {
		["ForceUsePokemon"] = {}, -- If provided in options, will use this pokemon instead of your lead pokemon (e.g. "Mr. Mime")
	}
	local allowedIconSets = {
		["6"] = true,
	}

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

	-- If its set, returns a proper pokemon id, otherwise nil
	function self.getPokemonIDFromSettings()
		local idFromSettings = tonumber(settings["ForceUsePokemon"]:get() or "") or 0
		return PokemonData.isValid(idFromSettings) and idFromSettings or nil
	end

	function self.openOptionsPopup()
		if not Main.IsOnBizhawk() then return end

		local form = Utils.createBizhawkForm("Pick a Pokémon", 320, 130, 100, 50)
		forms.label(form, "Pokémon to become:", 28, 20, 110, 20)

		local idFromSettings = tonumber(settings["ForceUsePokemon"]:get() or "") or 0
		local boxText = PokemonData.isValid(idFromSettings) and PokemonData.Pokemon[idFromSettings].name or ""
		local textboxPokemonName = forms.textbox(form, boxText, 134, 20, nil, 150, 18)

		forms.button(form, Resources.AllScreens.Save, function()
			settings["ForceUsePokemon"].values = {}
			local text = forms.gettext(textboxPokemonName) or ""
			if text ~= "" then
				local pokemonID = DataHelper.findPokemonId(text) or 0
				if PokemonData.isValid(pokemonID) then
					settings["ForceUsePokemon"].values = { pokemonID }
				end
			end
			settings["ForceUsePokemon"]:save()
			Program.redraw(true)
			client.unpause()
			forms.destroy(form)
		end, 30, 50)
		forms.button(form, Resources.AllScreens.Clear, function()
			forms.settext(textboxPokemonName, "")
		end, 120, 50)
		forms.button(form, Resources.AllScreens.Cancel, function()
			client.unpause()
			forms.destroy(form)
		end, 210, 50)
	end

	-- Tracker specific functions, can't rename these functions
	-- Executed only once: when the Tracker finishes starting up and after it loads all other required files and code
	function self.startup()
		-- Load all settings
		for _, setting in pairs(settings or {}) do
			setting:load()
		end
	end

	-- Executed when the user clicks the "Options" button while viewing the extension details within the Tracker's UI
	function self.configureOptions()
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
		if not Program.isValidMapLocation() or Battle.inBattleScreen or not allowedIconSets[tostring(Options["Pokemon icon set"])] then
			return
		end

		local pokemonID = self.getPokemonIDFromSettings() or (Tracker.getPokemon(1, true) or {}).pokemonID or 0
		if not PokemonData.isValid(pokemonID) then
			return
		end

		local x = Constants.SCREEN.WIDTH / 2 - 16
		local y = Constants.SCREEN.HEIGHT / 2 - 24
		Drawing.drawSpriteIcon(x, y, pokemonID)
	end

	return self
end
return SpriteIsMe