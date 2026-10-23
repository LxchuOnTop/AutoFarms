-- Scripted by TokyoMemoriess

local SETTINGS_FILE = "TokyoFarm_Settings.json"
getgenv().TokyoFarmSourceURL = 'https://raw.githubusercontent.com/TokyoMemoriess/AutoFarms/refs/heads/main/AutofarmMM2.lua'

local settings = {
	["Mode"] = "Safe",
	["AutofarmSpeed"] = 27.5,
	["TweenDelay"] = 0.09,
	["SafeModeOffset"] = 4,
	["CoinAuraDistance"] = 6,
	["CoinType"] = "Candy",
	["ResetIfDone"] = true,
	["ShootMurdererIfDone"] = false,
	["KillEveryoneIfDone"] = false,
	["UI"] = true,
	["UIMode"] = 3,
	["FullyOptimizeWhileGrinding"] = false,
	["ServerHopEnabled"] = true,
	["MaxHopAttempts"] = 10,
	["MinPlayerCount"] = 4,
	["HopCheckInterval"] = 3,
	["HopGracePeriod"] = 12,
	["HopLowCountDuration"] = 15,
	["HopMidRound"] = false,
	["ExploiterHopEnabled"] = false,
	["MinExploitersToHop"] = 1,
	["ExploiterViolationThreshold"] = 6,
	["ExploiterFlagCooldown"] = 30,
	["ExploiterMinMoveDistance"] = 1.5,
	["ExploiterSampleRate"] = 0.1,
	["HopStateFile"] = "TokyoFarm_HopState.json",
}

local players = game:GetService("Players")

local tracked = {}
local flingPlayerData = {}
local exploiterTrackers = {}
local flaggedExploiters = {}

local function enforce(part)
    if part.CanCollide then
        part.CanCollide = false
    end
end

local function hookPart(char, part)
    if not part:IsA("BasePart") then return end
    local data = tracked[char]
    if not data then return end

    data.parts[part] = true
    enforce(part)

    part:GetPropertyChangedSignal("CanCollide"):Connect(function()
        if tracked[char] and part.CanCollide then
            part.CanCollide = false
        end
    end)
end

local function trackCharacter(char)
    if tracked[char] then return end
    tracked[char] = { parts = {} }

    for _, d in ipairs(char:GetDescendants()) do
        hookPart(char, d)
    end

    char.DescendantAdded:Connect(function(d)
        if tracked[char] then
            hookPart(char, d)
        end
    end)

    char.DescendantRemoving:Connect(function(d)
        local data = tracked[char]
        if data then
            data.parts[d] = nil
        end
    end)

    char.Destroying:Connect(function()
        tracked[char] = nil
    end)
end

local function onPlayer(p)
    if p == players.LocalPlayer then return end
    if p.Character then
        trackCharacter(p.Character)
    end
    p.CharacterAdded:Connect(trackCharacter)
end

for _, p in ipairs(players:GetPlayers()) do
    onPlayer(p)
end

players.PlayerAdded:Connect(onPlayer)

game:GetService('RunService').Stepped:Connect(function()
    for char, data in pairs(tracked) do
        if not char.Parent then
            tracked[char] = nil
            continue
        end
        for part in pairs(data.parts) do
            if not part.Parent then
                data.parts[part] = nil
            elseif part.CanCollide then
                part.CanCollide = false
            end
        end
    end
end)

local player = players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoidRootPart = character:WaitForChild('HumanoidRootPart')
local lowerTorso = character:WaitForChild('LowerTorso')
local upperTorso = character:WaitForChild('UpperTorso')
local humanoid = character:WaitForChild('Humanoid')

local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService('RunService')
local tweenService = game:GetService("TweenService")
local virtualUser = game:GetService("VirtualUser")
local userInputService = game:GetService("UserInputService")
local httpService = game:GetService("HttpService")

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
local currentFarmHandle = nil
local savedAnimations = nil
local flingActive = false
local physicsSettled = false
local physicsDisabled = false
local floatForce = nil
local fixedRotation = nil

if isfile and isfile(SETTINGS_FILE) then
	pcall(function()
		local saved = httpService:JSONDecode(readfile(SETTINGS_FILE))
		for k, v in pairs(saved) do
			if settings[k] ~= nil then
				settings[k] = v
			end
		end
	end)
end

local function saveSettings()
	if writefile then
		pcall(function()
			writefile(SETTINGS_FILE, httpService:JSONEncode(settings))
		end)
	end
end

local function computeSafeTargetY(coinPart, desiredY, allowUnderground)
    if not coinPart or not coinPart.Parent then return desiredY end

    if allowUnderground then
        return desiredY
    end

    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = {character, coinPart}
    local origin = Vector3.new(coinPart.Position.X, coinPart.Position.Y + 0.1, coinPart.Position.Z)
    local distance = origin.Y - desiredY + 2
    if distance <= 0 then return desiredY end
    local result = workspace:Raycast(origin, Vector3.new(0, -distance, 0), rp)
    if result then
        return math.max(desiredY, result.Position.Y + 3)
    end
    return desiredY
end

local function enableAnimate()
    if character then
        local a = character:FindFirstChild("Animate")
        if a then a.Enabled = true end
    end
end

local coinBlacklist   = setmetatable({}, {__mode = "k"})
local coinArrivalTime = setmetatable({}, {__mode = "k"})
local coinAttemptStart = setmetatable({}, {__mode = "k"})

local cachedStatusLabel = nil
local cachedTotalCoinLabel = nil

local function getStatusLabel()
	if cachedStatusLabel and cachedStatusLabel.Parent then
		return cachedStatusLabel
	end
	cachedStatusLabel = nil
	local root = player.PlayerGui
	if settings["UIMode"] == 1 then
		root = root:FindFirstChild('UI')
		if root then root = root:FindFirstChild('Interface') end
	elseif settings["UIMode"] == 3 then
		root = root:FindFirstChild('TokyoUI')
		if root then root = root:FindFirstChild('UI') end
	else
		root = root:FindFirstChild('Lxchu')
		if root then root = root:FindFirstChild('UI') end
		if root then root = root:FindFirstChild('Tab01') end
	end
	if root then
		cachedStatusLabel = root:FindFirstChild('STATUS')
	end
	return cachedStatusLabel
end

local function getTotalCoinLabel()
	if cachedTotalCoinLabel and cachedTotalCoinLabel.Parent then
		return cachedTotalCoinLabel
	end
	cachedTotalCoinLabel = nil
	local ui = player.PlayerGui:FindFirstChild('UI')
	if ui then
		local iface = ui:FindFirstChild('Interface')
		if iface then
			cachedTotalCoinLabel = iface:FindFirstChild('TOTALCOIN')
		end
	end
	return cachedTotalCoinLabel
end

local function setStatus(txt)
	if settings["UI"] ~= true then return end
	local label = getStatusLabel()
	if label then
		label.Text = txt
	end
end

local cachedCoinContainers = nil

local function rebuildCoinContainerCache()
	local list = {}
	for _, model in ipairs(workspace:GetChildren()) do
		local cc = model:FindFirstChild("CoinContainer")
		if cc then
			list[#list + 1] = cc
		end
	end
	cachedCoinContainers = list
end

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

local function OdhSkid(TargetPlayer, duration)
	local startTime = tick()
	local Character = player.Character
	local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
	local RootPart = Humanoid and Humanoid.RootPart

	local TCharacter = TargetPlayer.Character
	local THumanoid
	local TRootPart
	local THead
	local Accessory
	local Handle

	if TCharacter:FindFirstChildOfClass("Humanoid") then
		THumanoid = TCharacter:FindFirstChildOfClass("Humanoid")
	end
	if THumanoid and THumanoid.RootPart then
		TRootPart = THumanoid.RootPart
	end
	if TCharacter:FindFirstChild("Head") then
		THead = TCharacter.Head
	end
	if TCharacter:FindFirstChildOfClass("Accessory") then
		Accessory = TCharacter:FindFirstChildOfClass("Accessory")
	end
	if Accessory and Accessory:FindFirstChild("Handle") then
		Handle = Accessory.Handle
	end

	local OldPos

	if Character and Humanoid and RootPart then
		if RootPart.Velocity.Magnitude < 50 then
			getgenv().OldPos = RootPart.CFrame
		end
		if THead then
			workspace.CurrentCamera.CameraSubject = THead
		elseif not THead and Handle then
			workspace.CurrentCamera.CameraSubject = Handle
		elseif THumanoid and TRootPart then
			workspace.CurrentCamera.CameraSubject = THumanoid
		end
		if not TCharacter:FindFirstChildWhichIsA("BasePart") then
			return
		end

		for _, part in ipairs(TCharacter:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = true
			end
		end

		local FPos = function(BasePart, Pos, Ang)
			RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
			Character:SetPrimaryPartCFrame(CFrame.new(BasePart.Position) * Pos * Ang)
			RootPart.Velocity = Vector3.new(9e7, 9e7 * 10, 9e7)
			RootPart.RotVelocity = Vector3.new(9e8, 9e8, 9e8)
		end

		local SFBasePart = function(BasePart)
			local TimeToWait = duration or 2
			local Time = tick()
			local Angle = 0

			repeat
				if RootPart and THumanoid then
					if BasePart.Velocity.Magnitude < 50 then
						Angle = Angle + 100

						FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle),0 ,0))
						task.wait()

						FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(2.25, 1.5, -2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(-2.25, -1.5, 2.25) + THumanoid.MoveDirection * BasePart.Velocity.Magnitude / 1.25, CFrame.Angles(math.rad(Angle), 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, 1.5, 0) + THumanoid.MoveDirection,CFrame.Angles(math.rad(Angle), 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, -1.5, 0) + THumanoid.MoveDirection,CFrame.Angles(math.rad(Angle), 0, 0))
						task.wait()
					else
						FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, -1.5, -THumanoid.WalkSpeed), CFrame.Angles(0, 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, 1.5, THumanoid.WalkSpeed), CFrame.Angles(math.rad(90), 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, 1.5, TRootPart.Velocity.Magnitude / 1.25), CFrame.Angles(math.rad(90), 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, -1.5, -TRootPart.Velocity.Magnitude / 1.25), CFrame.Angles(0, 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, 1.5, TRootPart.Velocity.Magnitude / 1.25), CFrame.Angles(math.rad(90), 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(math.rad(90), 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, -1.5 ,0), CFrame.Angles(math.rad(-90), 0, 0))
						task.wait()

						FPos(BasePart, CFrame.new(0, -1.5, 0), CFrame.Angles(0, 0, 0))
						task.wait()
					end
				else
					break
				end
			until not flingActive or BasePart.Velocity.Magnitude > 500 or BasePart.Parent ~= TargetPlayer.Character or TargetPlayer.Parent ~= game:GetService('Players') or TargetPlayer.Character ~= TCharacter or THumanoid.Sit or tick() > Time + TimeToWait
		end

		local previousDestroyHeight = workspace.FallenPartsDestroyHeight
		workspace.FallenPartsDestroyHeight = 0/0

		local BV = Instance.new("BodyVelocity")
		BV.Name = "EpixVel"
		BV.Parent = RootPart
		BV.Velocity = Vector3.new(9e8, 9e8, 9e8)
		BV.MaxForce = Vector3.new(1/0, 1/0, 1/0)

		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

		if TRootPart and THead then
			if (TRootPart.CFrame.p - THead.CFrame.p).Magnitude > 5 then
				SFBasePart(THead)
			else
				SFBasePart(TRootPart)
			end
		elseif TRootPart and not THead then
			SFBasePart(TRootPart)
		elseif not TRootPart and THead then
			SFBasePart(THead)
		elseif not TRootPart and not THead and Accessory and Handle then
			SFBasePart(Handle)
		end

		BV:Destroy()
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
		workspace.CurrentCamera.CameraSubject = Humanoid

		repeat
			if Character and Humanoid and RootPart and getgenv().OldPos then
				RootPart.CFrame = getgenv().OldPos * CFrame.new(0, .5, 0)
				Character:SetPrimaryPartCFrame(getgenv().OldPos * CFrame.new(0, .5, 0))
				Humanoid:ChangeState("GettingUp")
				for _, x in ipairs(Character:GetChildren()) do
					if x:IsA("BasePart") then
						x.Velocity, x.RotVelocity = Vector3.new(), Vector3.new()
					end
				end
			end
			task.wait()
		until not flingActive or (RootPart and getgenv().OldPos and (RootPart.Position - getgenv().OldPos.p).Magnitude < 25)
		workspace.FallenPartsDestroyHeight = previousDestroyHeight
	end
