local player = game:GetService("Players").LocalPlayer
flingActive = false

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
				table.foreach(Character:GetChildren(), function(_, x)
					if x:IsA("BasePart") then
						x.Velocity, x.RotVelocity = Vector3.new(), Vector3.new()
					end
				end)
			end
			task.wait()
		until not flingActive or (RootPart and getgenv().OldPos and (RootPart.Position - getgenv().OldPos.p).Magnitude < 25)
		workspace.FallenPartsDestroyHeight = previousDestroyHeight
	end
end

local odhPlayers = game:GetService("Players")
local odhUIS = game:GetService("UserInputService")
local odhTS = game:GetService("TweenService")

local function odhResolvePlayer(input)
	if not input then return nil end
	local s = input:match("^%s*(.-)%s*$")
	if s == "" then return nil end
	local low = s:lower()
	local list = odhPlayers:GetPlayers()

	for _, p in ipairs(list) do
		if p.Name:lower() == low then return p end
	end
	for _, p in ipairs(list) do
		if p.DisplayName:lower() == low then return p end
	end
	for _, p in ipairs(list) do
		if p.Name:lower():sub(1, #low) == low then return p end
	end
	for _, p in ipairs(list) do
		if p.DisplayName:lower():sub(1, #low) == low then return p end
	end
	for _, p in ipairs(list) do
		if p.Name:lower():find(low, 1, true) then return p end
	end
	for _, p in ipairs(list) do
		if p.DisplayName:lower():find(low, 1, true) then return p end
	end
	return nil
end

local odhGui = Instance.new("ScreenGui")
odhGui.Name = "OdhSkidUI"
odhGui.ResetOnSpawn = false
odhGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
odhGui.IgnoreGuiInset = true
odhGui.Parent = player:WaitForChild("PlayerGui")

local odhFrame = Instance.new("Frame")
odhFrame.Size = UDim2.new(0, 340, 0, 200)
odhFrame.Position = UDim2.new(0.5, -170, 0, 60)
odhFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
odhFrame.BorderSizePixel = 0
odhFrame.Active = true
odhFrame.Draggable = true
odhFrame.Parent = odhGui

local odhCorner = Instance.new("UICorner")
odhCorner.CornerRadius = UDim.new(0, 10)
odhCorner.Parent = odhFrame

local odhStroke = Instance.new("UIStroke")
odhStroke.Color = Color3.fromRGB(45, 45, 45)
odhStroke.Thickness = 1.5
odhStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
odhStroke.Parent = odhFrame

local odhTitle = Instance.new("TextLabel")
odhTitle.Size = UDim2.new(1, -44, 0, 26)
odhTitle.Position = UDim2.new(0, 14, 0, 6)
odhTitle.BackgroundTransparency = 1
odhTitle.Font = Enum.Font.SourceSansBold
odhTitle.Text = "ODH SKID"
odhTitle.TextSize = 15
odhTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
odhTitle.TextXAlignment = Enum.TextXAlignment.Left
odhTitle.Parent = odhFrame

local odhClose = Instance.new("TextButton")
odhClose.Size = UDim2.new(0, 24, 0, 24)
odhClose.Position = UDim2.new(1, -34, 0, 6)
odhClose.BackgroundColor3 = Color3.fromRGB(60, 32, 32)
odhClose.BorderSizePixel = 0
odhClose.AutoButtonColor = false
odhClose.Font = Enum.Font.SourceSansBold
odhClose.Text = "×"
odhClose.TextColor3 = Color3.fromRGB(255, 255, 255)
odhClose.TextSize = 18
odhClose.Parent = odhFrame

local odhCloseCorner = Instance.new("UICorner")
odhCloseCorner.CornerRadius = UDim.new(0, 6)
odhCloseCorner.Parent = odhClose

odhClose.MouseEnter:Connect(function()
	odhTS:Create(odhClose, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(120, 40, 40)}):Play()
end)
odhClose.MouseLeave:Connect(function()
	odhTS:Create(odhClose, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(60, 32, 32)}):Play()
end)
odhClose.MouseButton1Click:Connect(function()
	odhFrame.Visible = false
end)

local odhBox = Instance.new("TextBox")
odhBox.Size = UDim2.new(1, -28, 0, 34)
odhBox.Position = UDim2.new(0, 14, 0, 40)
odhBox.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
odhBox.BorderSizePixel = 0
odhBox.Font = Enum.Font.SourceSansBold
odhBox.PlaceholderText = "Username / DisplayName  (Enter)"
odhBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
odhBox.Text = ""
odhBox.TextColor3 = Color3.fromRGB(255, 255, 255)
odhBox.TextSize = 14
odhBox.ClearTextOnFocus = false
odhBox.Parent = odhFrame

local odhBoxCorner = Instance.new("UICorner")
odhBoxCorner.CornerRadius = UDim.new(0, 8)
odhBoxCorner.Parent = odhBox

local odhBoxStroke = Instance.new("UIStroke")
odhBoxStroke.Color = Color3.fromRGB(50, 50, 50)
odhBoxStroke.Thickness = 1
odhBoxStroke.Parent = odhBox

odhBox.Focused:Connect(function()
	odhBoxStroke.Color = Color3.fromRGB(90, 120, 200)
end)
odhBox.FocusLost:Connect(function()
	odhBoxStroke.Color = Color3.fromRGB(50, 50, 50)
end)

