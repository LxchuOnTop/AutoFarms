local settings = {
	["Mode"] = "Safe",
	["AutofarmSpeed"] = 27.5,
	["TweenDelay"] = 0.09,
	["CoinAuraDistance"] = 6,
	["CoinType"] = "Coin",
	["ResetIfDone"] = true,
	["ShootMurdererIfDone"] = false,
	["KillEveryoneIfDone"] = false,
	["UI"] = true,
	["UIMode"] = 2,
	["FullyOptimizeWhileGrinding"] = false,
}

local player = game:GetService('Players').LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild('HumanoidRootPart')
local lowerTorso = character:WaitForChild('LowerTorso')
local upperTorso = character:WaitForChild('UpperTorso')
local humanoid = character:WaitForChild('Humanoid')

local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")
local virtualUser = game:GetService("VirtualUser")
local userInputService = game:GetService("UserInputService")
local players = game:GetService("Players")

local remotes = replicatedStorage:WaitForChild('Remotes')
local gameplay = remotes:WaitForChild('Gameplay')
local coinCollected = gameplay:WaitForChild("CoinCollected")
local roundStart = gameplay:WaitForChild("RoundStart")
local roundEndFade = gameplay:WaitForChild("RoundEndFade")

local farming = false
local totalCollected = 0
local roundCoins = 0
local fullBag = false
local alive = false
local roundStarted = false
local startPosition = humanoidRootPart.CFrame

player.Idled:Connect(function()
	virtualUser:CaptureController()
	virtualUser:ClickButton2(Vector2.new())
end)

task.spawn(function()
	while true do
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.new())
		task.wait(60)
	end
end)

local function setStatus(txt)
	if settings["UI"] ~= true then return end
	pcall(function()
		if settings["UIMode"] == 1 then
			player.PlayerGui:WaitForChild('UI'):WaitForChild('Interface'):WaitForChild('STATUS').Text = txt
		else
			player.PlayerGui:WaitForChild('Lxchu'):WaitForChild('UI'):WaitForChild('Tab01'):WaitForChild('STATUS').Text = txt
		end
	end)
end

local function disablePhysics(stopAnims)
	upperTorso.CanCollide = false
	lowerTorso.CanCollide = false
	humanoidRootPart.CanCollide = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	humanoid.PlatformStand = true
	humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
	humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
	if stopAnims then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop()
			end
			animator.Parent = nil
		end
	end
end

local function restorePhysics()
	upperTorso.CanCollide = true
	lowerTorso.CanCollide = true
	humanoidRootPart.CanCollide = true
	humanoid.PlatformStand = false
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
	humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
end

local function teleportFunction(cframe, duration, ifCoin)
	local cancelled = false
	local currentTween = nil
	local coinCFrame = ifCoin and ifCoin.Parent and ifCoin.CFrame or nil

	local function lockVelocity()
		task.spawn(function()
			while not cancelled do
				local tw = currentTween
				if not tw or tw.PlaybackState ~= Enum.PlaybackState.Playing then break end
				humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
				humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
				task.wait(0.05)
			end
		end)
	end

	local function tweenTo(targetCFrame, dur)
		if cancelled then return false end
		if dur <= 0 then
			humanoidRootPart.CFrame = targetCFrame
			return not cancelled
		end
		currentTween = tweenService:Create(
			humanoidRootPart,
			TweenInfo.new(dur, Enum.EasingStyle.Linear),
			{CFrame = targetCFrame}
		)
		currentTween:Play()
		lockVelocity()
		currentTween.Completed:Wait()
		return not cancelled
	end

	if ifCoin and ifCoin.Parent and ifCoin:FindFirstChild('TouchInterest')
		and (humanoidRootPart.Position - ifCoin.Position).Magnitude < settings["CoinAuraDistance"] then
		setStatus("STATUS: [COIN AURA]: Teleporting Coin to Player...")
		ifCoin.CFrame = humanoidRootPart.CFrame
		return nil
	end

	if settings["Mode"] == "Standing" then
		disablePhysics(true)
		setStatus("STATUS: Going for another coin.")
		local handle = {}

		task.spawn(function()
			if not tweenTo(cframe, duration) then return end
			task.wait(0.1)
			if ifCoin and ifCoin.Parent and ifCoin:FindFirstChild("TouchInterest") then
				ifCoin.CFrame = humanoidRootPart.CFrame
			end
			task.wait(settings["TweenDelay"])
			if not cancelled then
				local animator = humanoid:FindFirstChildOfClass("Animator")
				if not animator then
					local newAnim = Instance.new("Animator")
					newAnim.Parent = humanoid
				end
				restorePhysics()
			end
		end)

		function handle:Cancel()
			cancelled = true
			if currentTween then currentTween:Cancel() end
			if coinCFrame then
				humanoidRootPart.CFrame = coinCFrame + Vector3.new(0, 3, 0)
			end
			restorePhysics()
		end
		return handle
	elseif settings["Mode"] == "Safe" then
		disablePhysics(true)
		setStatus("STATUS: Going for another coin.")

		local OFFSET = -5
		local ROTATE = CFrame.Angles(math.rad(90), 0, 0)
		local startPos = humanoidRootPart.Position
		local targPos = cframe.Position

		local tunnelY = math.min(startPos.Y, targPos.Y) + OFFSET

		local wp1 = CFrame.new(startPos.X, tunnelY, startPos.Z) * ROTATE
		local wp2 = CFrame.new(targPos.X, tunnelY, targPos.Z) * ROTATE
		local wp3 = CFrame.new(targPos.X, tunnelY, targPos.Z) * ROTATE

		local diveTime = 0.15
		local horizDist = (Vector2.new(startPos.X, startPos.Z) - Vector2.new(targPos.X, targPos.Z)).Magnitude
		local horizTime = math.max(horizDist / settings["AutofarmSpeed"], 0.05)
		local riseTime = 0.15

		local handle = {}
		task.spawn(function()
			if not tweenTo(wp1, diveTime) then return end
			if not tweenTo(wp2, horizTime) then return end

			humanoidRootPart.CFrame = wp2 + Vector3.new(0, math.abs(OFFSET), 0) * ROTATE
			if not cancelled then
				humanoidRootPart.CFrame = cframe + Vector3.new(0, -3, 0) * ROTATE
			end
			task.wait(0.05)

			upperTorso.CanCollide = true
			lowerTorso.CanCollide = true
			humanoidRootPart.CanCollide = true
			task.wait(0.1)
			if ifCoin and ifCoin.Parent and ifCoin:FindFirstChild("TouchInterest") then
				humanoidRootPart.CFrame = ifCoin.CFrame
			end
			task.wait(settings["TweenDelay"])
			if not cancelled then
				local animator = humanoid:FindFirstChildOfClass("Animator")
				if not animator then
					local newAnim = Instance.new("Animator")
					newAnim.Parent = humanoid
				end
				restorePhysics()
			end
		end)

		function handle:Cancel()
			cancelled = true
			if currentTween then currentTween:Cancel() end
			if coinCFrame then
				humanoidRootPart.CFrame = coinCFrame + Vector3.new(0, 3, 0)
			end
			restorePhysics()
		end
		return handle
	end