end

local safeHold = {
	active = false,
	tweening = false,
	targetCFrame = nil,
}

runService.Stepped:Connect(function()
	if not safeHold.active then return end
	if not humanoidRootPart or not humanoidRootPart.Parent then return end
	
	humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
	humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
	
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end
	
	if not safeHold.tweening and safeHold.targetCFrame then
		humanoidRootPart.CFrame = safeHold.targetCFrame
	end
end)

local function disablePhysics(stopAnims)
    if physicsDisabled then return end
    physicsDisabled = true
    
    humanoid.EvaluateStateMachine = false
    
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
        end
    end
    upperTorso.CanCollide = false
    lowerTorso.CanCollide = false
    humanoidRootPart.CanCollide = false
    humanoid.AutoRotate = false

    humanoid.PlatformStand = true
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
    humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
    humanoidRootPart.AssemblyAngularVelocity = Vector3.zero

    if not floatForce or not floatForce.Parent then
        if floatForce then
            pcall(function() floatForce:Destroy() end)
        end
        floatForce = Instance.new("BodyForce")
        floatForce.Parent = humanoidRootPart
    end
    pcall(function()
        if floatForce and floatForce.Parent and humanoidRootPart and humanoidRootPart.Parent then
            floatForce.Force = Vector3.new(0, workspace.Gravity * humanoidRootPart:GetMass(), 0)
        end
    end)

    if stopAnims then
        local animateScript = character:FindFirstChild("Animate")
        if animateScript then animateScript.Enabled = false end
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if animator then
            if savedAnimations == nil then
                savedAnimations = {}
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    local anim = track.Animation
                    if anim and anim.AnimationId ~= "" then
                        table.insert(savedAnimations, {
                            id     = anim.AnimationId,
                            time   = track.TimePosition,
                            weight = track.WeightCurrent,
                            speed  = track.Speed,
                            looped = track.Looped,
                        })
                    end
                end
            end
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                track:Stop()
            end
            animator.Parent = nil
        end
    end
end

local function restorePhysics()
    physicsDisabled = false
    
    if floatForce then
        floatForce:Destroy()
        floatForce = nil
    end
    
    humanoid.EvaluateStateMachine = true 
    
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if descendant.Name == "Head"
                or descendant.Name == "UpperTorso"
                or descendant.Name == "LowerTorso"
                or descendant.Name == "Torso" then
                descendant.CanCollide = true
            end
        end
    end
    humanoidRootPart.CanCollide = true
    humanoid.AutoRotate = true
    humanoid.PlatformStand = false
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
    humanoidRootPart.AssemblyAngularVelocity = Vector3.zero

    physicsSettled = false
end

local function getFlatRotationTowards(targetPos)
	local look = Vector3.new(targetPos.X, humanoidRootPart.Position.Y, targetPos.Z) - humanoidRootPart.Position
	if look.Magnitude < 0.01 then
		look = humanoidRootPart.CFrame.LookVector
		look = Vector3.new(look.X, 0, look.Z)
	end
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(Vector3.zero, look.Unit) * CFrame.Angles(math.pi / 2, 0, 0)
end

local function enterTunnelIfNeeded(targetY)
    if physicsSettled then return end
    if not (humanoidRootPart and humanoidRootPart.Parent) then return end
    
    physicsSettled = true
    task.wait()
    if not (humanoidRootPart and humanoidRootPart.Parent) then return end
    
    local look = humanoidRootPart.CFrame.LookVector
    local flatLook = Vector3.new(look.X, 0, look.Z)
    if flatLook.Magnitude < 0.01 then
        flatLook = Vector3.new(0, 0, -1)
    else
        flatLook = flatLook.Unit
    end
    
    fixedRotation = CFrame.lookAt(Vector3.zero, flatLook) * CFrame.Angles(math.pi / 2, 0, 0)
    
    humanoidRootPart.CFrame = CFrame.new(
        humanoidRootPart.Position.X,
        targetY,
        humanoidRootPart.Position.Z
    ) * fixedRotation
    humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
    humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
end

local function teleportFunction(cframe, duration, ifCoin)
    if ifCoin then
        if coinBlacklist[ifCoin] then return nil end
        if coinArrivalTime[ifCoin] and (os.clock() - coinArrivalTime[ifCoin]) > 10 then
            coinBlacklist[ifCoin] = true
            coinArrivalTime[ifCoin] = nil
            setStatus("STATUS: Coin Bugged! Blacklisting and selecting another...")
            return nil
        end
    end

    local cancelled = false
    local currentTween = nil
    local coinCFrame = ifCoin and ifCoin.Parent and ifCoin.CFrame or nil

    local function tweenTo(targetCFrame, dur)
        if cancelled then return false end
        if dur <= 0 then
            humanoidRootPart.CFrame = targetCFrame
            return not cancelled
        end
        dur = math.max(dur, 0.01)
        currentTween = tweenService:Create(
            humanoidRootPart,
            TweenInfo.new(dur, Enum.EasingStyle.Linear),
            {CFrame = targetCFrame}
        )
        currentTween:Play()
        currentTween.Completed:Wait()
        return not cancelled
    end

    if ifCoin and ifCoin.Parent and ifCoin:FindFirstChild('TouchInterest') and (humanoidRootPart.Position - ifCoin.Position).Magnitude < settings["CoinAuraDistance"] then
        setStatus("STATUS: [COIN AURA]: Teleporting Coin to Player...")
        ifCoin.CFrame = humanoidRootPart.CFrame
        if coinArrivalTime[ifCoin] == nil then
            coinArrivalTime[ifCoin] = os.clock()
        end
        
        safeHold.targetCFrame = humanoidRootPart.CFrame 
        safeHold.tweening = false
        
        return nil
    end

    if settings["Mode"] == "Standing" then
        safeHold.active = false
        safeHold.tweening = false
        safeHold.targetCFrame = nil
        
        disablePhysics(false) 
        
        local animateScript = character:FindFirstChild("Animate")
        if animateScript then animateScript.Enabled = true end
        local animator = humanoid:FindFirstChildOfClass("Animator")
        if not animator then
            animator = Instance.new("Animator")
            animator.Parent = humanoid
        end
        
        local fallAnim = Instance.new("Animation")
        fallAnim.AnimationId = "rbxassetid://507767714"
        local fallTrack = animator:LoadAnimation(fallAnim)
        fallTrack:Play()

        setStatus("STATUS: Going for another coin.")
        local handle = {}
        local adjustedCFrame = cframe
        if ifCoin then
            local rot = cframe - cframe.Position
            local safeY = computeSafeTargetY(ifCoin, cframe.Position.Y)
            adjustedCFrame = CFrame.new(cframe.Position.X, safeY, cframe.Position.Z) * rot
        end

        task.spawn(function()
            if not tweenTo(adjustedCFrame, duration) then 
                if fallTrack then fallTrack:Stop() end
                return 
            end
            if ifCoin then
                coinArrivalTime[ifCoin] = coinArrivalTime[ifCoin] or os.clock()
            end
            task.wait(0.1)
            if ifCoin and ifCoin.Parent and ifCoin:FindFirstChild("TouchInterest") then
                ifCoin.CFrame = humanoidRootPart.CFrame
            end
            task.wait(settings["TweenDelay"])
            if not cancelled then
                if fallTrack then fallTrack:Stop() end
                local idleAnim = Instance.new("Animation")
                idleAnim.AnimationId = "rbxassetid://507766666"
                local idleTrack = animator:LoadAnimation(idleAnim)
                idleTrack:Play()
                task.wait(1)
                if idleTrack then idleTrack:Stop() end
                restorePhysics()
            end
        end)

        function handle:Cancel()
            cancelled = true
            if currentTween then currentTween:Cancel() end
            if fallTrack then fallTrack:Stop() end
            if coinCFrame then
                humanoidRootPart.CFrame = coinCFrame + Vector3.new(0, 3, 0)
            end
            restorePhysics()
        end
        return handle
    elseif settings["Mode"] == "Safe" then
        disablePhysics(true)
        setStatus("STATUS: Going for another coin.")

        if not physicsSettled then
            local tunnelY = (ifCoin and ifCoin.Position.Y or cframe.Position.Y) - settings["SafeModeOffset"]
            enterTunnelIfNeeded(tunnelY)
            if not (humanoidRootPart and humanoidRootPart.Parent) then return nil end
        end

        local desiredY = cframe.Position.Y - settings["SafeModeOffset"]
        local safeY = computeSafeTargetY(ifCoin, desiredY, true)
        local targetPos = Vector3.new(
            cframe.Position.X,
            safeY,
            cframe.Position.Z
        )
        
        local targetCFrame = CFrame.new(targetPos) * fixedRotation

        humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.Position) * fixedRotation

        local gyro = Instance.new("BodyGyro")
        gyro.Parent = humanoidRootPart
        gyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        gyro.D = 0
        gyro.P = 10000
        gyro.CFrame = targetCFrame

        safeHold.active = true
        safeHold.targetCFrame = targetCFrame

        local handle = {}
        local tween

        local dist = (humanoidRootPart.Position - targetPos).Magnitude
        if dist > 0.05 then
            local safeDur = math.max(duration, 0.01)
            safeHold.tweening = true
            
            tween = tweenService:Create(
                humanoidRootPart,
                TweenInfo.new(safeDur, Enum.EasingStyle.Linear),
                {Position = targetPos} 
            )
            tween.Completed:Connect(function()
                if not cancelled then
                    safeHold.tweening = false
                end
            end)
            tween:Play()
        else
            safeHold.tweening = false
            humanoidRootPart.CFrame = targetCFrame
        end

        task.spawn(function()
            if tween then tween.Completed:Wait() end
            if gyro then gyro:Destroy() end
            if cancelled then return end
            if ifCoin then
                coinArrivalTime[ifCoin] = coinArrivalTime[ifCoin] or os.clock()
            end
            if ifCoin and ifCoin.Parent and ifCoin:FindFirstChild("TouchInterest") then
                ifCoin.CFrame = humanoidRootPart.CFrame
            end
        end)

        function handle:Cancel()
            cancelled = true
            if tween then tween:Cancel() end
            if gyro then gyro:Destroy() end
            pcall(function()
                if humanoidRootPart and humanoidRootPart.Parent then
                    safeHold.targetCFrame = humanoidRootPart.CFrame
                end
            end)
            safeHold.tweening = false
        end
        return handle
    end
end

local function hasKnife()
	return character:FindFirstChild("Knife") ~= nil or (player.Backpack and player.Backpack:FindFirstChild("Knife") ~= nil)
end

local function resetForAction()
    if currentFarmHandle and currentFarmHandle.Cancel then
        pcall(function() currentFarmHandle:Cancel() end)
        currentFarmHandle = nil
    end

    safeHold.active = false
    safeHold.tweening = false
    safeHold.targetCFrame = nil
    physicsSettled = false

    if floatForce then
        pcall(function() floatForce:Destroy() end)
        floatForce = nil
    end

    if humanoid and humanoid.Parent then
        humanoid.EvaluateStateMachine = true
        humanoid.PlatformStand = false
        humanoid.AutoRotate = true
        pcall(function()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
        end)
    end

    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                local n = part.Name
                if n == "Head" or n == "UpperTorso" or n == "LowerTorso" or n == "Torso" then
                    part.CanCollide = true
                end
            end
        end
    end
    if humanoidRootPart and humanoidRootPart.Parent then
        humanoidRootPart.CanCollide = true
        humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
        humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
    end

    if character then
        local animateScript = character:FindFirstChild("Animate")
        if animateScript then animateScript.Enabled = true end
    end
    if humanoid and humanoid.Parent and not humanoid:FindFirstChildOfClass("Animator") then
        local animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

    physicsDisabled = false

    if humanoidRootPart and humanoidRootPart.Parent then
        humanoidRootPart.CFrame = startPosition
        humanoidRootPart.AssemblyLinearVelocity = Vector3.zero
        humanoidRootPart.AssemblyAngularVelocity = Vector3.zero
    end
    if humanoid and humanoid.Parent then
        pcall(function()
            humanoid:ChangeState(Enum.HumanoidStateType.Running)
            humanoid:ChangeState(Enum.HumanoidStateType.Landed)
        end)
    end
end

