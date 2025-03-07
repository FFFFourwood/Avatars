require "scripts/util"
require "scripts/storage"
require "scripts/deployment"
require "scripts/avatar_control"
require "scripts/sort"
require "scripts/gui"

require "scripts/migrations"
require "scripts/compatibility"

-- Initialize global tables
script.on_init(function()
	Storage.init()
	Compatibility.run_all()
end)

script.on_load(function()
	Compatibility.run_all()
end)

-- Migrations
script.on_configuration_changed(function(data)
	Migrations.handle(data)
end)

-- Check when a player leaves the game
function on_player_left_game(event)
	local player = game.players[event.player_index]
	AvatarControl.loseAvatarControl(player, 0)
end

script.on_event(defines.events.on_pre_player_left_game, on_player_left_game)

function on_player_joined_game(event)
	local player = game.players[event.player_index]
	Storage.Avatars.repairOnJoinedGame(player)
end

script.on_event(defines.events.on_player_joined_game, on_player_joined_game)

-- Check on entering or leaving a vehicle
function on_driving(event)
	local player = game.players[event.player_index]
	
	-- Check for entering the Avatar Control Center
	if player.vehicle and player.vehicle.name == "avatar-control-center" then
		GUI.Selection.draw(player)
		debugLog("Getting in")
		
	-- Check for entering the Avatar Remote Deployment unit (ARDU)
	elseif player.vehicle and player.vehicle.name == "avatar-remote-deployment-unit" then
		GUI.ARDU.draw(player, player.vehicle)
		
	-- Otherwise, destroy vehicle GUIs
	else
		GUI.Main.destroy(player)
		GUI.ARDU.destroy(player)
		debugLog("Getting out")
	end
end

script.on_event(defines.events.on_player_driving_changed_state, on_driving)

-- Check on GUI click
function checkGUI(event)
	local elementName = event.element.name
	local player = game.players[event.player_index]
	debugLog("Clicked "..elementName)
	
	-- Avatar button ("avatar_"..4LetterCode...)
	local modSubString = string.sub(elementName, 1, 7)
	
	-- Look for button header
	if modSubString == "avatar_" then
		debugLog("Avatar Mod button press")
		
		-- Look for the individual buttons
		local modButton = string.sub(elementName, 8, 11)
		debugLog("Button pushed: "..modButton)
		
		-- Rename button
		if modButton == "rnam" then
			-- Obtain the old name
			local name = string.sub(elementName, 13)
			GUI.Rename.draw(player, name)
			
		elseif modButton == "ctrl" then
			-- Control button
			-- Obtain the name of the avatar to control
			if GUI.Selection.isAllowedOrDestroy(player) then
				local name = string.sub(elementName, 13)
				AvatarControl.gainAvatarControl(player, name, event.tick)
			end
			
		elseif modButton == "rfrh" then
			-- Selection Refresh button
			GUI.Main.update(player)
			
		elseif modButton == "sbmt" then
			-- Submit button (to submit a rename)
			if GUI.Selection.isAllowedOrDestroy(player) then
				GUI.Trigger.changeAvatarNameSubmit(player)
			end
			
		elseif modButton == "cncl" then
			-- Cancel button (to cancel a rename)
			GUI.Rename.destroy(player)
			
		elseif modButton == "exit" then
			-- Exit button (for control center ui)
			GUI.Main.destroy(player)
			GUI.ARDU.destroy(player)
			
			local vehicle = player.vehicle
			if vehicle and vehicle.valid and vehicle.name == "avatar-control-center" then
				local driver = vehicle.get_driver()
				if driver and driver.valid then
					if driver.object_name == "LuaEntity" then
						driver = driver.player
					end
					if driver and driver.index == player.index then
						vehicle.set_driver(nil)
					else
						vehicle.set_passenger(nil)
					end
				else
					vehicle.set_passenger(nil)
				end
			end
			
		elseif modButton == "disc" then
			-- Disconnect button (to disconnect from the avatar)
			AvatarControl.loseAvatarControl(player, event.tick)
			
		elseif modButton == "ARDU" then
			-- The ARDU submit button
			GUI.Trigger.changeARDUName(player)
		end
	end
end

script.on_event(defines.events.on_gui_click, checkGUI)

