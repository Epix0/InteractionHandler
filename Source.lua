return (function(player)
	local Interaction = {}

	local ContextAction = game:GetService("ContextActionService")
	local cullingCache do
		cullingCache = {
			__actionNames = {},
			__prompts = {}
		}
		function cullingCache.add(self, value)
			if type(value) == "string" then
				table.insert(self.__actionNames, value)
			else
				table.insert(self.__prompts, value)
			end
		end

		function cullingCache.remove(self, value)
			if type(value) == "string" then
				table.remove(self.__actionNames, table.find(self.__actionNames, value))
			else
				self.__attachments[table.find(self.__attachments, value)] = nil -- prolly never gets used
			end
		end

		function cullingCache.reset(self)
			table.clear(self.__actionNames)
			table.clear(self.__prompts)
		end
	end

	local function get(root, name)
		return root:FindFirstChild(name) or root:WaitForChild(name)
	end

	local function CULL()
		for _, name in pairs(cullingCache.__actionNames) do
			ContextAction:UnbindAction(name)
		end

		for _, prompt in pairs(cullingCache.__prompts) do
			prompt:Destroy()
		end	

		cullingCache:reset()
	end

	local function connectHumanoidDied(character)
		get(character, "Humanoid").Died:Connect(CULL)
	end

	local character do
		character = player.Character or player.CharacterAdded:Wait()
		connectHumanoidDied(character)
		player.CharacterAdded:Connect(function(model)
			if not model.Parent then
				while not model.Parent do
					task.wait()
				end
			end

			character = model
			connectHumanoidDied(character)
		end)
	end

	local guiMask = get(get(script, "Configuration"), "Container").Value
	local playerGui = get(player, "PlayerGui")

	--local getUIElements do
	--	getUIElements = function(container)
	--		local subConfigFolder = get(container, "Configuration")

	--		return {
	--			KeyCodeLabel = get(subConfigFolder, "KeyCodeLabel").Value,
	--			ActionNameLabel = get(subConfigFolder, "ActionNameLabel").Value
	--		}
	--	end
	--end

	local function newPrompt()
		local prompt = Instance.new("ProximityPrompt")
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
		prompt.Enabled = true
		prompt.KeyboardKeyCode = Enum.KeyCode.F15 -- normal keys conflict with contextactionservice

		cullingCache:add(prompt)
		return prompt
	end

	local DELAY = game:GetService("Players").RespawnTime
	local function newBillboardGui(parent)
		local gui = Instance.new("BillboardGui")

		gui.ResetOnSpawn = false
		gui.Enabled = false

		local listLayout = Instance.new("UIListLayout")
		listLayout.Parent = gui
		listLayout.Padding = UDim.new(0, 4)
		listLayout.FillDirection = Enum.FillDirection.Vertical
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

		gui.Size = UDim2.new(0, 350, 0, 30)
		gui.ClipsDescendants = false
		gui.Parent = playerGui

		task.delay(DELAY, function()
			gui.ResetOnSpawn = true --[[
				This was a fun one to figure out :\
				It appears that the Backpack is purged before the PlayerGui during respawn, so tool scripts will run first.
				The new BillboardGui will be made and parented before the PlayerGui reset, and assuming ResetOnSpawn is true,
					the new ui will be culled
			]]
		end)
		return gui
	end

	local function createPromptConnections(interactionObject : Interaction_Object)
		local prompt = interactionObject.__proximityPrompt
		prompt.PromptShown:Connect(function()
			interactionObject:__update()
			interactionObject.__billboardGui.Enabled = true
		end)
		prompt.PromptHidden:Connect(function()
			interactionObject.__billboardGui.Enabled = false
			interactionObject:__unbindAllActions()
			interactionObject:__cleanup()
		end)
	end

	function Interaction.new()
		local meta = {
			__parent = get(character, "HumanoidRootPart"),
			__context = {},
			__boundActions = {}, -- k, action name ; v, Enum.KeyCode
			__visibleContainers = {},
		}

		meta.__billboardGui = newBillboardGui()
		meta.__proximityPrompt = newPrompt()

		meta.__bindKey = function(self, actionName, callback, keyCode : Enum.KeyCode)
			if not self.__boundActions[actionName] then

				ContextAction:BindAction(actionName, callback, false, keyCode)
				cullingCache:add(actionName)
				self.__boundActions[actionName] = keyCode
			else
				warn("Attempted to override existing bound keycode for context ".. actionName)
			end
		end

		meta.__cleanup = function(self)
			local visibleContainers = self.__visibleContainers
			for _, container in pairs(visibleContainers) do
				container:Destroy()
			end

			table.clear(visibleContainers)
		end

		meta.__unbindActionName = function(self, name)
			local boundActions = self.__boundActions

			if boundActions[name] then
				ContextAction:UnbindAction(name)
				boundActions[name] = nil
				cullingCache:remove(name)
			end
		end

		meta.__onShowing = nil

		meta.__setOnShowing = function(self, c)
			self.__onShowing = c
		end

		meta.__unbindAllActions = function(self)
			local boundActions = self.__boundActions

			for actionName, _ in pairs(boundActions) do
				ContextAction:UnbindAction(actionName)
				boundActions[actionName] = nil
				cullingCache:remove(actionName)
			end
		end

		meta.__update = function(self)
			local boundActions = self.__boundActions
			local contextCache = self.__context
			local billboard = self.__billboardGui
			local visibleContainers = self.__visibleContainers

			for actionName, object in pairs(contextCache) do
				if not boundActions[actionName] and object.Enabled then
					local container = guiMask:Clone()
					container.Parent = billboard

					local subConfig = get(container, "Configuration")

					local actionLabel = subConfig.ActionNameLabel.Value
					actionLabel.Text = actionName

					local keyCodeLabel = subConfig.KeyCodeLabel.Value
					keyCodeLabel.Text = object.KeyCode.Name

					if self.__onShowing then
						self.__onShowing({ActionLabel = actionLabel, KeyCodeLabel = keyCodeLabel, BillboardGui = container})
					end

					visibleContainers[actionName] = container

					self:__bindKey(actionName, object.Callback, object.KeyCode)
					boundActions[actionName] = object.KeyCode

				elseif boundActions[actionName] and not object.Enabled then
					self:__unbindActionName(actionName)
					visibleContainers[actionName]:Destroy()
					visibleContainers[actionName] = nil
				end
			end
		end

		meta.__index = meta
		local object = setmetatable({}, meta)

		object.CreateContext = function(self, contextName : string, callback : (callingPlayer : Player) -> (), enumKeyCode : Enum.KeyCode, startDisabled : boolean?)
			self.__context[contextName] = {
				ActionName = contextName,
				Callback = callback,
				KeyCode = enumKeyCode,
				Enabled =  (function() if startDisabled then return false end return true end)() -- time spent enabling passive interactions > time spent enabling interaction under circumstance
			}
		end

		object.SetPositionRelativeTo = function(self, parent : BasePart | Attachment, positionOffset : Vector3)
			assert(parent, "arg #1 of SetPositionRelativeTo() expected parent Instance, got nil")
			self.__proximityPrompt.	Parent = parent
			self.__billboardGui.Adornee = parent

			self.__billboardGui.StudsOffsetWorldSpace = positionOffset or Vector3.new(0, 0, 0)
		end

		object.Enable = function(self)
			self.__proximityPrompt.Enabled = true
			self.__billboardGui.Enabled = true
		end

		object.Disable = function(self)
			self.__proximityPrompt.Enabled = false
			self.__billboardGui.Enabled = false
		end

		object.SetContextState = function(self, contextName : string, state : boolean)
			local context = self.__context[contextName]
			if context then
				context.Enabled = state
				self:__update()
			end
		end

		object.SetShowingCallback = function(self, callback)
			self:__setOnShowing(callback)
		end

		createPromptConnections(object)
		return object
	end

	--type Interaction_Object = typeof(Interaction.new())
	export type Interaction_Object = typeof(Interaction.new())
	return Interaction
end)

-- Epix0(ServerStettler)