local function functionInnocentSheriffHeroMurderer()
    if not (player and player.Character and humanoid and humanoidRootPart) then return end
    if not (roundStarted and fullBag and alive) then return end

    resetForAction()
    task.wait(0.2)

    local iAmMurderer = hasKnife()

    if settings["KillEveryoneIfDone"] and iAmMurderer then
        local knife = character:FindFirstChild("Knife")
            or (player.Backpack and player.Backpack:FindFirstChild("Knife"))

        if not knife then
            setStatus("STATUS: No Knife — can't kill everyone")
            return
        end

        if knife.Parent == player.Backpack then
            humanoid:EquipTool(knife)
            task.wait(0.3)
        end

        setStatus("STATUS: Filled Bag! Killing Everyone...")

        local killed = {}
        local maxPasses = 3
        local killsPerTarget = 8

        for pass = 1, maxPasses do
            local anyAlive = false
            for _, other in ipairs(players:GetPlayers()) do
                if other ~= player and not killed[other] then
                    local oChar = other.Character
                    local oHum  = oChar and oChar:FindFirstChildOfClass("Humanoid")
                    local oHRP  = oChar and oChar:FindFirstChild("HumanoidRootPart")
                    if oHum and oHum.Health > 0 and oHRP then
                        anyAlive = true
                        oHRP.CFrame = humanoidRootPart.CFrame * CFrame.new(0, 0, 0)
                        task.wait(0.15)

                        for i = 1, killsPerTarget * 5 do
                            local eq = character:FindFirstChild("Knife")
                            if eq and eq:FindFirstChild("Stab") then
                                pcall(function() eq.Stab:FireServer("Slash") end)
                            end
                            task.wait(0.04)
                        end

                        if oHum.Health <= 0 then
                            killed[other] = true
                            other:SetAttribute('AmIAlive', nil)
                        end
                    else
                        killed[other] = true
                    end
                end
            end
            if not anyAlive then break end
            task.wait(0.1)
        end

        humanoidRootPart.CFrame = startPosition
        return
    end

    if settings["ShootMurdererIfDone"] and not iAmMurderer then
        local murderer = nil
        for _, other in ipairs(players:GetPlayers()) do
            if other ~= player and other.Character then
                local oChar = other.Character
                local oHasKnife = oChar:FindFirstChild("Knife")
                    or (other.Backpack and other.Backpack:FindFirstChild("Knife"))
                if oHasKnife then
                    murderer = other
                    break
                end
            end
        end

        if murderer then
            setStatus("STATUS: Filled Bag! Flinging Murderer...")
            flingActive = true
            pcall(OdhSkid, murderer, 3)
            flingActive = false
            humanoidRootPart.CFrame = startPosition
            resetForAction()
            setStatus("STATUS: Murderer flung!")
        else
            setStatus("STATUS: Filled Bag! Murderer not found.")
        end
        return
    end

    if settings["ResetIfDone"] then
        if character:FindFirstChild("Humanoid") then
            setStatus("STATUS: Filled Bag! Resetting...")
            task.wait(0.1)
            character.Humanoid.Health = 0
        end
        return
    end
end

local function returnToStartPosition()
    if not (humanoidRootPart and humanoidRootPart.Parent) then return end

    if currentFarmHandle and currentFarmHandle.Cancel then
        currentFarmHandle:Cancel()
        currentFarmHandle = nil
    end

    safeHold.active = false
    safeHold.tweening = false
    safeHold.targetCFrame = nil

    task.wait(0.25)
    if not (humanoidRootPart and humanoidRootPart.Parent) then return end

    local dist = (humanoidRootPart.Position - startPosition.Position).Magnitude
    if dist > 0.05 then
        local duration = math.clamp(dist / settings["AutofarmSpeed"], 0.01, 3)
        local tween = tweenService:Create(
            humanoidRootPart,
            TweenInfo.new(duration, Enum.EasingStyle.Linear),
            {CFrame = startPosition}
        )
        tween:Play()
        tween.Completed:Wait()
    end
    if not (humanoidRootPart and humanoidRootPart.Parent) then return end
    humanoidRootPart.CFrame = startPosition

    if not humanoid:FindFirstChildOfClass("Animator") then
        local animator = Instance.new("Animator")
        animator.Parent = humanoid
    end

	enableAnimate()

    restorePhysics()

	humanoid:ChangeState(Enum.HumanoidStateType.Running)
	humanoid:ChangeState(Enum.HumanoidStateType.Landed)

    savedAnimations = nil
end

local function getNearestCoin()
	local containers = cachedCoinContainers
	if not containers then
		rebuildCoinContainerCache()
		containers = cachedCoinContainers
	end

	local closestCoin, minSqDist = nil, math.huge
	local hrpPos = humanoidRootPart.Position
	local targetCoinType = settings["CoinType"]

	for i = 1, #containers do
		local container = containers[i]
		if container.Parent then
			local children = container:GetChildren()
			for j = 1, #children do
				local coin = children[j]
				if coin:GetAttribute("CoinID") == targetCoinType
					and coin:FindFirstChild("TouchInterest")
					and not coinBlacklist[coin] then
					local cpos = coin.Position
					local dx, dy, dz = hrpPos.X - cpos.X, hrpPos.Y - cpos.Y, hrpPos.Z - cpos.Z
					local sq = dx*dx + dy*dy + dz*dz
					if sq < minSqDist then
						closestCoin = coin
						minSqDist = sq
					end
				end
			end
		end
	end

	return closestCoin, closestCoin and math.sqrt(minSqDist) or nil
end

local function startFarmingLoop()
    task.spawn(function()
        while true do
            local ok, err = pcall(function()
                local processed = false
                if farming and not fullBag and roundStarted and alive
                    and character and humanoidRootPart and humanoidRootPart.Parent
                    and humanoid and humanoid.Parent and humanoid.Health > 0 then
                    local coin, distance = getNearestCoin()
                    if coin and coin.Parent then
                        processed = true
                        if not coinAttemptStart[coin] then
                            coinAttemptStart[coin] = os.clock()
                        end

                        if (os.clock() - coinAttemptStart[coin]) > 10 then
                            coinBlacklist[coin] = true
                            coinAttemptStart[coin] = nil
                            setStatus("STATUS: Coin stuck for 10s! Blacklisting and selecting another...")
                        elseif distance > 250 then
                            if coinArrivalTime[coin] and (os.clock() - coinArrivalTime[coin]) > 10 then
                                coinBlacklist[coin] = true
                                coinArrivalTime[coin] = nil
                                setStatus("STATUS: Coin stuck for 10s! Blacklisting...")
                            else
                                disablePhysics(true)
                                local desiredY = coin.Position.Y - settings["SafeModeOffset"]
                                local safeY = computeSafeTargetY(coin, desiredY, true)
                                local targetPos = Vector3.new(coin.Position.X, safeY, coin.Position.Z)

                                safeHold.active = true
                                safeHold.tweening = false
                                safeHold.targetCFrame = CFrame.new(targetPos) * fixedRotation
                                humanoidRootPart.CFrame = safeHold.targetCFrame

                                coinArrivalTime[coin] = coinArrivalTime[coin] or os.clock()

                                local targetCoin = coin
                                task.spawn(function()
                                    task.wait(0.1)
                                    if targetCoin and targetCoin.Parent and targetCoin:FindFirstChild("TouchInterest")
                                        and humanoidRootPart and humanoidRootPart.Parent then
                                        targetCoin.CFrame = humanoidRootPart.CFrame
                                    end
                                end)
                            end
                        else
                            local handle = teleportFunction(coin.CFrame, distance / settings["AutofarmSpeed"], coin)
                            currentFarmHandle = handle

                            if handle then
                                local t0 = os.clock()
                                local maxWait = (distance / settings["AutofarmSpeed"]) + 4
                                while farming
                                    and coin.Parent
                                    and coin:FindFirstChild("TouchInterest")
                                    and (os.clock() - t0) < maxWait
                                    and not coinBlacklist[coin] do
                                    task.wait(0.05)
                                end

                                if handle and handle.Cancel then
                                    handle:Cancel()
                                end
                                if currentFarmHandle == handle then
                                    currentFarmHandle = nil
                                end
                            else
                                task.wait(0.1)
                            end

                            if not (coin.Parent and coin:FindFirstChild("TouchInterest")) then
                                coinAttemptStart[coin] = nil
                            end
                        end
                    end
                end

                if not processed then
                    task.wait(settings["TweenDelay"])
                else
                    task.wait(settings["TweenDelay"])
                end
            end)
            if not ok then
                setStatus("[Autofarm] loop iteration error: " .. tostring(err))
                if floatForce and not floatForce.Parent then
                    floatForce = nil
                end
                physicsDisabled = false
                task.wait(0.25)
            end
        end
    end)

    task.spawn(function()
        local lastActionTime = os.clock()
        local lastPos = humanoidRootPart.Position
        while true do
            task.wait(2)
            if farming and not fullBag and roundStarted and alive and humanoid and humanoid.Health > 0 and humanoidRootPart and humanoidRootPart.Parent then
                local currentPos = humanoidRootPart.Position
                if (currentPos - lastPos).Magnitude > 5 then
                    lastActionTime = os.clock()
                    lastPos = currentPos
                end
                
                if os.clock() - lastActionTime > 15 then
                    setStatus("STATUS: Autofarm stuck detected! Restarting...")
                    if currentFarmHandle and currentFarmHandle.Cancel then
                        pcall(function() currentFarmHandle:Cancel() end)
                    end
                    currentFarmHandle = nil
                    physicsSettled = false
                    physicsDisabled = false
                    safeHold.active = false
                    safeHold.tweening = false
                    safeHold.targetCFrame = nil
                    if floatForce then
                        pcall(function() floatForce:Destroy() end)
                        floatForce = nil
                    end
                    task.wait(0.5)
                    lastActionTime = os.clock()
                    if humanoidRootPart and humanoidRootPart.Parent then
                        lastPos = humanoidRootPart.Position
                    end
                end
            else
                lastActionTime = os.clock()
                if humanoidRootPart and humanoidRootPart.Parent then
                    lastPos = humanoidRootPart.Position
                end
            end
        end
    end)
end

startFarmingLoop()

local function handleDeathCleanup()
    pcall(function()
        if humanoid and humanoid.Parent then
            humanoid.EvaluateStateMachine = true
            humanoid.PlatformStand = false
            humanoid.AutoRotate = true
        end
    end)

    if floatForce then
        pcall(function() floatForce:Destroy() end)
        floatForce = nil
    end

    safeHold.active = false
    safeHold.tweening = false
    safeHold.targetCFrame = nil

    if currentFarmHandle and currentFarmHandle.Cancel then
        pcall(function() currentFarmHandle:Cancel() end)
        currentFarmHandle = nil
    end

    physicsDisabled = false
    physicsSettled = false
    savedAnimations = nil

    if roundStarted then
        farming = false
        alive = false
    end
end

local function connectCharacter(newCharacter)
    safeHold.active = false
    safeHold.tweening = false
    safeHold.targetCFrame = nil
    character = newCharacter
    humanoidRootPart = newCharacter:WaitForChild('HumanoidRootPart')
    humanoid = newCharacter:WaitForChild('Humanoid')
    lowerTorso = newCharacter:WaitForChild('LowerTorso')
    upperTorso = newCharacter:WaitForChild('UpperTorso')
    startPosition = humanoidRootPart.CFrame

    physicsSettled = false
    physicsDisabled = false
	fixedRotation = nil

    if floatForce then
        pcall(function() floatForce:Destroy() end)
        floatForce = nil
    end
    savedAnimations = nil

    if currentFarmHandle and currentFarmHandle.Cancel then
        pcall(function() currentFarmHandle:Cancel() end)
        currentFarmHandle = nil
    end

    humanoid.Died:Connect(function()
		handleDeathCleanup()
    end)
end

player.CharacterAdded:Connect(connectCharacter)

player.CharacterRemoving:Connect(function()
    safeHold.active = false
    safeHold.tweening = false
    safeHold.targetCFrame = nil
    if floatForce then
        pcall(function() floatForce:Destroy() end)
        floatForce = nil
    end
    physicsDisabled = false
    if currentFarmHandle and currentFarmHandle.Cancel then
        pcall(function() currentFarmHandle:Cancel() end)
        currentFarmHandle = nil
    end
end)

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

end