-- Handles the checkbox checked event
function checkboxChecked(event)
	local elementName = event.element.name
	local player = game.players[event.player_index]
	
	-- Check for avatar sort checkbox ("avatar_sort_")
	local modSubString = string.sub(elementName, 1, 12)
	
	if modSubString == "avatar_sort_" then
		debugLog("Avatar Mod Radio-button press")
		
		-- Look for the individual button
		local modButton = string.sub(elementName, 13, #elementName)
		debugLog("Radio-button pushed: "..modButton)
		
		-- Check for each sort button
		GUI.Selection.flipRadioButtons(player, modButton)
		
		-- Update the Selection GUI
		GUI.Selection.update(player)
	end
end

script.on_event(defines.events.on_gui_checked_state_changed, checkboxChecked)

-- Check on an entity being built
function on_entity_built(event)
	local entity = event.created_entity or event.entity or event.destination
	if entity then
		if entity.name == "avatar-control-center" then
			entity.operable = false
			return
			
		elseif entity.name == "avatar" then
			--Add avatars to the table
			Storage.Avatars.add(entity)
			
		elseif entity.name == "avatar-remote-deployment-unit" then
			--Add ARDU to the table
			Storage.ARDU.add(entity)
		end
	end
end

script.on_event(defines.events.on_robot_built_entity, on_entity_built)
script.on_event(defines.events.on_built_entity, on_entity_built)
script.on_event(defines.events.script_raised_built, on_entity_built)
script.on_event(defines.events.script_raised_revive, on_entity_built)

function on_entity_cloned(event)
	local destination = event.destination
	Storage.repairFromClone(event.source, destination)

	if destination and destination.name == "avatar-control-center" then
		destination.operable = false
	end
end

script.on_event(defines.events.on_entity_cloned, on_entity_cloned)

-- Check on entity being destroyed or deconstructed
function on_entity_destroyed(event)
	local entity = event.entity
	
	-- Destruction of an Avatar Control Center
	if entity.name == "avatar-control-center" then
		-- Check if a player was using it
		local driver = entity.get_driver()
		local playerData = Storage.PlayerData.getByEntity(driver)
		
		if playerData and playerData.currentAvatarData then
			local player = playerData.player
			AvatarControl.loseAvatarControl(player, event.tick)
			GUI.destroyAll(player)
			player.print{"Avatars-error-avatar-control-center-destroyed"}
		end
		
	elseif entity.name == "avatar" then
		-- Destruction of an Avatar
		-- Remove the avatar from the global table (The player is no longer in control at this point)
		Storage.Avatars.remove(entity)

	elseif entity.name == "avatar-corpse" then
		-- Mining of an Avatar corpse
		on_corpse_expired({corpse = entity})

	elseif entity.name == "avatar-remote-deployment-unit" then
		-- Destruction of an ARDU
		Storage.ARDU.remove(entity)
	end
end

function on_entity_died(event)
	local entity = event.entity
	
	if entity.name == "character" then
		local playerData = Storage.PlayerData.getByEntity(entity)
		
		if playerData then
			local player = playerData.player
			local realBody = playerData.realBody
			debugLog(player.name .. "'s real body died")
			
			-- Make a new body for the player, and give it to them
			local newBody = realBody.surface.create_entity{name="fake-player", position=realBody.position, force=realBody.force}
			playerData.realBody = newBody
			AvatarControl.loseAvatarControl(playerData.player, event.tick)
			
			-- Now kill them
			newBody.die(event.force, event.cause)
			GUI.destroyAll(player)
		end
		return
	end
	
	on_entity_destroyed(event)
end

script.on_event(defines.events.on_pre_player_mined_item, on_entity_destroyed)
script.on_event(defines.events.on_robot_pre_mined, on_entity_destroyed)
script.on_event(defines.events.script_raised_destroy, on_entity_destroyed)
script.on_event(defines.events.on_entity_died, on_entity_died)

function on_post_character_died(event)
	for _, corpse in ipairs(event.corpses) do
		if corpse.name == "avatar-corpse" then
			local tag = event.force.add_chart_tag(event.surface_index, {
				position = event.position,
				icon = {type = "item", name = "avatar"}
			})
			Storage.MapTags.add(corpse, tag)
		end
	end
end

script.on_event(defines.events.on_post_entity_died, on_post_character_died,{{filter = "type", type = "character"}})

-- Check on corpse being expired
function on_corpse_expired(event)
	local corpse = event.corpse
	local tag = Storage.MapTags.remove(corpse)
	if tag and tag.valid then
		debugLog("Destroying map tag")
		tag.destroy()
	end
end

script.on_event(defines.events.on_character_corpse_expired, on_corpse_expired)

-- Handles a player dying while controlling an avatar
function on_preplayer_died(event)
	local player = game.players[event.player_index]
	
	if player and player.character and player.character.name == "avatar" then
		AvatarControl.loseAvatarControl(player, 0)
		player.print{"Avatars-error-controlled-avatar-death"}
	end
end

script.on_event(defines.events.on_pre_player_died, on_preplayer_died)

-- Handler for the hotkey to disconnect from an avatar
function on_hotkey(event)
	local player = game.players[event.player_index]
	
	AvatarControl.loseAvatarControl(player, event.tick)
end

script.on_event("avatars_disconnect", on_hotkey)


-- Handler for when the player teleports to a different surface
function on_player_changed_surface(event)
	local player = game.players[event.player_index]
	local playerData = Storage.PlayerData.getOrCreate(player)
	
	-- If the player is controlling an avatar, then we need to fix the entity reference to that avatar
	-- Otherwise, it becomes invalid
	if player.character and player.character.name == "avatar" and playerData.currentAvatarData then
		debugLog("Re-referencing avatar")
		playerData.currentAvatarData.entity = player.character
	end
end

script.on_event(defines.events.on_player_changed_surface, on_player_changed_surface)


-- Handle for setting changes
function on_runtime_mod_setting_changed(event)
	local name = event["setting"]
	
	if name == "Avatars_avatar_ownership" then
		for _, player in pairs(game.players) do
			GUI.Main.update(player)
		end
	end
end

script.on_event(defines.events.on_runtime_mod_setting_changed, on_runtime_mod_setting_changed)


--~~~~~~~ Remote Calls ~~~~~~~--
--Mod Interfaces

-- This isn't needed any more, since the script_raised_built event exists, so please use that
-- Just keeping it in case someone is still using it
--remote.call("Avatars_avatar_placement", "addAvatar", arg)
remote.add_interface("Avatars_avatar_placement", {
	addAvatar = function(entity)
		if entity and entity.valid then
			if entity.name == "avatar" then
				Storage.Avatars.add(entity)
			end
		end
	end
})


-- Mod compatibility
remote.add_interface("Avatars_compat", {
	on_character_swapped = function(data)
		local oldCharacter = data.old_character
		local newCharacter = data.new_character
		if oldCharacter and oldCharacter.valid and newCharacter and newCharacter.valid then
			Storage.swapCharacter(oldCharacter, newCharacter)
		end
	end
})

commands.add_command("repair_avatars", {"Avatars-command-help-repair-avatars"}, function(command)
	if command.player_index then
		local player = game.get_player(command.player_index)
		debugLog(player.name .. " is running repair command")
		local group = player.permission_group
		if not group then
			debugLog("Player not in permission group, not allowed to do anything")
			return
		end
		local allowedGroupsSetting = settings.global["Avatars_command_allowed_groups"].value
		local allowedGroups = Util.tableToSet(Util.splitString(allowedGroupsSetting, ","))
		if not (group.allows_action(defines.input_action.admin_action) or allowedGroups[group.name]) then
			debugLog("Player is not admin or group is not allowed to run Avatar commands")
			return
		end
	end
	Storage.Avatars.repair()
end)


commands.add_command("avatars_repair_player_temporary", "PLAYER_NAME -- Fix invalid players references for the Avatars mod. If you don't know what this does or why you need it, then you DON'T need it. See the mod portal thread \"0.5.25 - Avatar Player References Broken\" for more info.", function(command) -- TODO - remove eventually, this was for a migration from 0.5.24 to 0.5.25
	local commandPlayer = game.get_player(command.player_index)
	if command.player_index then
		debugLog(commandPlayer.name .. " is running repair command")
		local group = commandPlayer.permission_group
		if not group then
			debugLog("Player not in permission group, not allowed to do anything")
			return
		end
		local allowedGroupsSetting = settings.global["Avatars_command_allowed_groups"].value
		local allowedGroups = Util.tableToSet(Util.splitString(allowedGroupsSetting, ","))
		if not (group.allows_action(defines.input_action.admin_action) or allowedGroups[group.name]) then
			debugLog("Player is not admin or group is not allowed to run Avatar commands")
			return
		end
	end
	local targetPlayer = commandPlayer
	if command.parameter then
		targetPlayer = game.get_player(command.parameter)
	end

	if not (targetPlayer and targetPlayer.valid) then
		commandPlayer.print(command.parameter .. " is not a valid player")
		return
	end

	local selected = commandPlayer.selected
	if selected and selected.valid and selected.name == "avatar-control-center" then
		local playerData = Storage.PlayerData.getByPlayer(targetPlayer)
		if playerData and playerData.realBody and not playerData.realBody.valid then
			Migrations._0_5_25__try_to_fix_player_from_avatar_control_center(selected, playerData)
		else
			commandPlayer.print(targetPlayer.name .. " does not have the 0.5.24 Avatars invalid player reference. This command does not need run for them.")
		end
	else
		commandPlayer.print({"", "ERROR: Select an ", {"entity-name.avatar-control-center"}, " when running this command. See the mod portal at https://mods.factorio.com/mod/Avatars for more information on this error and how to fix it."})
	end
end)

--User Commands
remote.add_interface("Avatars", {
	--Used to remove invalidated Avatars from the global listing, and search for orphaned avatars that are missing from the listing
	-- /c remote.call("Avatars", "repair_avatars_listing")
	repair_avatars_listing = function()
		Storage.Avatars.repair()
	end,
	
	--Used to force a swap back to the player's body
	-- /c remote.call("Avatars", "manual_swap_back")
	manual_swap_back = function()
		player = game.player
		if player.character.name ~= "character" then
			local playerData = Storage.PlayerData.getOrCreate(player)
			local avatarData = playerData.currentAvatarData
			
			if playerData.realBody then
				-- Give back the player's body
				player.character = playerData.realBody
				
				-- In strange waters here, this might not exist
				if avatarData then
					avatarData.entity.active = false
					avatarData.playerData = nil
				end
				
				-- Clear the table
				playerData.realBody = nil
				playerData.currentAvatarData = nil
				
				-- GUI clean up
				GUI.destroyAll(player)
			end
		else
			player.print{"avatar-remote-call-in-your-body"}
		end
	end,
	
	--LAST DITCH EFFORT
	--Only use this is your body was destroyed somehow and you can't reload a save (this will create a new body)
	-- /c remote.call("Avatars", "create_new_body")
	create_new_body = function()
		player = game.player
		if player.character.name ~= "character" then
			local playerData = Storage.PlayerData.getOrCreate(player)
			
			if playerData.realBody and playerData.realBody.valid then
				player.print{"avatar-remote-call-still-have-a-body"}
				return
			end
			
			local newBody = player.surface.create_entity{name="character", position=player.position, force=player.force}
			
			if newBody then
				-- Manually lose control
				player.character = newBody
				
				-- In strange waters here, this might not exist
				local avatarData = playerData.currentAvatarData
				if avatarData then
					avatarData.entity.active = false
					avatarData.playerData = nil
				end
				
				-- Clear the table
				playerData.realBody = nil
				playerData.currentAvatarData = nil
				
				-- GUI clean up
				GUI.destroyAll(player)
			end
		else
			player.print{"avatar-remote-call-in-your-body"}
		end
	end
})


--		DEBUG Things
-- Only initialized if the debug_mode setting is true
local debug_mode = settings.global["Avatars_debug_mode"].value
debugLog = function(s) end
if debug_mode then
	debugLog = function (message)
		for _, player in pairs(game.players) do
			player.print(message)
		end
	end
	
	remote.add_interface("Avatars_debug", {
		-- /c remote.call("Avatars_debug", "testing")
		testing = function()
			for _, player in pairs(game.players) do
				player.insert({name="avatar-control-center", count=5})
				player.insert({name="avatar-remote-deployment-unit", count=5})
				player.insert({name="avatar", count=25})
			end
		end,
		
		-- /c remote.call("Avatars_debug", "avatars_list")
		avatars_list = function()
			local count = 0
			for _, avatar in ipairs(storage.avatars) do
				count = count + 1
				debugLog(count .. ", " .. avatar.name .. ", " .. tostring(avatar.entity and avatar.entity.valid))
			end
		end,
		
		-- /c remote.call("Avatars_debug", "invalidate_avatar")
		invalidate_avatar = function()
			if #storage.avatars > 0 then
				local avatar = storage.avatars[1].entity
				local surface = avatar.surface
				local position = avatar.position
				local force = avatar.force
				local player = avatar.player
				
				avatar.destroy()
				local newAvatar = surface.create_entity({name="avatar", position=position, force=force,})

				if player then
					player.character = newAvatar
				end
			end
		end
	})
end