end

local function functionInnocentSheriffHeroMurderer()
	if not (player and player.Character and humanoid and humanoidRootPart) then return end
	if not (roundStarted and fullBag and alive) then return end
	local knife = player.Backpack and player.Backpack:FindFirstChild("Knife")
	local gun = player.Backpack and player.Backpack:FindFirstChild("Gun")
	if knife and settings["KillEveryoneIfDone"] then
		humanoid:EquipTool(knife)
		setStatus("STATUS: Filled Bag! Killing Everyone...")
		for _, other in pairs(players:GetPlayers()) do
			if other ~= player and other.Character then
				local otherHum = other.Character:FindFirstChild("Humanoid")
				if otherHum and otherHum.Health > 0 and other:GetAttribute('AmIAlive', true) then
					local targetHRP = other.Character:FindFirstChild("HumanoidRootPart")
					if targetHRP then
						local savedCFrame = targetHRP.CFrame
						targetHRP.Anchored = true
						targetHRP.CFrame = humanoidRootPart.CFrame + humanoidRootPart.CFrame.LookVector * 1
						if character:FindFirstChild("Knife") then
							character.Knife.Stab:FireServer("Slash")
							targetHRP:SetAttribute('AmIAlive', nil)
						end
						task.wait(0.3)
						targetHRP.Anchored = false
						targetHRP.CFrame = savedCFrame
					end
				end
			end
		end
		return
	end
	if gun and settings["ShootMurdererIfDone"] then
		humanoid:EquipTool(gun)
		setStatus("STATUS: Filled Bag! Shooting Murderer...")
		for _, other in pairs(players:GetPlayers()) do
			if other ~= player and other.Character and other.Backpack and other.Backpack:FindFirstChild("Knife") then
				local targetHRP = other.Character:FindFirstChild("HumanoidRootPart")
				if targetHRP then
					for _ = 1, 3 do
						local predicted = targetHRP.CFrame
						humanoidRootPart.CFrame = predicted * CFrame.new(0, 0, 2)
						if character:FindFirstChild("Gun") then
							character.Gun.KnifeLocal.CreateBeam.RemoteFunction:InvokeServer(1, predicted, "AH2")
						end
						task.wait(0.6)
					end
					humanoidRootPart.CFrame = startPosition
				end
			end
		end
		return
	end
	if settings["ResetIfDone"] then
		if character:FindFirstChild("Humanoid") then
			setStatus("STATUS: Filled Bag! Resetting...")
			humanoidRootPart.CFrame = startPosition
			task.wait(settings["TweenDelay"])
			character.Humanoid.Health = 0
		end
		return
	end
end

local function getNearestCoin()
	local closestCoin, minDistance = nil, math.huge
	for _, model in pairs(workspace:GetChildren()) do
		if model:FindFirstChild("CoinContainer") then
			for _, coin in pairs(model.CoinContainer:GetChildren()) do
				if coin:GetAttribute("CoinID") == settings["CoinType"] and coin:FindFirstChild("TouchInterest") then
					local distance = (humanoidRootPart.Position - coin.Position).Magnitude
					if distance < minDistance then
						closestCoin = coin
						minDistance = distance
					end
				end
			end
		end
	end
	return closestCoin, minDistance