coinCollected.OnClientEvent:Connect(function(coinType, current, max)
	totalCollected += 1
	roundCoins += 1
	if settings["UI"] == true then
		if settings["UIMode"] == 1 then
			local totalLabel = getTotalCoinLabel()
			if totalLabel then
				totalLabel.Text = "TOTAL COIN COLLECTED: " .. totalCollected
			end
			setStatus("STATUS: Collected Coin! Current Collected: " .. roundCoins .. "/" .. max)
		elseif settings["UIMode"] == 2 or settings["UIMode"] == 3 then
			setStatus("STATUS: Collected Coin! Current Collected: " .. roundCoins .. "/" .. max)
		end
	end
	if coinType == settings["CoinType"] then
		if current == max then
			fullBag = true
			farming = false
			if settings["ResetIfDone"] or settings["ShootMurdererIfDone"] or settings["KillEveryoneIfDone"] then
				functionInnocentSheriffHeroMurderer()
			else
				setStatus("STATUS: Bag full! Returning to start position...")
				task.spawn(function()
					returnToStartPosition()
					setStatus("STATUS: Waiting for round to end... Coins Collected: " .. roundCoins .. "/" .. max)
				end)
			end
		end
	end
end)

roundStart.OnClientEvent:Connect(function()
    detect()
    cachedCoinContainers = nil
    savedAnimations = nil
    roundCoins = 0
    roundStarted = true
    farming = true
    alive = true
    fullBag = false
    physicsSettled = false
    physicsDisabled = false

    if currentFarmHandle and currentFarmHandle.Cancel then
        pcall(function() currentFarmHandle:Cancel() end)
    end
    currentFarmHandle = nil

    fixedRotation = nil

    safeHold.active = false
    safeHold.tweening = false
    safeHold.targetCFrame = nil

    for _, other in ipairs(players:GetPlayers()) do
        if other ~= player then
            other:SetAttribute('AmIAlive', true)
        end
    end

    for _, tr in pairs(exploiterTrackers) do
        tr.violations = 0
        tr.lastPos = nil
        tr.lastTime = nil
        tr.samplesSeen = 0
        tr.directionHistory = {}
    end
    flaggedExploiters = {}
end)

roundEndFade.OnClientEvent:Connect(function()
    detect()
	enableAnimate()
    coinBlacklist = setmetatable({}, {__mode = "k"})
    coinArrivalTime = setmetatable({}, {__mode = "k"})
    coinAttemptStart = setmetatable({}, {__mode = "k"})
    cachedCoinContainers = nil

    if currentFarmHandle and currentFarmHandle.Cancel then
        pcall(function() currentFarmHandle:Cancel() end)
    end
    currentFarmHandle = nil
	fixedRotation = nil
    safeHold.active = false
    safeHold.tweening = false
    safeHold.targetCFrame = nil

	physicsDisabled = false

    for _, tr in pairs(exploiterTrackers) do
        tr.violations = 0
        tr.lastPos = nil
        tr.lastTime = nil
        tr.samplesSeen = 0
        tr.directionHistory = {}
    end
    flaggedExploiters = {}

    if roundStarted then
        setStatus("STATUS: Waiting for round to start.")
        roundCoins = 0
        roundStarted = false
        farming = false
        alive = false
        fullBag = false
        for _, other in ipairs(players:GetPlayers()) do
            if other ~= player then
                other:SetAttribute('AmIAlive', nil)
            end
        end
    end
end)

task.spawn(function()
    local fr = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 30)
    if not fr then return end
    local fg = fr:WaitForChild("Gameplay", 30)
    if not fg then return end
    local pdc = fg:WaitForChild("PlayerDataChanged", 30)
    if not pdc then return end
    pdc.OnClientEvent:Connect(function(data)
        if type(data) == "table" then flingPlayerData = data end
    end)
end)

workspace.ChildRemoved:Connect(function(ch)
    if ch:FindFirstChild("CoinContainer") and ch:FindFirstChild("Spawns") then
        flingPlayerData = {}
    end
end)

local function findMurderer()
    for name, data in pairs(flingPlayerData) do
        if type(data) == "table" and data.Role == "Murderer" then
            local p = players:FindFirstChild(name)
            if p then return p end
        end
    end
    for _, p in ipairs(players:GetPlayers()) do
        if p.Backpack and p.Backpack:FindFirstChild("Knife") then return p end
    end
    for _, p in ipairs(players:GetPlayers()) do
        if p.Character and p.Character:FindFirstChild("Knife") then return p end
    end
    return nil
end

local function findSheriff()
    for name, data in pairs(flingPlayerData) do
        if type(data) == "table" and data.Role == "Sheriff" then
            local p = players:FindFirstChild(name)
            if p then return p end
        end
    end
    for _, p in ipairs(players:GetPlayers()) do
        if p.Backpack and p.Backpack:FindFirstChild("Gun") then return p end
    end
    for _, p in ipairs(players:GetPlayers()) do
        if p.Character and p.Character:FindFirstChild("Gun") then return p end
    end
    return nil
end