local odhDurLbl = Instance.new("TextLabel")
odhDurLbl.Size = UDim2.new(0, 80, 0, 24)
odhDurLbl.Position = UDim2.new(0, 14, 0, 82)
odhDurLbl.BackgroundTransparency = 1
odhDurLbl.Font = Enum.Font.SourceSansBold
odhDurLbl.Text = "Duration:"
odhDurLbl.TextSize = 13
odhDurLbl.TextColor3 = Color3.fromRGB(180, 180, 180)
odhDurLbl.TextXAlignment = Enum.TextXAlignment.Left
odhDurLbl.Parent = odhFrame

local odhDur = Instance.new("TextBox")
odhDur.Size = UDim2.new(0, 60, 0, 24)
odhDur.Position = UDim2.new(0, 90, 0, 82)
odhDur.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
odhDur.BorderSizePixel = 0
odhDur.Font = Enum.Font.SourceSansBold
odhDur.Text = "5"
odhDur.TextColor3 = Color3.fromRGB(255, 255, 255)
odhDur.TextSize = 13
odhDur.Parent = odhFrame

local odhDurCorner = Instance.new("UICorner")
odhDurCorner.CornerRadius = UDim.new(0, 6)
odhDurCorner.Parent = odhDur

local odhDurSuffix = Instance.new("TextLabel")
odhDurSuffix.Size = UDim2.new(0, 60, 0, 24)
odhDurSuffix.Position = UDim2.new(0, 156, 0, 82)
odhDurSuffix.BackgroundTransparency = 1
odhDurSuffix.Font = Enum.Font.SourceSans
odhDurSuffix.Text = "seconds"
odhDurSuffix.TextSize = 13
odhDurSuffix.TextColor3 = Color3.fromRGB(140, 140, 140)
odhDurSuffix.TextXAlignment = Enum.TextXAlignment.Left
odhDurSuffix.Parent = odhFrame

local odhMatch = Instance.new("TextLabel")
odhMatch.Size = UDim2.new(1, -28, 0, 18)
odhMatch.Position = UDim2.new(0, 14, 0, 116)
odhMatch.BackgroundTransparency = 1
odhMatch.Font = Enum.Font.SourceSans
odhMatch.Text = "Matched: —"
odhMatch.TextSize = 12
odhMatch.TextColor3 = Color3.fromRGB(140, 140, 140)
odhMatch.TextXAlignment = Enum.TextXAlignment.Left
odhMatch.Parent = odhFrame

local odhStatus = Instance.new("TextLabel")
odhStatus.Size = UDim2.new(1, -28, 0, 42)
odhStatus.Position = UDim2.new(0, 14, 0, 142)
odhStatus.BackgroundTransparency = 1
odhStatus.Font = Enum.Font.SourceSansBold
odhStatus.Text = "Status: idle"
odhStatus.TextSize = 13
odhStatus.TextColor3 = Color3.fromRGB(160, 160, 160)
odhStatus.TextXAlignment = Enum.TextXAlignment.Left
odhStatus.TextYAlignment = Enum.TextYAlignment.Top
odhStatus.TextWrapped = true
odhStatus.Parent = odhFrame

odhBox:GetPropertyChangedSignal("Text"):Connect(function()
	local raw = odhBox.Text
	if raw == "" then
		odhMatch.Text = "Matched: —"
		odhMatch.TextColor3 = Color3.fromRGB(140, 140, 140)
		return
	end
	local p = odhResolvePlayer(raw)
	if p then
		odhMatch.Text = "Matched: " .. p.Name .. " (" .. p.DisplayName .. ")"
		odhMatch.TextColor3 = Color3.fromRGB(120, 200, 120)
	else
		odhMatch.Text = "Matched: — none —"
		odhMatch.TextColor3 = Color3.fromRGB(200, 90, 90)
	end
end)

local function odhSetStatus(text, color)
	odhStatus.Text = "Status: " .. text
	odhStatus.TextColor3 = color or Color3.fromRGB(160, 160, 160)
end

odhUIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.F4 then
		odhFrame.Visible = not odhFrame.Visible
	end
end)

local odhBusy = false

odhBox.FocusLost:Connect(function(enterPressed)
	if not enterPressed then return end
	local raw = odhBox.Text
	if raw == "" then return end

	if odhBusy then
		odhSetStatus("already flinging, please wait", Color3.fromRGB(210, 160, 60))
		return
	end

	local target = odhResolvePlayer(raw)
	if not target then
		odhSetStatus("no player matched '" .. raw .. "'", Color3.fromRGB(200, 60, 60))
		return
	end
	if target == player then
		odhSetStatus("cannot fling yourself", Color3.fromRGB(200, 60, 60))
		return
	end
	if not target.Character then
		odhSetStatus(target.Name .. " has no character", Color3.fromRGB(200, 60, 60))
		return
	end

	local duration = tonumber(odhDur.Text) or 5
	if duration <= 0 then duration = 5 end

	odhBusy = true
	odhSetStatus("flinging " .. target.Name .. " for " .. duration .. "s", Color3.fromRGB(140, 160, 255))

	task.spawn(function()
		flingActive = true
		local ok, err = pcall(OdhSkid, target, duration)
		flingActive = false
		odhBusy = false
		if ok then
			odhSetStatus("done — flung " .. target.Name, Color3.fromRGB(75, 170, 0))
		else
			odhSetStatus("error: " .. tostring(err), Color3.fromRGB(200, 60, 60))
		end
	end)
end)