end

local function startFarmingLoop()
	task.spawn(function()
		while true do
			if farming and not fullBag and roundStarted and alive
				and character and humanoidRootPart and humanoidRootPart.Parent then
				local coin, distance = getNearestCoin()
				if coin and coin.Parent then
					if distance > 250 then
						humanoidRootPart.CFrame = coin.CFrame
					else
						local handle = teleportFunction(
							coin.CFrame,
							distance / settings["AutofarmSpeed"],
							coin
						)
						local t0 = os.clock()
						local maxWait = (distance / settings["AutofarmSpeed"]) + 4
						while farming
							and coin.Parent
							and coin:FindFirstChild("TouchInterest")
							and (os.clock() - t0) < maxWait do
							task.wait(0.05)
						end
						if handle and handle.Cancel then
							handle:Cancel()
						end
					end
				end
			end
			task.wait(settings["TweenDelay"])
		end
	end)
end

startFarmingLoop()

local function connectCharacter(newCharacter)
	character = newCharacter
	humanoidRootPart = newCharacter:WaitForChild('HumanoidRootPart')
	humanoid = newCharacter:WaitForChild('Humanoid')
	lowerTorso = newCharacter:WaitForChild('LowerTorso')
	upperTorso = newCharacter:WaitForChild('UpperTorso')
	startPosition = humanoidRootPart.CFrame

	humanoid.Died:Connect(function()
		if roundStarted then
			farming = false
			fullBag = true
			alive = false
		end
	end)
end

player.CharacterAdded:Connect(connectCharacter)

if character and humanoid then
	humanoid.Died:Connect(function()
		if roundStarted then
			farming = false
			fullBag = true
			alive = false
		end
	end)
end

local function detect()
	if settings["FullyOptimizeWhileGrinding"] == true then
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if (descendant:IsA("BasePart") or descendant:IsA("MeshPart")) and not players:GetPlayerFromCharacter(descendant:FindFirstAncestorOfClass("Model")) then
				descendant.Transparency = 1
			end
		end
		workspace.DescendantAdded:Connect(function(descendant)
			if (descendant:IsA("BasePart") or descendant:IsA("MeshPart")) and settings["FullyOptimizeWhileGrinding"] == true and not players:GetPlayerFromCharacter(descendant:FindFirstAncestorOfClass("Model")) then
				descendant.Transparency = 1
			end
		end)
	else
		for _, descendant in ipairs(workspace:GetDescendants()) do
			if (descendant:IsA("BasePart") or descendant:IsA("MeshPart")) and not players:GetPlayerFromCharacter(descendant:FindFirstAncestorOfClass("Model")) then
				descendant.Transparency = 0
			end
		end
	end
end

coinCollected.OnClientEvent:Connect(function(coinType, current, max)
	totalCollected += 1
	roundCoins += 1
	if settings["UI"] == true then
		if settings["UIMode"] == 1 then
			pcall(function()
				player.PlayerGui:WaitForChild('UI'):WaitForChild('Interface'):WaitForChild('TOTALCOIN').Text = "TOTAL COIN COLLECTED: " .. totalCollected
				player.PlayerGui:WaitForChild('UI'):WaitForChild('Interface'):WaitForChild('STATUS').Text = "STATUS: Collected Coin! Current Collected: " .. roundCoins .. "/" .. max
			end)
		elseif settings["UIMode"] == 2 then
			pcall(function()
				player.PlayerGui:WaitForChild('Lxchu'):WaitForChild('UI'):WaitForChild('Tab01'):WaitForChild('STATUS').Text = "STATUS: Collected Coin! Current Collected: " .. roundCoins .. "/" .. max
			end)
		end
	end
	if coinType == settings["CoinType"] then
		if current == max then
			fullBag = true
			if settings["ResetIfDone"] or settings["ShootMurdererIfDone"] or settings["KillEveryoneIfDone"] then
				functionInnocentSheriffHeroMurderer()
			else
				setStatus("STATUS: Waiting for round to end... Coins Collected: " .. roundCoins .. "/" .. max)
			end
		end
	end
end)

roundStart.OnClientEvent:Connect(function()
	detect()
	if not roundStarted then
		roundCoins = 0
		roundStarted = true
		farming = true
		alive = true
		for _, other in pairs(players:GetPlayers()) do
			if other ~= player then
				other:SetAttribute('AmIAlive', true)
			end
		end
	end
end)

roundEndFade.OnClientEvent:Connect(function()
	detect()
	if roundStarted then
		setStatus("STATUS: Waiting for round to start.")
		roundCoins = 0
		roundStarted = false
		farming = false
		alive = false
		if fullBag then
			fullBag = false
		end
		for _, other in pairs(players:GetPlayers()) do
			if other ~= player then
				other:SetAttribute('AmIAlive', nil)
			end
		end
	end
end)