local function resolvePlayer(input)
    if not input or input == "" then return nil end
    local s = input:match("^%s*(.-)%s*$")
    if s == "" then return nil end
    local low = s:lower()
    local list = players:GetPlayers()
    for _, p in ipairs(list) do if p.Name:lower() == low then return p end end
    for _, p in ipairs(list) do if p.DisplayName:lower() == low then return p end end
    for _, p in ipairs(list) do if p.Name:lower():sub(1, #low) == low then return p end end
    for _, p in ipairs(list) do if p.DisplayName:lower():sub(1, #low) == low then return p end end
    for _, p in ipairs(list) do if p.Name:lower():find(low, 1, true) then return p end end
    for _, p in ipairs(list) do if p.DisplayName:lower():find(low, 1, true) then return p end end
    return nil
end

local flingBusy = false
local function flingTarget(targetPlayer, duration)
    if flingBusy then setStatus("[Fling] Busy"); return false end
    if not targetPlayer then return false end
    if targetPlayer == player then return false end
    if not targetPlayer.Character then return false end
    duration = tonumber(duration) or 3
    if duration <= 0 then duration = 3 end
    flingBusy = true
    setStatus("[Fling] Flinging " .. targetPlayer.Name .. " for " .. duration .. "s")
    task.spawn(function()
        flingActive = true
        local ok, err = pcall(OdhSkid, targetPlayer, duration)
        flingActive = false
        flingBusy = false
        if ok then
            setStatus("[Fling] Done - flung " .. targetPlayer.Name)
        else
            setStatus("[Fling] Error: " .. tostring(err))
        end
    end)
    return true
end

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
		Interface.Position = UDim2.new(0.5, 0, 1, 0)
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
		Title.Text = "AUTOFARM Scripted by TokyoMemoriess [MODIFY SETTINGS IN SCRIPT]"
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
		local SAFEMODEOFFSET = Instance.new("TextBox")
		local UICorner_13 = Instance.new("UICorner")
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
			UI.Size = UDim2.new(0, 400, 0, 320)
		else
			UI.Size = UDim2.new(0, 150, 0, 100)
		end
		UICorner.CornerRadius = UDim.new(0, 10)
		UICorner.Parent = UI
		
		local uiScale = Instance.new("UIScale")
		uiScale.Scale = 0.65
		uiScale.Parent = UI
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
		Tab01.Position = UDim2.new(0.5, 0, 0.54, 0)
		Tab01.Size = UDim2.new(0, 400, 0, 290)
		UICorner_2.CornerRadius = UDim.new(0, 10)
		UICorner_2.Parent = Tab01
		SPEED.Name = "SPEED"
		SPEED.Parent = Tab01
		SPEED.AnchorPoint = Vector2.new(0.5, 0.5)
		SPEED.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		SPEED.BorderColor3 = Color3.fromRGB(0, 0, 0)
		SPEED.BorderSizePixel = 0
		SPEED.Position = UDim2.new(0.5, 0, 0.21, 0)
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
		SAFE.Position = UDim2.new(0.230000004, 0, 0.075, 0)
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
		STANDING.Position = UDim2.new(0.769999981, 0, 0.075, 0)
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
		DELAY.Position = UDim2.new(0.5, 0, 0.30, 0)
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
		CAURADISTANCE.Position = UDim2.new(0.5, 0, 0.39, 0)
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
		COINTYPE.Position = UDim2.new(0.5, 0, 0.48, 0)
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
		SAFEMODEOFFSET.Name = "SAFEMODEOFFSET"
		SAFEMODEOFFSET.Parent = Tab01
		SAFEMODEOFFSET.AnchorPoint = Vector2.new(0.5, 0.5)
		SAFEMODEOFFSET.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		SAFEMODEOFFSET.BorderColor3 = Color3.fromRGB(0, 0, 0)
		SAFEMODEOFFSET.BorderSizePixel = 0
		SAFEMODEOFFSET.Position = UDim2.new(0.5, 0, 0.57, 0)
		SAFEMODEOFFSET.Size = UDim2.new(0, 350, 0, 25)
		SAFEMODEOFFSET.Font = Enum.Font.SourceSansBold
		SAFEMODEOFFSET.PlaceholderColor3 = Color3.fromRGB(255, 255, 255)
		SAFEMODEOFFSET.PlaceholderText = "SAFE MODE OFFSET"
		SAFEMODEOFFSET.Text = "4"
		SAFEMODEOFFSET.TextColor3 = Color3.fromRGB(255, 255, 255)
		SAFEMODEOFFSET.TextScaled = true
		SAFEMODEOFFSET.TextSize = 14.000
		SAFEMODEOFFSET.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
		SAFEMODEOFFSET.TextStrokeTransparency = 0.900
		SAFEMODEOFFSET.TextWrapped = true
		UICorner_13.CornerRadius = UDim.new(0, 10)
		UICorner_13.Parent = SAFEMODEOFFSET
		KILL.Name = "KILL"
		KILL.Parent = Tab01
		KILL.AnchorPoint = Vector2.new(0.5, 0.5)
		KILL.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		KILL.BorderColor3 = Color3.fromRGB(0, 0, 0)
		KILL.BorderSizePixel = 0
		KILL.Position = UDim2.new(0.769999981, 0, 0.71, 0)
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
		RESET.Position = UDim2.new(0.230000004, 0, 0.71, 0)
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
		SHOOT.Position = UDim2.new(0.5, 0, 0.71, 0)
		SHOOT.Size = UDim2.new(0, 75, 0, 50)
		SHOOT.AutoButtonColor = false
		SHOOT.Font = Enum.Font.SourceSansBold
		SHOOT.Text = "FLING MURDERER ON DONE"
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
		OPTIMIZE.Position = UDim2.new(0.5, 0, 0.85, 0)
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
		STATUS.BackgroundTransparency = 1
		STATUS.TextXAlignment = Enum.TextXAlignment.Center
		STATUS.TextColor3 = Color3.fromRGB(255, 255, 255)
		STATUS.TextScaled = true
		STATUS.TextSize = 14.000
		STATUS.TextStrokeTransparency = 0.900
		STATUS.TextWrapped = true

		if settings["AutofarmSpeed"] then
			SPEED.Text = tostring(settings["AutofarmSpeed"])
		end
		SPEED.MouseEnter:Connect(function()
			tweenService:Create(SPEED, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0), PlaceholderColor3 = Color3.fromRGB(0,0,0)}):Play()
		end)
		SPEED.MouseLeave:Connect(function()
			tweenService:Create(SPEED, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255), PlaceholderColor3 = Color3.fromRGB(255,255,255)}):Play()
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
			tweenService:Create(DELAY, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0,0,0), PlaceholderColor3 = Color3.fromRGB(0,0,0)}):Play()
		end)
		DELAY.MouseLeave:Connect(function()
			tweenService:Create(DELAY, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255), PlaceholderColor3 = Color3.fromRGB(255,255,255)}):Play()
		end)
		DELAY.FocusLost:Connect(function()
			local value = tonumber(DELAY.Text)
			if value then
				settings["TweenDelay"] = math.clamp(value, 0.01, 5)
			end
		end)
		if settings["CoinAuraDistance"] then
			CAURADISTANCE.Text = tostring(settings["CoinAuraDistance"])
		end
		CAURADISTANCE.MouseEnter:Connect(function()
			tweenService:Create(CAURADISTANCE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0,0,0), PlaceholderColor3 = Color3.fromRGB(0,0,0)}):Play()
		end)
		CAURADISTANCE.MouseLeave:Connect(function()
			tweenService:Create(CAURADISTANCE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255), PlaceholderColor3 = Color3.fromRGB(255,255,255)}):Play()
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
			tweenService:Create(COINTYPE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0,0,0), PlaceholderColor3 = Color3.fromRGB(0,0,0)}):Play()
		end)
		COINTYPE.MouseLeave:Connect(function()
			tweenService:Create(COINTYPE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255), PlaceholderColor3 = Color3.fromRGB(255,255,255)}):Play()
		end)
		COINTYPE.FocusLost:Connect(function()
			local value = tostring(COINTYPE.Text)
			if value then
				settings["CoinType"] = value
			end
		end)
		if settings["SafeModeOffset"] then
			SAFEMODEOFFSET.Text = tostring(settings["SafeModeOffset"])
		end
		SAFEMODEOFFSET.MouseEnter:Connect(function()
			tweenService:Create(SAFEMODEOFFSET, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0,0,0), PlaceholderColor3 = Color3.fromRGB(0,0,0)}):Play()
		end)
		SAFEMODEOFFSET.MouseLeave:Connect(function()
			tweenService:Create(SAFEMODEOFFSET, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255), PlaceholderColor3 = Color3.fromRGB(255,255,255)}):Play()
		end)
		SAFEMODEOFFSET.FocusLost:Connect(function()
			local value = tonumber(SAFEMODEOFFSET.Text)
			if value then
				settings["SafeModeOffset"] = value
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

		local CLOSE = Instance.new("TextButton")
		CLOSE.Name = "CLOSE"
		CLOSE.Parent = Tab01
		CLOSE.AnchorPoint = Vector2.new(0.5, 0.5)
		CLOSE.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		CLOSE.BorderColor3 = Color3.fromRGB(0, 0, 0)
		CLOSE.BorderSizePixel = 0
		CLOSE.Position = UDim2.new(0.36, 0, 0.075, 0)
		CLOSE.Size = UDim2.new(0, 25, 0, 25)
		CLOSE.AutoButtonColor = false
		CLOSE.Font = Enum.Font.SourceSansBold
		CLOSE.Text = "X"
		CLOSE.TextColor3 = Color3.fromRGB(255, 255, 255)
		CLOSE.TextScaled = true
		CLOSE.TextSize = 14.000
		CLOSE.TextStrokeTransparency = 0.900
		
		local UICorner_Close = Instance.new("UICorner")
		UICorner_Close.CornerRadius = UDim.new(0, 10)
		UICorner_Close.Parent = CLOSE
		
		local uStroke_Close = Instance.new('UIStroke', CLOSE)
		uStroke_Close.Thickness = 1.5
		uStroke_Close.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		uStroke_Close.Color = Color3.fromRGB(170, 0, 0)

		local TOGGLE = Instance.new("TextButton")
		TOGGLE.Name = "TOGGLE"
		TOGGLE.Parent = Lxchu
		TOGGLE.AnchorPoint = Vector2.new(0.5, 0.5)
		TOGGLE.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		TOGGLE.BorderColor3 = Color3.fromRGB(0, 0, 0)
		TOGGLE.BorderSizePixel = 0
		TOGGLE.Position = UDim2.new(0.85, 0, 0.8, 0)
		TOGGLE.Size = UDim2.new(0, 50, 0, 50)
		TOGGLE.AutoButtonColor = false
		TOGGLE.Font = Enum.Font.SourceSansBold
		TOGGLE.Text = "OPEN"
		TOGGLE.TextColor3 = Color3.fromRGB(255, 255, 255)
		TOGGLE.TextScaled = true
		TOGGLE.TextSize = 14.000
		TOGGLE.TextStrokeTransparency = 0.900
		TOGGLE.Visible = false
		
		local UICorner_Toggle = Instance.new("UICorner")
		UICorner_Toggle.CornerRadius = UDim.new(0, 10)
		UICorner_Toggle.Parent = TOGGLE

		CLOSE.MouseEnter:Connect(function()
			tweenService:Create(CLOSE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		CLOSE.MouseLeave:Connect(function()
			tweenService:Create(CLOSE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		CLOSE.MouseButton1Click:Connect(function()
			UI.Visible = false
			TOGGLE.Visible = true
		end)

		TOGGLE.MouseEnter:Connect(function()
			tweenService:Create(TOGGLE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(255, 255, 255), TextColor3 = Color3.fromRGB(0, 0, 0)}):Play()
		end)
		TOGGLE.MouseLeave:Connect(function()
			tweenService:Create(TOGGLE, TweenInfo.new(0.25, Enum.EasingStyle.Linear), {BackgroundColor3 = Color3.fromRGB(35, 35, 35), TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
		end)
		TOGGLE.MouseButton1Click:Connect(function()
			UI.Visible = true
			TOGGLE.Visible = false
		end)

		UI.Active = true
		Tab01.Active = true

		local odhDragging = false
		local odhDragStart = nil
		local odhStartPos = nil

		local function odhBeginDrag(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				odhDragging = true
				odhDragStart = input.Position
				odhStartPos = UI.Position
			end
		end

		UI.InputBegan:Connect(odhBeginDrag)
		Tab01.InputBegan:Connect(odhBeginDrag)
		Title.InputBegan:Connect(odhBeginDrag)

		userInputService.InputChanged:Connect(function(input)
			if not odhDragging then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				local delta = input.Position - odhDragStart
				UI.Position = UDim2.new(
					odhStartPos.X.Scale,
					odhStartPos.X.Offset + delta.X,
					odhStartPos.Y.Scale,
					odhStartPos.Y.Offset + delta.Y
				)
			end
		end)

		userInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				odhDragging = false
			end
		end)
	elseif settings["UIMode"] == 3 then
		local COLORS = {
			bg          = Color3.fromRGB(10, 10, 14),
			panel       = Color3.fromRGB(18, 18, 24),
			elevated    = Color3.fromRGB(26, 26, 34),
			border      = Color3.fromRGB(42, 42, 53),
			text        = Color3.fromRGB(240, 240, 245),
			textDim     = Color3.fromRGB(138, 138, 154),
			accent      = Color3.fromRGB(124, 92, 255),
			accentLight = Color3.fromRGB(158, 132, 255),
			green       = Color3.fromRGB(74, 222, 128),
			red         = Color3.fromRGB(248, 113, 113),
		}
		local FONT      = Enum.Font.GothamMedium
		local FONT_BOLD = Enum.Font.GothamBold

		local H_TITLE   = 44
		local H_TABBAR  = 34
		local H_STATUS  = 26
		local H_ROW     = 34

		local function corner(p, r)
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, r or 6)
			c.Parent = p
			return c
		end
		local function stroke(p, col, th)
			local s = Instance.new("UIStroke")
			s.Color = col or COLORS.border
			s.Thickness = th or 1
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Parent = p
			return s
		end

		local TokyoUI = Instance.new("ScreenGui")
		TokyoUI.Name = "TokyoUI"
		TokyoUI.ResetOnSpawn = false
		TokyoUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		TokyoUI.IgnoreGuiInset = true
		TokyoUI.Parent = player:WaitForChild("PlayerGui")

		local SoundService = game:GetService("SoundService")
		
		local notifSound = Instance.new("Sound")
		notifSound.SoundId = "rbxassetid://4590662766"
		notifSound.Volume = 0.15
		notifSound.Parent = SoundService

		local NotifContainer = Instance.new("Frame")
		NotifContainer.Name = "NotifContainer"
		NotifContainer.AnchorPoint = Vector2.new(1, 0)
		NotifContainer.Position = UDim2.new(1, -20, 0, 20)
		NotifContainer.Size = UDim2.new(0, 260, 1, -40)
		NotifContainer.BackgroundTransparency = 1
		NotifContainer.Parent = TokyoUI

		local NotifLayout = Instance.new("UIListLayout")
		NotifLayout.Padding = UDim.new(0, 8)
		NotifLayout.SortOrder = Enum.SortOrder.LayoutOrder
		NotifLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		NotifLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		NotifLayout.Parent = NotifContainer

		_G.Notify = function(title, text)
			if notifSound then
				notifSound:Play()
			end

			local notif = Instance.new("Frame")
			notif.Size = UDim2.new(1, 0, 0, 52)
			notif.BackgroundColor3 = COLORS.elevated
			notif.BackgroundTransparency = 1
			notif.Position = UDim2.new(1, 280, 0, 0)
			notif.Parent = NotifContainer
			corner(notif, 8); stroke(notif, COLORS.border, 1)

			local accent = Instance.new("Frame")
			accent.Size = UDim2.new(0, 4, 1, -12)
			accent.Position = UDim2.new(0, 6, 0, 6)
			accent.BackgroundColor3 = COLORS.accent
			accent.BorderSizePixel = 0
			accent.Parent = notif
			corner(accent, 4)

			local titleLbl = Instance.new("TextLabel")
			titleLbl.Size = UDim2.new(1, -24, 0, 18)
			titleLbl.Position = UDim2.new(0, 16, 0, 8)
			titleLbl.BackgroundTransparency = 1
			titleLbl.Font = FONT_BOLD
			titleLbl.Text = title
			titleLbl.TextColor3 = COLORS.text
			titleLbl.TextSize = 12
			titleLbl.TextXAlignment = Enum.TextXAlignment.Left
			titleLbl.Parent = notif

			local textLbl = Instance.new("TextLabel")
			textLbl.Size = UDim2.new(1, -24, 0, 16)
			textLbl.Position = UDim2.new(0, 16, 0, 26)
			textLbl.BackgroundTransparency = 1
			textLbl.Font = FONT
			textLbl.Text = text
			textLbl.TextColor3 = COLORS.textDim
			textLbl.TextSize = 11
			textLbl.TextXAlignment = Enum.TextXAlignment.Left
			textLbl.TextTruncate = Enum.TextTruncate.AtEnd
			textLbl.Parent = notif

			tweenService:Create(notif, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 0
			}):Play()

			task.delay(3.5, function()
				if notif and notif.Parent then
					local tweenOut = tweenService:Create(notif, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
						Position = UDim2.new(1, 280, 0, 0),
						BackgroundTransparency = 1
					})
					tweenOut:Play()
					tweenOut.Completed:Connect(function()
						notif:Destroy()
					end)
				end
			end)
		end

		local UI = Instance.new("Frame")
		UI.Name = "UI"
		UI.AnchorPoint = Vector2.new(0.5, 0.5)
		UI.Position = UDim2.new(0.5, 0, 0.5, 0)
		UI.Size = UDim2.new(0.85, 0, 0.7, 0)
		UI.BackgroundColor3 = COLORS.bg
		UI.BorderSizePixel = 0
		UI.ClipsDescendants = true
		UI.Active = true
		UI.Parent = TokyoUI
		corner(UI, 12)
		stroke(UI, COLORS.border, 1)

		local sizeConstraint = Instance.new("UISizeConstraint")
		sizeConstraint.MaxSize = Vector2.new(420, 380)
		sizeConstraint.MinSize = Vector2.new(280, 300)
		sizeConstraint.Parent = UI

		local TitleBar = Instance.new("Frame")
		TitleBar.Name = "TitleBar"
		TitleBar.Size = UDim2.new(1, 0, 0, H_TITLE)
		TitleBar.BackgroundColor3 = COLORS.panel
		TitleBar.BackgroundTransparency = 1
		TitleBar.BorderSizePixel = 0
		TitleBar.Parent = UI

		local TitleDot = Instance.new("Frame")
		TitleDot.Size = UDim2.new(0, 7, 0, 7)
		TitleDot.Position = UDim2.new(0, 14, 0.5, -3)
		TitleDot.BackgroundColor3 = COLORS.accent
		TitleDot.BorderSizePixel = 0
		TitleDot.Parent = TitleBar
		corner(TitleDot, 4)

		local Title = Instance.new("TextLabel")
		Title.Name = "Title"
		Title.Size = UDim2.new(1, -100, 0, 18)
		Title.Position = UDim2.new(0, 28, 0.5, -19)
		Title.BackgroundTransparency = 1
		Title.Font = FONT_BOLD
		Title.Text = "TokyoMemoriess's Auto Farm"
		Title.TextColor3 = COLORS.text
		Title.TextSize = 13
		Title.TextXAlignment = Enum.TextXAlignment.Left
		Title.Parent = TitleBar

		local Subtitle = Instance.new("TextLabel")
		Subtitle.Size = UDim2.new(1, -100, 0, 14)
		Subtitle.Position = UDim2.new(0, 28, 0.5, 1)
		Subtitle.BackgroundTransparency = 1
		Subtitle.Font = FONT
		Subtitle.Text = "Reworked • V3"
		Subtitle.TextColor3 = COLORS.textDim
		Subtitle.TextSize = 9
		Subtitle.TextXAlignment = Enum.TextXAlignment.Left
		Subtitle.Parent = TitleBar

		local CLOSE = Instance.new("TextButton")
		CLOSE.Name = "CLOSE"
		CLOSE.Size = UDim2.new(0, 26, 0, 26)
		CLOSE.Position = UDim2.new(1, -34, 0.5, -13)
		CLOSE.BackgroundColor3 = COLORS.elevated
		CLOSE.BorderSizePixel = 0
		CLOSE.Font = FONT_BOLD
		CLOSE.Text = "X"
		CLOSE.TextColor3 = COLORS.red
		CLOSE.TextSize = 12
		CLOSE.AutoButtonColor = false
		CLOSE.Parent = TitleBar
		corner(CLOSE, 6)
		stroke(CLOSE, COLORS.border, 1)

		local TOGGLE = Instance.new("TextButton")
		TOGGLE.Name = "TOGGLE"
		TOGGLE.AnchorPoint = Vector2.new(0.5, 0.5)
		TOGGLE.Position = UDim2.new(0.9, 0, 0.88, 0)
		TOGGLE.Size = UDim2.new(0, 44, 0, 44)
		TOGGLE.BackgroundColor3 = COLORS.panel
		TOGGLE.BorderSizePixel = 0
		TOGGLE.Font = FONT_BOLD
		TOGGLE.Text = "T"
		TOGGLE.TextColor3 = COLORS.accent
		TOGGLE.TextSize = 17
		TOGGLE.AutoButtonColor = false
		TOGGLE.Visible = false
		TOGGLE.Parent = TokyoUI
		corner(TOGGLE, 22)
		stroke(TOGGLE, COLORS.accent, 2)

		CLOSE.MouseEnter:Connect(function()
			tweenService:Create(CLOSE, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.red, TextColor3 = COLORS.text}):Play()
		end)
		CLOSE.MouseLeave:Connect(function()
			tweenService:Create(CLOSE, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.elevated, TextColor3 = COLORS.red}):Play()
		end)
		CLOSE.MouseButton1Click:Connect(function()
			UI.Visible = false
			TOGGLE.Visible = true
		end)
		TOGGLE.MouseButton1Click:Connect(function()
			UI.Visible = true
			TOGGLE.Visible = false
		end)

		local TabBar = Instance.new("Frame")
		TabBar.Name = "TabBar"
		TabBar.Size = UDim2.new(1, 0, 0, H_TABBAR)
		TabBar.Position = UDim2.new(0, 0, 0, H_TITLE)
		TabBar.BackgroundColor3 = COLORS.bg
		TabBar.BorderSizePixel = 0
		TabBar.Parent = UI

		local TabDivider = Instance.new("Frame")
		TabDivider.Size = UDim2.new(1, -20, 0, 1)
		TabDivider.Position = UDim2.new(0, 10, 1, -1)
		TabDivider.BackgroundColor3 = COLORS.border
		TabDivider.BorderSizePixel = 0
		TabDivider.Parent = TabBar

		local Tab1Btn = Instance.new("TextButton")
		Tab1Btn.Name = "Tab1Btn"
		Tab1Btn.Size = UDim2.new(0, 96, 0, 26)
		Tab1Btn.Position = UDim2.new(0, 10, 0, 4)
		Tab1Btn.BackgroundColor3 = COLORS.accent
		Tab1Btn.BorderSizePixel = 0
		Tab1Btn.Font = FONT_BOLD
		Tab1Btn.Text = "FARM"
		Tab1Btn.TextColor3 = COLORS.text
		Tab1Btn.TextSize = 11
		Tab1Btn.AutoButtonColor = false
		Tab1Btn.Parent = TabBar
		corner(Tab1Btn, 6)

		local Tab2Btn = Instance.new("TextButton")
		Tab2Btn.Name = "Tab2Btn"
		Tab2Btn.Size = UDim2.new(0, 116, 0, 26)
		Tab2Btn.Position = UDim2.new(0, 112, 0, 4)
		Tab2Btn.BackgroundColor3 = COLORS.elevated
		Tab2Btn.BorderSizePixel = 0
		Tab2Btn.Font = FONT_BOLD
		Tab2Btn.Text = "SERVER HOP"
		Tab2Btn.TextColor3 = COLORS.textDim
		Tab2Btn.TextSize = 11
		Tab2Btn.AutoButtonColor = false
		Tab2Btn.Parent = TabBar
		corner(Tab2Btn, 6)

		local Tab3Btn = Instance.new("TextButton")
		Tab3Btn.Name = "Tab3Btn"
		Tab3Btn.Size = UDim2.new(0, 80, 0, 26)
		Tab3Btn.Position = UDim2.new(0, 234, 0, 4)
		Tab3Btn.BackgroundColor3 = COLORS.elevated
		Tab3Btn.BorderSizePixel = 0
		Tab3Btn.Font = FONT_BOLD
		Tab3Btn.Text = "FLING"
		Tab3Btn.TextColor3 = COLORS.textDim
		Tab3Btn.TextSize = 11
		Tab3Btn.AutoButtonColor = false
		Tab3Btn.Parent = TabBar
		corner(Tab3Btn, 6)

		local Content = Instance.new("Frame")
		Content.Name = "Content"
		Content.Size = UDim2.new(1, 0, 1, -(H_TITLE + H_TABBAR + H_STATUS))
		Content.Position = UDim2.new(0, 0, 0, H_TITLE + H_TABBAR)
		Content.BackgroundTransparency = 1
		Content.Parent = UI

		local STATUS = Instance.new("TextLabel")
		STATUS.Name = "STATUS"
		STATUS.Size = UDim2.new(1, 0, 0, H_STATUS)
		STATUS.Position = UDim2.new(0, 0, 1, -H_STATUS)
		STATUS.BackgroundTransparency = 1
		STATUS.BorderSizePixel = 0
		STATUS.Font = FONT
		STATUS.Text = "STATUS: NIL"
		STATUS.TextColor3 = COLORS.textDim
		STATUS.TextSize = 10
		STATUS.TextXAlignment = Enum.TextXAlignment.Center
		STATUS.TextTruncate = Enum.TextTruncate.AtEnd
		STATUS.Parent = UI

		local function makeTab(name)
			local tab = Instance.new("ScrollingFrame")
			tab.Name = name
			tab.ScrollBarImageTransparency = 1
			tab.Size = UDim2.new(1, -14, 1, -10)
			tab.Position = UDim2.new(0, 7, 0, 5)
			tab.BackgroundTransparency = 1
			tab.BorderSizePixel = 0
			tab.ScrollBarThickness = 0
			tab.ScrollBarImageColor3 = COLORS.border
			tab.CanvasSize = UDim2.new(0, 0, 0, 0)
			tab.AutomaticCanvasSize = Enum.AutomaticSize.Y
			tab.Parent = Content
			local layout = Instance.new("UIListLayout")
			layout.Padding = UDim.new(0, 4)
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Parent = tab
			return tab
		end

		local Tab01 = makeTab("Tab01")
		local Tab02 = makeTab("Tab02")
		local Tab03 = makeTab("Tab03")
		Tab02.Visible = false
		Tab03.Visible = false

		Tab1Btn.MouseButton1Click:Connect(function()
			Tab01.Visible = true; Tab02.Visible = false; Tab03.Visible = false
			tweenService:Create(Tab1Btn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.accent,  TextColor3 = COLORS.text}):Play()
			tweenService:Create(Tab2Btn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.elevated, TextColor3 = COLORS.textDim}):Play()
			tweenService:Create(Tab3Btn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.elevated, TextColor3 = COLORS.textDim}):Play()
		end)
		Tab2Btn.MouseButton1Click:Connect(function()
			Tab01.Visible = false; Tab02.Visible = true; Tab03.Visible = false
			tweenService:Create(Tab2Btn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.accent,  TextColor3 = COLORS.text}):Play()
			tweenService:Create(Tab1Btn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.elevated, TextColor3 = COLORS.textDim}):Play()
			tweenService:Create(Tab3Btn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.elevated, TextColor3 = COLORS.textDim}):Play()
		end)
		Tab3Btn.MouseButton1Click:Connect(function()
			Tab01.Visible = false; Tab02.Visible = false; Tab03.Visible = true
			tweenService:Create(Tab3Btn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.accent,  TextColor3 = COLORS.text}):Play()
			tweenService:Create(Tab1Btn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.elevated, TextColor3 = COLORS.textDim}):Play()
			tweenService:Create(Tab2Btn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.elevated, TextColor3 = COLORS.textDim}):Play()
		end)

		local function createInput(parent, key, labelText, isNumeric, clampRange, order)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, H_ROW)
			row.BackgroundColor3 = COLORS.elevated
			row.BorderSizePixel = 0
			row.LayoutOrder = order or 0
			row.Parent = parent
			corner(row, 6); stroke(row, COLORS.border, 1)

			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(0.55, -12, 1, 0)
			lbl.Position = UDim2.new(0, 10, 0, 0)
			lbl.BackgroundTransparency = 1
			lbl.Font = FONT
			lbl.Text = labelText
			lbl.TextColor3 = COLORS.text
			lbl.TextSize = 11
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextTruncate = Enum.TextTruncate.AtEnd
			lbl.Parent = row

			local inp = Instance.new("TextBox")
			inp.Size = UDim2.new(0.45, -18, 1, -10)
			inp.Position = UDim2.new(0.55, 8, 0, 5)
			inp.BackgroundColor3 = COLORS.panel
			inp.BorderSizePixel = 0
			inp.Font = FONT_BOLD
			inp.Text = tostring(settings[key] or "")
			inp.TextColor3 = COLORS.accentLight
			inp.TextSize = 11
			inp.ClearTextOnFocus = false
			inp.Parent = row
			corner(inp, 4); stroke(inp, COLORS.border, 1)

			inp.FocusLost:Connect(function()
				local oldVal = tostring(settings[key])
				if isNumeric then
					local n = tonumber(inp.Text)
					if n then
						if clampRange then n = math.clamp(n, clampRange[1], clampRange[2]) end
						settings[key] = n
						inp.Text = tostring(n)
						if tostring(n) ~= oldVal then 
							_G.Notify("Setting Updated", labelText .. " set to " .. tostring(n)) 
							saveSettings()
						end
					else
						inp.Text = tostring(settings[key])
					end
				else
					settings[key] = inp.Text
					if inp.Text ~= oldVal then 
						_G.Notify("Setting Updated", labelText .. " set to " .. inp.Text) 
						saveSettings()
					end
				end
			end)
			return row, inp
		end

		local function createToggle(parent, key, labelText, order)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, H_ROW)
			row.BackgroundColor3 = COLORS.elevated
			row.BorderSizePixel = 0
			row.LayoutOrder = order or 0
			row.Parent = parent
			corner(row, 6); stroke(row, COLORS.border, 1)

			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(1, -70, 1, 0)
			lbl.Position = UDim2.new(0, 10, 0, 0)
			lbl.BackgroundTransparency = 1
			lbl.Font = FONT
			lbl.Text = labelText
			lbl.TextColor3 = COLORS.text
			lbl.TextSize = 11
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.TextTruncate = Enum.TextTruncate.AtEnd
			lbl.Parent = row

			local state = settings[key] and true or false
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(0, 40, 0, 20)
			btn.Position = UDim2.new(1, -50, 0.5, -10)
			btn.BackgroundColor3 = state and COLORS.green or COLORS.textDim
			btn.BorderSizePixel = 0
			btn.Font = FONT_BOLD
			btn.Text = state and "ON" or "OFF"
			btn.TextColor3 = COLORS.bg
			btn.TextSize = 9
			btn.AutoButtonColor = false
			btn.Parent = row
			corner(btn, 10)

			btn.MouseButton1Click:Connect(function()
				state = not state
				settings[key] = state
				btn.Text = state and "ON" or "OFF"
				tweenService:Create(btn, TweenInfo.new(0.15), {
					BackgroundColor3 = state and COLORS.green or COLORS.textDim
				}):Play()
				_G.Notify("Toggled", labelText .. ": " .. (state and "ON" or "OFF"))
				saveSettings()
			end)
			return row
		end

		local function createSegment(parent, key, labelText, options, order)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, H_ROW)
			row.BackgroundColor3 = COLORS.elevated
			row.BorderSizePixel = 0
			row.LayoutOrder = order or 0
			row.Parent = parent
			corner(row, 6); stroke(row, COLORS.border, 1)

			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(0.4, -12, 1, 0)
			lbl.Position = UDim2.new(0, 10, 0, 0)
			lbl.BackgroundTransparency = 1
			lbl.Font = FONT
			lbl.Text = labelText
			lbl.TextColor3 = COLORS.text
			lbl.TextSize = 11
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Parent = row

			local container = Instance.new("Frame")
			container.Size = UDim2.new(0.6, -18, 1, -10)
			container.Position = UDim2.new(0.4, 8, 0, 5)
			container.BackgroundColor3 = COLORS.panel
			container.BorderSizePixel = 0
			container.Parent = row
			corner(container, 4); stroke(container, COLORS.border, 1)

			local bw = 1 / #options
			local buttons = {}
			for i, opt in ipairs(options) do
				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(bw, -4, 1, -4)
				btn.Position = UDim2.new((i-1) * bw, 2, 0, 2)
				btn.BackgroundColor3 = (settings[key] == opt) and COLORS.accent or COLORS.panel
				btn.BorderSizePixel = 0
				btn.Font = FONT_BOLD
				btn.Text = opt
				btn.TextColor3 = (settings[key] == opt) and COLORS.text or COLORS.textDim
				btn.TextSize = 10
				btn.AutoButtonColor = false
				btn.Parent = container
				corner(btn, 3)
				buttons[opt] = btn

				btn.MouseButton1Click:Connect(function()
					if settings[key] ~= opt then
						settings[key] = opt
						for o, b in pairs(buttons) do
							local active = (o == opt)
							tweenService:Create(b, TweenInfo.new(0.15), {
								BackgroundColor3 = active and COLORS.accent or COLORS.panel,
								TextColor3 = active and COLORS.text or COLORS.textDim,
							}):Play()
						end
						_G.Notify("Mode Changed", labelText .. " set to " .. opt)
						saveSettings()
					end
				end)
			end
			return row
		end

		local function createButton(parent, labelText, color, onClick, order)
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, 0, 0, H_ROW)
			btn.BackgroundColor3 = color or COLORS.accent
			btn.BorderSizePixel = 0
			btn.Font = FONT_BOLD
			btn.Text = labelText
			btn.TextColor3 = COLORS.text
			btn.TextSize = 11
			btn.AutoButtonColor = false
			btn.LayoutOrder = order or 0
			btn.Parent = parent
			corner(btn, 6)
			btn.MouseEnter:Connect(function()
				tweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = COLORS.accentLight}):Play()
			end)
			btn.MouseLeave:Connect(function()
				tweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3 = color or COLORS.accent}):Play()
			end)
			btn.MouseButton1Click:Connect(function()
				_G.Notify("Action", "Executing " .. labelText)
				onClick()
			end)
			return btn
		end

		createInput(Tab01,"AutofarmSpeed","Autofarm Speed",true,{1,500},1)
		createInput(Tab01,"TweenDelay","Tween Delay",true,{0.01,5},2)
		createInput(Tab01,"CoinAuraDistance","Coin Aura Distance",true,{0,50},3)
		createInput(Tab01,"CoinType","Coin Type",false,nil,4)
		createInput(Tab01,"SafeModeOffset","Safe Mode Offset",true,{0,30},5)
		createSegment(Tab01,"Mode","Mode",{"Safe","Standing"},6)
		createToggle(Tab01,"KillEveryoneIfDone","Kill All When Done",7)
		createToggle(Tab01,"ShootMurdererIfDone","Fling Murderer",8)
		createToggle(Tab01,"ResetIfDone","Reset When Done",9)
		createToggle(Tab01,"FullyOptimizeWhileGrinding","Fully Optimize",10)

		createToggle(Tab02,"ServerHopEnabled","Server Hop Enabled",1)
		createInput(Tab02,"MaxHopAttempts","Max Hop Attempts",true,{1,100},2)
		createInput(Tab02,"MinPlayerCount","Min Player Count",true,{1,12},3)
		createInput(Tab02,"HopCheckInterval","Check Interval (s)",true,{1,60},4)
		createInput(Tab02,"HopGracePeriod","Grace Period (s)",true,{1,120},5)
		createInput(Tab02,"HopLowCountDuration","Low Count Duration (s)",true,{1,120},6)
		createToggle(Tab02,"HopMidRound","Allow Hop Mid-Round",7)
		
		createToggle(Tab02, "ExploiterHopEnabled","Hop on Exploiters",8)
		createInput(Tab02, "MinExploitersToHop","Min Exploiters to Hop",true,{1,12},9)
		createInput(Tab02, "ExploiterViolationThreshold","Violations to Flag",true,{2,50},10)
		createInput(Tab02, "ExploiterFlagCooldown","Flag Cooldown (s)",true,{5,120},11)
		createInput(Tab02, "ExploiterMinMoveDistance","Min Move Distance (studs)",true,{0.5,10},12)
		createInput(Tab02, "ExploiterSampleRate","Sample Rate (s)",true,{0.02,1},13)
		
		createButton(Tab02,"⚡ HOP NOW",COLORS.accent,function()
			if not _G._tokyoServerHop then
				setStatus("[AutoHop] Server-hop module not loaded yet")
				return
			end
			local saved = settings["ServerHopEnabled"]
			settings["ServerHopEnabled"] = true
			_G._tokyoServerHop("Manual user request")
			settings["ServerHopEnabled"] = saved
		end, 14)
		
		createButton(Tab02, "♻ Reset Hop Counter", COLORS.elevated, function()
			if _G._tokyoResetHopCounter then
				_G._tokyoResetHopCounter()
			else
				setStatus("[AutoHop] Hop module not ready")
			end
		end, 15)

		local _, usernameBox = createInput(Tab03, "FlingUsername", "Target Username", false, nil, 1)

		local matchLabel = Instance.new("TextLabel")
		matchLabel.Size = UDim2.new(1, 0, 0, 16)
		matchLabel.BackgroundTransparency = 1
		matchLabel.Font = FONT
		matchLabel.Text = "Matched: -"
		matchLabel.TextSize = 10
		matchLabel.TextColor3 = COLORS.textDim
		matchLabel.TextXAlignment = Enum.TextXAlignment.Left
		matchLabel.LayoutOrder = 2
		matchLabel.Parent = Tab03

		usernameBox:GetPropertyChangedSignal("Text"):Connect(function()
			if usernameBox.Text == "" then
				matchLabel.Text = "Matched: -"
				matchLabel.TextColor3 = COLORS.textDim
				return
			end
			local p = resolvePlayer(usernameBox.Text)
			if p then
				matchLabel.Text = "Matched: " .. p.Name .. " (" .. p.DisplayName .. ")"
				matchLabel.TextColor3 = COLORS.green
			else
				matchLabel.Text = "Matched: - none -"
				matchLabel.TextColor3 = COLORS.red
			end
		end)

		createInput(Tab03, "FlingDuration", "Fling Duration (s)", true, {1, 30}, 3)

		createButton(Tab03, "FLING USERNAME", COLORS.accent, function()
			local target = resolvePlayer(settings["FlingUsername"] or "")
			if not target then
				setStatus("[Fling] No player matched")
				return
			end
			flingTarget(target, settings["FlingDuration"] or 3)
		end, 4)

		createButton(Tab03, "FLING MURDERER", Color3.fromRGB(140, 40, 40), function()
			local target = findMurderer()
			if not target then
				setStatus("[Fling] Murderer not found")
				return
			end
			flingTarget(target, settings["FlingDuration"] or 3)
		end, 5)

		createButton(Tab03, "FLING SHERIFF", Color3.fromRGB(40, 70, 130), function()
			local target = findSheriff()
			if not target then
				setStatus("[Fling] Sheriff not found")
				return
			end
			flingTarget(target, settings["FlingDuration"] or 3)
		end, 6)

		local dragging, dragStart, startPos = false, nil, nil
		local function beginDrag(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPos = UI.Position
			end
		end
		TitleBar.InputBegan:Connect(beginDrag)
		Title.InputBegan:Connect(beginDrag)
		Subtitle.InputBegan:Connect(beginDrag)

		userInputService.InputChanged:Connect(function(input)
			if not dragging then return end
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				local delta = input.Position - dragStart
				UI.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y
				)
			end
		end)
		userInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end
end

task.spawn(function()
    while true do
        if farming and not fullBag and roundStarted and character and humanoid and humanoid.Parent then
            local animateScript = character:FindFirstChild("Animate")
            if animateScript and animateScript.Enabled then
                animateScript.Enabled = false
            end
            local animator = humanoid:FindFirstChildOfClass("Animator")
            if animator then
                local tracks = animator:GetPlayingAnimationTracks()
                for i = 1, #tracks do
                    tracks[i]:Stop(0)
                end
            end
        end
        task.wait(0.05)
    end
end)

local TeleportService = game:GetService("TeleportService")

local HOP_STATE_FILE     = settings["HopStateFile"] or "TokyoFarm_HopState.json"
local HOP_STATE_MAX_JOBS = 100

local function loadHopState()
    local state = { attempts = 0, visitedJobs = {}, lastHoppedFrom = nil }

    if isfile and isfile(HOP_STATE_FILE) then
        pcall(function()
            local data = httpService:JSONDecode(readfile(HOP_STATE_FILE))
            if type(data) ~= "table" then return end
            state.attempts = tonumber(data.attempts) or 0
            state.lastHoppedFrom = type(data.lastHoppedFrom) == "string" and data.lastHoppedFrom or nil

            local vj = data.visitedJobs
            if type(vj) == "table" then
                for k, v in pairs(vj) do
                    if type(k) == "number" then
                        table.insert(state.visitedJobs, v)
                    elseif type(k) == "string" and v == true then
                        table.insert(state.visitedJobs, k)
                    end
                end
            end
        end)
    end

    if game.JobId and game.JobId ~= "" then
        local already = false
        for _, v in ipairs(state.visitedJobs) do
            if tostring(v):lower() == tostring(game.JobId):lower() then
                already = true
                break
            end
        end
        if not already then
            table.insert(state.visitedJobs, game.JobId)
        end
    end

    while #state.visitedJobs > HOP_STATE_MAX_JOBS do
        table.remove(state.visitedJobs, 1)
    end

    return state