if settings["UI"] == true then
	if settings["UIMode"] == 1 then
		local UI = Instance.new("ScreenGui")
		local Interface = Instance.new("Frame")
		local Title = Instance.new("TextLabel")
		local STATUS = Instance.new("TextLabel")
		local TOTALCOIN = Instance.new("TextLabel")
		UI.Name = "UI"
		UI.Parent = player:WaitForChild("PlayerGui")
		UI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		UI.Enabled = false
		UI.ResetOnSpawn = false
		UI.IgnoreGuiInset = true

		Interface.Name = "Interface"
		Interface.Parent = UI
		Interface.AnchorPoint = Vector2.new(0.5, 0.5)
		Interface.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		Interface.BorderColor3 = Color3.fromRGB(0, 0, 0)
		Interface.BorderSizePixel = 0
		Interface.Position = UDim2.new(0.5, 0, 0.5, 0)
		Interface.Size = UDim2.new(1, 0, 1, 0)

		Title.Name = "Title"
		Title.Parent = Interface
		Title.AnchorPoint = Vector2.new(0.5, 0.5)
		Title.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		Title.BackgroundTransparency = 1.000
		Title.BorderColor3 = Color3.fromRGB(0, 0, 0)
		Title.BorderSizePixel = 0
		Title.Position = UDim2.new(0.5, 0, 0.0500000007, 0)
		Title.Size = UDim2.new(1, 0, 0, 50)
		Title.Font = Enum.Font.SourceSansBold
		Title.Text = "AUTOFARM SCRIPTED BY ! Lxchu [MODIFY SETTINGS IN SCRIPT]"
		Title.TextColor3 = Color3.fromRGB(255, 255, 255)
		Title.TextScaled = true
		Title.TextSize = 14.000
		Title.TextStrokeTransparency = 0.900
		Title.TextWrapped = true

		STATUS.Name = "STATUS"
		STATUS.Parent = Interface
		STATUS.AnchorPoint = Vector2.new(0.5, 0.5)
		STATUS.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		STATUS.BackgroundTransparency = 1.000
		STATUS.BorderColor3 = Color3.fromRGB(0, 0, 0)
		STATUS.BorderSizePixel = 0
		STATUS.Position = UDim2.new(0.5, 0, 0.5, 0)
		STATUS.Size = UDim2.new(1, 0, 0, 50)
		STATUS.Font = Enum.Font.SourceSansBold
		STATUS.Text = "STATUS: NIL"
		STATUS.TextColor3 = Color3.fromRGB(255, 255, 255)
		STATUS.TextScaled = true
		STATUS.TextSize = 14.000
		STATUS.TextStrokeTransparency = 0.900
		STATUS.TextWrapped = true

		TOTALCOIN.Name = "TOTALCOIN"
		TOTALCOIN.Parent = Interface
		TOTALCOIN.AnchorPoint = Vector2.new(0.5, 0.5)
		TOTALCOIN.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		TOTALCOIN.BackgroundTransparency = 1.000
		TOTALCOIN.BorderColor3 = Color3.fromRGB(0, 0, 0)
		TOTALCOIN.BorderSizePixel = 0
		TOTALCOIN.Position = UDim2.new(0.5, 0, 0.349999994, 0)
		TOTALCOIN.Size = UDim2.new(0, 500, 0, 50)
		TOTALCOIN.Font = Enum.Font.SourceSansBold
		TOTALCOIN.Text = "TOTAL COIN COLLECTED: NIL"
		TOTALCOIN.TextColor3 = Color3.fromRGB(255, 255, 255)
		TOTALCOIN.TextScaled = true
		TOTALCOIN.TextSize = 14.000
		TOTALCOIN.TextStrokeTransparency = 0.900
		TOTALCOIN.TextWrapped = true
		player.PlayerGui:WaitForChild('UI').Enabled = true
	elseif settings["UIMode"] == 2 then
		local Lxchu = Instance.new("ScreenGui")
		Lxchu.ResetOnSpawn = false
		local UI = Instance.new("Frame")
		local UICorner = Instance.new("UICorner")
		local Title = Instance.new("TextLabel")
		local Tab01 = Instance.new("Frame")
		local UICorner_2 = Instance.new("UICorner")
		local SPEED = Instance.new("TextBox")
		local UICorner_3 = Instance.new("UICorner")
		local SAFE = Instance.new("TextButton")
		local UICorner_4 = Instance.new("UICorner")
		local STANDING = Instance.new("TextButton")
		local UICorner_5 = Instance.new("UICorner")
		local DELAY = Instance.new("TextBox")
		local UICorner_6 = Instance.new("UICorner")
		local CAURADISTANCE = Instance.new("TextBox")
		local UICorner_7 = Instance.new("UICorner")
		local COINTYPE = Instance.new("TextBox")
		local UICorner_8 = Instance.new("UICorner")
		local KILL = Instance.new("TextButton")
		local UICorner_9 = Instance.new("UICorner")
		local RESET = Instance.new("TextButton")
		local UICorner_10 = Instance.new("UICorner")
		local SHOOT = Instance.new("TextButton")
		local UICorner_11 = Instance.new("UICorner")
		local OPTIMIZE = Instance.new("TextButton")
		local UICorner_12 = Instance.new("UICorner")
		local STATUS = Instance.new("TextLabel")
		Lxchu.Name = "Lxchu"
		Lxchu.Parent = game.Players.LocalPlayer:WaitForChild("PlayerGui")
		Lxchu.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		UI.Name = "UI"
		UI.Parent = Lxchu
		UI.AnchorPoint = Vector2.new(0.5, 0.5)
		UI.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		UI.BorderColor3 = Color3.fromRGB(0, 0, 0)
		UI.BorderSizePixel = 0
		UI.Position = UDim2.new(0.5, 0, 0.5, 0)
		if userInputService.TouchEnabled == false then
			UI.Size = UDim2.new(0, 500, 0, 300)
		else
			UI.Size = UDim2.new(0, 150, 0, 100)
		end
		UICorner.CornerRadius = UDim.new(0, 10)
		UICorner.Parent = UI
		Title.Name = "Title"
		Title.Parent = UI
		Title.AnchorPoint = Vector2.new(0.5, 0.5)
		Title.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		Title.BackgroundTransparency = 1.000
		Title.BorderColor3 = Color3.fromRGB(0, 0, 0)
		Title.BorderSizePixel = 0
		Title.Position = UDim2.new(0.5, 0, 0.0399999991, 0)
		Title.Size = UDim2.new(1, 0, 0, 25)
		Title.Font = Enum.Font.SourceSansBold
		Title.Text = "AUTOFARM SCRIPTED BY ! Lxchu"
		Title.TextColor3 = Color3.fromRGB(255, 255, 255)
		Title.TextScaled = true
		Title.TextSize = 14.000
		Title.TextStrokeTransparency = 0.900
		Title.TextWrapped = true
		Tab01.Name = "Tab01"
		Tab01.Parent = UI
		Tab01.AnchorPoint = Vector2.new(0.5, 0.5)
		Tab01.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		Tab01.BorderColor3 = Color3.fromRGB(0, 0, 0)
		Tab01.BorderSizePixel = 0
		Tab01.Position = UDim2.new(0.5, 0, 0.540000021, 0)
		Tab01.Size = UDim2.new(0, 500, 0, 276)
		UICorner_2.CornerRadius = UDim.new(0, 10)
		UICorner_2.Parent = Tab01
		SPEED.Name = "SPEED"
		SPEED.Parent = Tab01
		SPEED.AnchorPoint = Vector2.new(0.5, 0.5)
		SPEED.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		SPEED.BorderColor3 = Color3.fromRGB(0, 0, 0)
		SPEED.BorderSizePixel = 0
		SPEED.Position = UDim2.new(0.5, 0, 0.25, 0)
		SPEED.Size = UDim2.new(0, 350, 0, 25)
		SPEED.Font = Enum.Font.SourceSansBold
		SPEED.PlaceholderColor3 = Color3.fromRGB(255, 255, 255)
		SPEED.PlaceholderText = "AUTOFARM SPEED"
		SPEED.Text = "25"
		SPEED.TextColor3 = Color3.fromRGB(255, 255, 255)
		SPEED.TextScaled = true
		SPEED.TextSize = 14.000
		SPEED.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		SPEED.TextStrokeTransparency = 0.900
		SPEED.TextWrapped = true
		UICorner_3.CornerRadius = UDim.new(0, 10)
		UICorner_3.Parent = SPEED
		SAFE.Name = "SAFE"
		SAFE.Parent = Tab01
		SAFE.AnchorPoint = Vector2.new(0.5, 0.5)
		SAFE.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		SAFE.BorderColor3 = Color3.fromRGB(0, 0, 0)
		SAFE.BorderSizePixel = 0
		SAFE.Position = UDim2.new(0.230000004, 0, 0.0900000036, 0)
		SAFE.Size = UDim2.new(0, 75, 0, 50)
		SAFE.AutoButtonColor = false
		SAFE.Font = Enum.Font.SourceSansBold
		SAFE.Text = "SAFE"
		SAFE.TextColor3 = Color3.fromRGB(255, 255, 255)
		SAFE.TextScaled = true
		SAFE.TextSize = 14.000
		SAFE.TextStrokeTransparency = 0.900
		SAFE.TextWrapped = true
		UICorner_4.CornerRadius = UDim.new(0, 10)
		UICorner_4.Parent = SAFE
		STANDING.Name = "STANDING"
		STANDING.Parent = Tab01
		STANDING.AnchorPoint = Vector2.new(0.5, 0.5)
		STANDING.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		STANDING.BorderColor3 = Color3.fromRGB(0, 0, 0)
		STANDING.BorderSizePixel = 0
		STANDING.Position = UDim2.new(0.769999981, 0, 0.0900000036, 0)
		STANDING.Size = UDim2.new(0, 75, 0, 50)
		STANDING.AutoButtonColor = false
		STANDING.Font = Enum.Font.SourceSansBold
		STANDING.Text = "STANDING"
		STANDING.TextColor3 = Color3.fromRGB(255, 255, 255)
		STANDING.TextScaled = true
		STANDING.TextSize = 14.000
		STANDING.TextStrokeTransparency = 0.900
		STANDING.TextWrapped = true
		UICorner_5.CornerRadius = UDim.new(0, 10)
		UICorner_5.Parent = STANDING
		DELAY.Name = "DELAY"
		DELAY.Parent = Tab01
		DELAY.AnchorPoint = Vector2.new(0.5, 0.5)
		DELAY.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		DELAY.BorderColor3 = Color3.fromRGB(0, 0, 0)
		DELAY.BorderSizePixel = 0
		DELAY.Position = UDim2.new(0.5, 0, 0.349999994, 0)
		DELAY.Size = UDim2.new(0, 350, 0, 25)
		DELAY.Font = Enum.Font.SourceSansBold
		DELAY.PlaceholderColor3 = Color3.fromRGB(255, 255, 255)
		DELAY.PlaceholderText = "TWEEN DELAY"
		DELAY.Text = "0.15"
		DELAY.TextColor3 = Color3.fromRGB(255, 255, 255)
		DELAY.TextScaled = true
		DELAY.TextSize = 14.000
		DELAY.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		DELAY.TextStrokeTransparency = 0.900
		DELAY.TextWrapped = true
		UICorner_6.CornerRadius = UDim.new(0, 10)
		UICorner_6.Parent = DELAY
		CAURADISTANCE.Name = "CAURADISTANCE"
		CAURADISTANCE.Parent = Tab01
		CAURADISTANCE.AnchorPoint = Vector2.new(0.5, 0.5)
		CAURADISTANCE.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		CAURADISTANCE.BorderColor3 = Color3.fromRGB(0, 0, 0)
		CAURADISTANCE.BorderSizePixel = 0
		CAURADISTANCE.Position = UDim2.new(0.5, 0, 0.449999988, 0)
		CAURADISTANCE.Size = UDim2.new(0, 350, 0, 25)
		CAURADISTANCE.Font = Enum.Font.SourceSansBold
		CAURADISTANCE.PlaceholderColor3 = Color3.fromRGB(255, 255, 255)
		CAURADISTANCE.PlaceholderText = "COIN AURA DISTANCE"
		CAURADISTANCE.Text = "5"
		CAURADISTANCE.TextColor3 = Color3.fromRGB(255, 255, 255)
		CAURADISTANCE.TextScaled = true
		CAURADISTANCE.TextSize = 14.000
		CAURADISTANCE.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		CAURADISTANCE.TextStrokeTransparency = 0.900
		CAURADISTANCE.TextWrapped = true
		UICorner_7.CornerRadius = UDim.new(0, 10)
		UICorner_7.Parent = CAURADISTANCE
		COINTYPE.Name = "COINTYPE"
		COINTYPE.Parent = Tab01
		COINTYPE.AnchorPoint = Vector2.new(0.5, 0.5)
		COINTYPE.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		COINTYPE.BorderColor3 = Color3.fromRGB(0, 0, 0)
		COINTYPE.BorderSizePixel = 0
		COINTYPE.Position = UDim2.new(0.5, 0, 0.550000012, 0)
		COINTYPE.Size = UDim2.new(0, 350, 0, 25)
		COINTYPE.Font = Enum.Font.SourceSansBold
		COINTYPE.PlaceholderColor3 = Color3.fromRGB(255, 255, 255)
		COINTYPE.PlaceholderText = "COIN TYPE"
		COINTYPE.Text = "Candy"
		COINTYPE.TextColor3 = Color3.fromRGB(255, 255, 255)
		COINTYPE.TextScaled = true
		COINTYPE.TextSize = 14.000
		COINTYPE.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		COINTYPE.TextStrokeTransparency = 0.900
		COINTYPE.TextWrapped = true
		UICorner_8.CornerRadius = UDim.new(0, 10)
		UICorner_8.Parent = COINTYPE
		KILL.Name = "KILL"
		KILL.Parent = Tab01
		KILL.AnchorPoint = Vector2.new(0.5, 0.5)
		KILL.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		KILL.BorderColor3 = Color3.fromRGB(0, 0, 0)
		KILL.BorderSizePixel = 0
		KILL.Position = UDim2.new(0.769999981, 0, 0.699999988, 0)
		KILL.Size = UDim2.new(0, 75, 0, 50)
		KILL.AutoButtonColor = false
		KILL.Font = Enum.Font.SourceSansBold
		KILL.Text = "KILL ALL WHEN DONE"
		KILL.TextColor3 = Color3.fromRGB(255, 255, 255)
		KILL.TextScaled = true
		KILL.TextSize = 14.000
		KILL.TextStrokeTransparency = 0.900
		KILL.TextWrapped = true
		UICorner_9.CornerRadius = UDim.new(0, 10)
		UICorner_9.Parent = KILL
		RESET.Name = "RESET"
		RESET.Parent = Tab01
		RESET.AnchorPoint = Vector2.new(0.5, 0.5)
		RESET.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		RESET.BorderColor3 = Color3.fromRGB(0, 0, 0)
		RESET.BorderSizePixel = 0
		RESET.Position = UDim2.new(0.230000004, 0, 0.699999988, 0)
		RESET.Size = UDim2.new(0, 75, 0, 50)
		RESET.AutoButtonColor = false
		RESET.Font = Enum.Font.SourceSansBold
		RESET.Text = "RESET ON DONE"
		RESET.TextColor3 = Color3.fromRGB(255, 255, 255)
		RESET.TextScaled = true
		RESET.TextSize = 14.000
		RESET.TextStrokeTransparency = 0.900
		RESET.TextWrapped = true
		UICorner_10.CornerRadius = UDim.new(0, 10)
		UICorner_10.Parent = RESET
		SHOOT.Name = "SHOOT"
		SHOOT.Parent = Tab01
		SHOOT.AnchorPoint = Vector2.new(0.5, 0.5)
		SHOOT.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		SHOOT.BorderColor3 = Color3.fromRGB(0, 0, 0)
		SHOOT.BorderSizePixel = 0
		SHOOT.Position = UDim2.new(0.5, 0, 0.699999988, 0)
		SHOOT.Size = UDim2.new(0, 75, 0, 50)
		SHOOT.AutoButtonColor = false
		SHOOT.Font = Enum.Font.SourceSansBold
		SHOOT.Text = "SHOOT ON DONE"
		SHOOT.TextColor3 = Color3.fromRGB(255, 255, 255)
		SHOOT.TextScaled = true
		SHOOT.TextSize = 14.000
		SHOOT.TextStrokeTransparency = 0.900
		SHOOT.TextWrapped = true
		UICorner_11.CornerRadius = UDim.new(0, 10)
		UICorner_11.Parent = SHOOT
		OPTIMIZE.Name = "OPTIMIZE"
		OPTIMIZE.Parent = Tab01
		OPTIMIZE.AnchorPoint = Vector2.new(0.5, 0.5)
		OPTIMIZE.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		OPTIMIZE.BorderColor3 = Color3.fromRGB(0, 0, 0)
		OPTIMIZE.BorderSizePixel = 0
		OPTIMIZE.Position = UDim2.new(0.5, 0, 0.850000024, 0)
		OPTIMIZE.Size = UDim2.new(0, 350, 0, 25)
		OPTIMIZE.AutoButtonColor = false
		OPTIMIZE.Font = Enum.Font.SourceSansBold
		OPTIMIZE.Text = "FULLY OPTIMIZED GAME"
		OPTIMIZE.TextColor3 = Color3.fromRGB(255, 255, 255)
		OPTIMIZE.TextScaled = true
		OPTIMIZE.TextSize = 14.000
		OPTIMIZE.TextStrokeTransparency = 0.900
		OPTIMIZE.TextWrapped = true
		UICorner_12.CornerRadius = UDim.new(0, 10)
		UICorner_12.Parent = OPTIMIZE
		STATUS.Name = "STATUS"
		STATUS.Parent = Tab01
		STATUS.AnchorPoint = Vector2.new(0.5, 0.5)
		STATUS.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		STATUS.BackgroundTransparency = 1.000
		STATUS.BorderColor3 = Color3.fromRGB(0, 0, 0)
		STATUS.BorderSizePixel = 0
		STATUS.Position = UDim2.new(0.5, 0, 0.949999988, 0)
		STATUS.Size = UDim2.new(1, 0, 0, 25)
		STATUS.Font = Enum.Font.SourceSansBold
		STATUS.Text = "STATUS: NIL"
		STATUS.TextColor3 = Color3.fromRGB(255, 255, 255)
		STATUS.TextScaled = true
		STATUS.TextSize = 14.000
		STATUS.TextStrokeTransparency = 0.900
		STATUS.TextWrapped = true

		if settings["AutofarmSpeed"] then
			SPEED.Text = tostring(settings["AutofarmSpeed"])
		end
		SPEED.MouseEnter:Connect(function()
			tweenService:Create(SPEED, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		SPEED.MouseLeave:Connect(function()
			tweenService:Create(SPEED, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		SPEED.FocusLost:Connect(function()
			local value = tonumber(SPEED.Text)
			if value then
				settings["AutofarmSpeed"] = value
			end
		end)
		local uStroke = Instance.new('UIStroke', SAFE)
		uStroke.Thickness = 1.5
		uStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		if settings["Mode"] == "Safe" then
			tweenService:Create(SAFE.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
		else
			tweenService:Create(SAFE.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
		end
		SAFE.MouseEnter:Connect(function()
			tweenService:Create(SAFE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		SAFE.MouseLeave:Connect(function()
			tweenService:Create(SAFE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		SAFE.MouseButton1Click:Connect(function()
			settings["Mode"] = "Safe"
			tweenService:Create(SAFE.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
			tweenService:Create(STANDING.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
		end)
		local uStroke2 = Instance.new('UIStroke', STANDING)
		uStroke2.Thickness = 1.5
		uStroke2.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		if settings["Mode"] == "Standing" then
			tweenService:Create(STANDING.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
		else
			tweenService:Create(STANDING.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
		end
		STANDING.MouseEnter:Connect(function()
			tweenService:Create(STANDING, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		STANDING.MouseLeave:Connect(function()
			tweenService:Create(STANDING, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		STANDING.MouseButton1Click:Connect(function()
			settings["Mode"] = "Standing"
			tweenService:Create(STANDING.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
			tweenService:Create(SAFE.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
		end)
		if settings["TweenDelay"] then
			DELAY.Text = tostring(settings["TweenDelay"])
		end
		DELAY.MouseEnter:Connect(function()
			tweenService:Create(DELAY, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		DELAY.MouseLeave:Connect(function()
			tweenService:Create(DELAY, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		DELAY.FocusLost:Connect(function()
			local value = tonumber(DELAY.Text)
			if value then
				settings["TweenDelay"] = value
			end
		end)
		if settings["CoinAuraDistance"] then
			CAURADISTANCE.Text = tostring(settings["CoinAuraDistance"])
		end
		CAURADISTANCE.MouseEnter:Connect(function()
			tweenService:Create(CAURADISTANCE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		CAURADISTANCE.MouseLeave:Connect(function()
			tweenService:Create(CAURADISTANCE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		CAURADISTANCE.FocusLost:Connect(function()
			local value = tonumber(CAURADISTANCE.Text)
			if value then
				settings["CoinAuraDistance"] = value
			end
		end)
		if settings["CoinType"] then
			COINTYPE.Text = settings["CoinType"]
		end
		COINTYPE.MouseEnter:Connect(function()
			tweenService:Create(COINTYPE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		COINTYPE.MouseLeave:Connect(function()
			tweenService:Create(COINTYPE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		COINTYPE.FocusLost:Connect(function()
			local value = tostring(COINTYPE.Text)
			if value then
				settings["CoinType"] = value
			end
		end)
		local uStroke3 = Instance.new('UIStroke', KILL)
		uStroke3.Thickness = 1.5
		uStroke3.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local killVal = false
		if settings["KillEveryoneIfDone"] == true then
			killVal = true
			tweenService:Create(KILL.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
		else
			killVal = false
			tweenService:Create(KILL.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
		end
		KILL.MouseEnter:Connect(function()
			tweenService:Create(KILL, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		KILL.MouseLeave:Connect(function()
			tweenService:Create(KILL, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		KILL.MouseButton1Click:Connect(function()
			if killVal == false then
				killVal = true
				settings["KillEveryoneIfDone"] = true
				tweenService:Create(KILL.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
			else
				killVal = false
				settings["KillEveryoneIfDone"] = false
				tweenService:Create(KILL.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
			end
		end)
		local uStroke4 = Instance.new('UIStroke', RESET)
		uStroke4.Thickness = 1.5
		uStroke4.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local resetVal = false
		if settings["ResetIfDone"] == true then
			resetVal = true
			tweenService:Create(RESET.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
		else
			resetVal = false
			tweenService:Create(RESET.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
		end
		RESET.MouseEnter:Connect(function()
			tweenService:Create(RESET, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		RESET.MouseLeave:Connect(function()
			tweenService:Create(RESET, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		RESET.MouseButton1Click:Connect(function()
			if resetVal == false then
				resetVal = true
				settings["ResetIfDone"] = true
				tweenService:Create(RESET.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
			else
				resetVal = false
				settings["ResetIfDone"] = false
				tweenService:Create(RESET.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
			end
		end)
		local uStroke5 = Instance.new('UIStroke', SHOOT)
		uStroke5.Thickness = 1.5
		uStroke5.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local shootVal = false
		if settings["ShootMurdererIfDone"] == true then
			shootVal = true
			tweenService:Create(SHOOT.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
		else
			shootVal = false
			tweenService:Create(SHOOT.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
		end
		SHOOT.MouseEnter:Connect(function()
			tweenService:Create(SHOOT, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		SHOOT.MouseLeave:Connect(function()
			tweenService:Create(SHOOT, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		SHOOT.MouseButton1Click:Connect(function()
			if shootVal == false then
				shootVal = true
				settings["ShootMurdererIfDone"] = true
				tweenService:Create(SHOOT.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
			else
				shootVal = false
				settings["ShootMurdererIfDone"] = false
				tweenService:Create(SHOOT.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
			end
		end)
		local uStroke6 = Instance.new('UIStroke', OPTIMIZE)
		uStroke6.Thickness = 1.5
		uStroke6.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local optVal = false
		if settings["FullyOptimizeWhileGrinding"] == true then
			optVal = true
			tweenService:Create(OPTIMIZE.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
		else
			optVal = false
			tweenService:Create(OPTIMIZE.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
		end
		OPTIMIZE.MouseEnter:Connect(function()
			tweenService:Create(OPTIMIZE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		OPTIMIZE.MouseLeave:Connect(function()
			tweenService:Create(OPTIMIZE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		OPTIMIZE.MouseButton1Click:Connect(function()
			if optVal == false then
				optVal = true
				settings["FullyOptimizeWhileGrinding"] = true
				tweenService:Create(OPTIMIZE.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(75, 170, 0)}):Play()
			else
				optVal = false
				settings["FullyOptimizeWhileGrinding"] = false
				tweenService:Create(OPTIMIZE.UIStroke, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {Color = Color3.fromRGB(170, 0, 0)}):Play()
			end
		end)
		UI.Draggable = true
		UI.Active = true
		UI.Selectable = true
	end
end