end

local function saveHopState(state)
    if not writefile then return end
    pcall(function()
        writefile(HOP_STATE_FILE, httpService:JSONEncode(state))
    end)
end

local hopState = loadHopState()

_G._tokyoResetHopCounter = function()
    hopState.attempts = 0
    saveHopState(hopState)
    setStatus("[AutoHop] Attempt counter reset")
end

task.spawn(function()
    task.wait(300)
    if settings["ServerHopEnabled"] and hopState.attempts > 0 then
        hopState.attempts = 0
        saveHopState(hopState)
        setStatus("[AutoHop] Session healthy, attempt counter reset")
    end
end)

local function httpGetJson(url)
    local body

    local providers = {
        function() return syn and syn.request and syn.request({ Url = url, Method = "GET" }) end,
        function() return http and http.request and http.request({ Url = url, Method = "GET" }) end,
        function() return request and request({ Url = url, Method = "GET" }) end,
    }
    for _, fn in ipairs(providers) do
        local ok, res = pcall(fn)
        if ok and type(res) == "table" and res.Body then
            body = res.Body
            break
        end
    end

    if not body then
        local ok, raw = pcall(function() return game:HttpGet(url) end)
        if ok and type(raw) == "string" then body = raw end
    end

    if not body then return nil end
    local ok, data = pcall(httpService.JSONDecode, httpService, body)
    if not ok or type(data) ~= "table" then return nil end
    return data
end

local function fetchServers()
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100"):format(game.PlaceId)
    local data = httpGetJson(url)
    if not data or type(data.data) ~= "table" then return {} end
    return data.data
end

local function pickBestServer()
    local servers = fetchServers()
    local candidates = {}
    local currentJob = tostring(game.JobId):lower()
    local minPlayers = tonumber(settings["MinPlayerCount"]) or 4

    for _, srv in ipairs(servers) do
        if type(srv) == "table" and type(srv.id) == "string" then
            local srvId = srv.id:lower()
            
            if srvId ~= currentJob then
                local isVisited = false
                for _, v in ipairs(hopState.visitedJobs) do
                    if type(v) == "string" and v:lower() == srvId then
                        isVisited = true
                        break
                    end
                end

                local playing = tonumber(srv.playing) or 0
                local maxPlayers = tonumber(srv.maxPlayers) or 999

                if not isVisited and playing >= minPlayers and playing < maxPlayers then
                    table.insert(candidates, srv)
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        local pa = tonumber(a.playing) or 0
        local pb = tonumber(b.playing) or 0
        if pa ~= pb then return pa > pb end
        return (a.id or "") > (b.id or "")
    end)

    return candidates[1]
end

local hopping = false

local function rememberJob(id)
    if not id or id == "" then return end
    local lowerId = tostring(id):lower()
    for _, v in ipairs(hopState.visitedJobs) do
        if type(v) == "string" and v:lower() == lowerId then return end
    end
    table.insert(hopState.visitedJobs, id)
    while #hopState.visitedJobs > HOP_STATE_MAX_JOBS do
        table.remove(hopState.visitedJobs, 1)
    end
end

local function serverHop(reason)
    if not settings["ServerHopEnabled"] then return end
    if hopping then return end

    local maxAttempts = tonumber(settings["MaxHopAttempts"]) or 10
    if hopState.attempts >= maxAttempts then
        setStatus(("[AutoHop] Max attempts reached (%d/%d). Giving up. Reason: %s")
            :format(hopState.attempts, maxAttempts, tostring(reason)))
        return
    end

    hopping = true
    hopState.attempts = hopState.attempts + 1
    setStatus(("[AutoHop] Attempt %d/%d | Reason: %s")
        :format(hopState.attempts, maxAttempts, tostring(reason)))

    local wasFarming = farming
    if wasFarming ~= nil then farming = false end

    if game.JobId and game.JobId ~= "" then
        rememberJob(game.JobId)
        saveHopState(hopState)
    end

    local target = nil
    for _ = 1, 3 do
        target = pickBestServer()
        if target and tostring(target.id):lower() ~= tostring(game.JobId):lower() then
            break
        end
        target = nil
        task.wait(1)
    end

    if not target then
        setStatus("[AutoHop] No new server found. Cancelling to avoid rejoin.")
        if wasFarming ~= nil then farming = wasFarming end
        hopping = false
        return
    end

    local targetJobId = tostring(target.id)
    if targetJobId:lower() == tostring(game.JobId):lower() then
        setStatus("[AutoHop] Target equals current server. Aborting.")
        if wasFarming ~= nil then farming = wasFarming end
        hopping = false
        return
    end

    rememberJob(targetJobId)
    hopState.lastHoppedFrom = game.JobId
    saveHopState(hopState)

    if queue_on_teleport and getgenv().TokyoFarmSourceURL then
        pcall(function()
            queue_on_teleport("loadstring(game:HttpGet('" .. getgenv().TokyoFarmSourceURL .. "'))()")
        end)
    end

    setStatus(("[AutoHop] Teleporting to: %s"):format(targetJobId))

    local ok, err = pcall(function()
        if TeleportService.TeleportAsync then
            local opts = Instance.new("TeleportOptions")
            opts.ServerInstanceId = targetJobId
            TeleportService:TeleportAsync(game.PlaceId, { players.LocalPlayer }, opts)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId, players.LocalPlayer)
        end
    end)

    if not ok then
        setStatus("[AutoHop] Teleport error: " .. tostring(err))
        if wasFarming ~= nil then farming = wasFarming end
        hopping = false
    end
end

_G._tokyoServerHop = serverHop

task.spawn(function()
    repeat task.wait(1) until game:IsLoaded()
    task.wait(2)

    if hopState.lastHoppedFrom and tostring(hopState.lastHoppedFrom):lower() == tostring(game.JobId):lower() then
        setStatus("[AutoHop] Rejoin detected. Re-hopping with server blacklisted...")
        rememberJob(game.JobId)
        hopState.lastHoppedFrom = nil
        saveHopState(hopState)
        task.wait(1)
        if _G._tokyoServerHop then
            _G._tokyoServerHop("Rejoined the same server")
        end
    else
        hopState.lastHoppedFrom = nil
        saveHopState(hopState)
    end
end)

local function hasActiveAnimation(hum)
    for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
        if track.WeightCurrent > 0.4 and track.Speed ~= 0 then
            return true
        end
    end
    return false
end

local function isStraightLine(dirs)
    if #dirs < 5 then return false end
    local avg = Vector3.zero
    for _, d in ipairs(dirs) do avg = avg + d end
    avg = avg / #dirs
    if avg.Magnitude < 0.01 then return false end
    avg = avg.Unit
    for _, d in ipairs(dirs) do
        if d:Dot(avg) < 0.99 then return false end
    end
    return true
end

local function trackPlayerForExploit(p)
    if p == player then return end
    if exploiterTrackers[p] then return end
    exploiterTrackers[p] = {
        lastPos = nil,
        lastTime = nil,
        violations = 0,
        lastViolation = 0,
        directionHistory = {},
        samplesSeen = 0,
    }
    task.spawn(function()
        while exploiterTrackers[p] and p.Parent do
            local tr = exploiterTrackers[p]
            local char = p.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local now = os.clock()
                local pos = hrp.Position
                local minDist = tonumber(settings["ExploiterMinMoveDistance"]) or 1.5
                
                if tr.lastPos and tr.lastTime and tr.samplesSeen >= 2 then
                    local dt = now - tr.lastTime
                    if dt > 0.02 then
                        local delta = pos - tr.lastPos
                        local dist = delta.Magnitude
                        
                        if dist > minDist then
                            -- Teleport Filter: Ignore huge instant jumps (teleport pads, round transitions)
                            if dist > 100 then
                                tr.violations = 0
                                tr.directionHistory = {}
                            else
                                local pts = 0
                                if hrp.AssemblyLinearVelocity.Magnitude < 3 then
                                    pts = pts + 3
                                end
                                if not hasActiveAnimation(hum) then
                                    pts = pts + 2
                                end
                                if dist > 1 then
                                    table.insert(tr.directionHistory, delta.Unit)
                                    if #tr.directionHistory > 6 then
                                        table.remove(tr.directionHistory, 1)
                                    end
                                    if isStraightLine(tr.directionHistory) then
                                        pts = pts + 1
                                    end
                                end
                                if hum:GetState() == Enum.HumanoidStateType.Physics then
                                    pts = pts + 1
                                end
                                
                                if pts > 0 then
                                    tr.violations = tr.violations + pts
                                    tr.lastViolation = now
                                end
                            end
                        else
                            tr.directionHistory = {}
                        end
                        
                        if now - tr.lastViolation > 4 then
                            tr.violations = math.max(0, tr.violations - 1)
                        end
                        
                        local need = tonumber(settings["ExploiterViolationThreshold"]) or 6
                        if tr.violations >= need then
                            flaggedExploiters[p] = now
                        end
                    end
                end
                tr.lastPos = pos
                tr.lastTime = now
                tr.samplesSeen = tr.samplesSeen + 1
            else
                tr.lastPos = nil
                tr.lastTime = nil
            end
            task.wait(tonumber(settings["ExploiterSampleRate"]) or 0.1)
        end
        exploiterTrackers[p] = nil
    end)
end

for _, p in ipairs(players:GetPlayers()) do trackPlayerForExploit(p) end
players.PlayerAdded:Connect(trackPlayerForExploit)
players.PlayerRemoving:Connect(function(p)
    exploiterTrackers[p] = nil
    flaggedExploiters[p] = nil
end)

task.spawn(function()
    while true do
        task.wait(3)
        if not settings["ExploiterHopEnabled"] then
            flaggedExploiters = {}
            continue
        end
        if not settings["ServerHopEnabled"] then continue end
        if hopping then continue end
        local now = os.clock()
        local cd = tonumber(settings["ExploiterFlagCooldown"]) or 30
        local count, names = 0, {}
        for p, t in pairs(flaggedExploiters) do
            if not p.Parent then
                flaggedExploiters[p] = nil
            elseif now - t > cd then
                flaggedExploiters[p] = nil
            else
                count = count + 1
                names[#names + 1] = p.Name
            end
        end
        if count > 0 then
            setStatus(("[Detect] Suspicious: %d [%s]"):format(count, table.concat(names, ", ")))
        end
        local minCount = tonumber(settings["MinExploitersToHop"]) or 1
        if count >= minCount and _G._tokyoServerHop then
            _G._tokyoServerHop(("Detected %d exploiter(s): %s"):format(count, table.concat(names, ", ")))
            flaggedExploiters = {}
        end
    end
end)

if queue_on_teleport and getgenv().TokyoFarmSourceURL then
    pcall(function()
        queue_on_teleport("loadstring(game:HttpGet('" .. getgenv().TokyoFarmSourceURL .. "'))()")
    end)
end

task.spawn(function()
    local message = workspace:WaitForChild("Message")
    if message then
        serverHop("Roblox Server Shutdown")
    end
end)

game.OnClose = function()
    local lp = players.LocalPlayer
    task.defer(function()
        if lp and lp.Parent then
            task.wait(0.1) 
            serverHop("Connection lost / Kicked")
        end
    end)
end

task.spawn(function()
    while true do
        task.wait(1)
        local lp = players.LocalPlayer
        if lp and not lp.Parent then
            serverHop("LocalPlayer removed from Players (kick)")
            break
        end
    end
end)

task.spawn(function()
    task.wait(settings["HopGracePeriod"] or 12)
    local lowSince = nil

    while true do
        task.wait(settings["HopCheckInterval"] or 3)
        
        if not settings["ServerHopEnabled"] then
            lowSince = nil
            continue
        end

        local count = #players:GetPlayers()

        local threshold = tonumber(settings["MinPlayerCount"]) or 4

        if count <= threshold then
            local shouldSkip = (not settings["HopMidRound"]) and roundStarted and farming
            if not shouldSkip then
                if not lowSince then
                    lowSince = os.time()
                elseif os.time() - lowSince >= (settings["HopLowCountDuration"] or 15) then
                    lowSince = nil
                    serverHop(("Low player count: %d <= %d"):format(count, threshold))
                end
            end
        else
            lowSince = nil
        end
    end
end)

task.spawn(function()
	repeat task.wait() until game:IsLoaded()
	
	if _G.Notify then
		_G.Notify("Script Loaded!", "Made by tokyomemoriess on Discord.")
	else
		game:GetService('StarterGui'):SetCore('SendNotification',{
			Title = "Script Loaded!",
			Text = "Script was made by tokyomemoriess on Discord.",
			Duration = 2,
		})
	end

	local UserInputService = game:GetService("UserInputService")
	if UserInputService.MouseEnabled then
		return
	end

	_G.MobileDevice = "Phone"
	local player = game.Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	playerGui:SetAttribute("Device", "Phone")
	
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	pcall(function()
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Extras"):WaitForChild("ChangeLastDevice"):FireServer("Phone")
	end)
	
	local function clickUI(btn)
		if not btn then return end
		
		if firesignal then
			pcall(firesignal, btn.MouseButton1Click)
		end
		
		if getconnections then
			pcall(function()
				for _, conn in pairs(getconnections(btn.MouseButton1Click)) do
					conn:Fire()
				end
			end)
		end
		
		local vu = game:GetService("VirtualUser")
		if vu then
			local pos = btn.AbsolutePosition + (btn.AbsoluteSize / 2)
			pcall(function()
				vu:CaptureController()
				vu:ClickButton1(pos)
			end)
		end
	end

	local function forceMobileUI()
		local guiFolder = ReplicatedStorage:FindFirstChild("GUI")
		if not guiFolder or not guiFolder:FindFirstChild("MainMobile") then return end
		
		local pcGui = playerGui:FindFirstChild("MainGUI")
		if pcGui and not pcGui:GetAttribute("IsMobile") then
			pcGui.Name = "MainGUI_PC"
			pcGui.Visible = false
			pcGui:SetAttribute("IsMobile", true)
			
			local mobileGui = guiFolder.MainMobile:Clone()
			mobileGui.Name = "MainGUI"
			mobileGui:SetAttribute("IsMobile", true)
			mobileGui.Parent = playerGui
		end
	end

	local function handleGui(gui)
		if gui.Name == "DeviceSelect" then
			local container = gui:WaitForChild("Container", 10)
			if container then
				local phone = container:FindFirstChild("Phone")
				if phone then
					local btn = phone:FindFirstChild("Button")
					if btn then
						task.wait(0.5)
						clickUI(btn)
					end
				end
			end
		elseif gui.Name == "Join" or gui.Name == "JoinPhone" then
			local friends = gui:WaitForChild("Friends", 10)
			if friends then
				local playBtn = friends:FindFirstChild("Play")
				if playBtn then
					task.wait(0.5)
					clickUI(playBtn)
				end
			end
		elseif gui.Name == "MainGUI" then
			task.wait(0.1)
			forceMobileUI()
		end
	end

	for _, child in ipairs(playerGui:GetChildren()) do
		task.spawn(handleGui, child)
	end

	playerGui.ChildAdded:Connect(function(child)
		task.spawn(handleGui, child)
	end)
	
	forceMobileUI()
end)
