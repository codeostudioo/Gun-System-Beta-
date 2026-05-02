-- -- Services used by the client gun script for input, camera control, replication, and cleanup.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- These varibles just gives reference to the Local players so we can apply some logic to them. like makeing them aim in the correct way.
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Mouse = Player:GetMouse()
local Camera = workspace.CurrentCamera

-- Get the gun model in ReplicatedStorage.
local Revolver = ReplicatedStorage.Guns.Revolver

-- Get a SoundRemote that will be used to fire the sound to the server.
local GunSoundRemote = ReplicatedStorage:WaitForChild("GunSoundRemote")

-- Required Modules
local Prefix = require(ReplicatedStorage.GunModules.Prefix)
local GunModule = require(ReplicatedStorage.GunModules.Gun)
local NewGun = GunModule.new(Player)

-- Just some varibles defining stuff for the gun like cooldown
local Equiped = false
local RenderConnection = nil
local HoldTrack = nil
local FireCooldown = 0.25
local LastShotTime = 0

-- Shared is what will be shared from the start Local must be called my shared.
local Shared = {}
local Local = {}

-- Helper Functions: To stop the hold animation. so when players unequip the gun it would stop the idle gun Animations form playing.
local function StopHoldAnim()
	if not HoldTrack then
		return
	end

	HoldTrack:Stop(0.1)
	HoldTrack = nil
end

-- Helper Functions: To play the animations for the gun. It first gets the animation that need to be played based of what argument was passed to this function and then plays it.
local function PlayAnim(state)
	
	-- Get animation ID based on state
	local function AnimationState()
		if state == "Hold" then
			return Prefix.Pistol.Prototype.HoldAnim
		elseif state == "Shoot" then
			return Prefix.Pistol.Prototype.ShootAnim
		elseif state == "Reload" then
			return Prefix.Pistol.Prototype.ReloadAnim
		end
	end

	-- Check if animation is valid
	local animationId = AnimationState()
	if not animationId then
		return
	end
	
	-- Create animation
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	
	-- Check if player has humanoid
	local humanoid = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	
	-- check if animator exists
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	
	-- Stop animation
	if state == "Hold" then
		StopHoldAnim()
	end
	
	-- play animation
	local animationTrack = animator:LoadAnimation(animation)
	animationTrack:Play()
	
	-- Store animation track
	if state == "Hold" then
		HoldTrack = animationTrack
		animationTrack.Stopped:Connect(function()
			if HoldTrack == animationTrack then
				HoldTrack = nil
			end
		end)
	end

	-- Destroy aniamtion
	Debris:AddItem(animation, 5)
end

-- Helper Functions: To play the sound for the gun. It first gets the sound that need to be played based of what argument was passed to this function, and it plays it in the world so everone can hear the sound.
local function PlaySoundAtPosition(soundId, position)
	
	-- Check to make sure sound is valid
	if not soundId then
		return
	end
	
	-- create part to play sound
	local soundPart = Instance.new("Part")
	soundPart.Name = "GunSoundPart"
	soundPart.Transparency = 1
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.CanQuery = false
	soundPart.CanTouch = false
	soundPart.Size = Vector3.new(1, 1, 1)
	soundPart.CFrame = CFrame.new(position)
	soundPart.Parent = workspace

	-- create sound and make it play in the part
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.RollOffMaxDistance = 150
	sound.Parent = soundPart
	sound:Play()
	
	-- Destroy Sound part/Sound
	Debris:AddItem(soundPart, 5)
end

-- Helper Functions: To play the sound for the gun. It first gets the sound that need to be played based of what argument was passed to this function, and plays it for the person playing the game.
local function PlaySound(state, position)
	
	-- check what type of sound should be palyed
	local function SoundState()
		if state == "Hold" then
			return Prefix.Pistol.Prototype.EquipSFX
		elseif state == "Shoot" then
			return Prefix.Pistol.Prototype.ShootSFX
		elseif state == "Reload" then
			return Prefix.Pistol.Prototype.ReloadSFX
		end
	end
	
	-- return if not sound Id
	local soundId = SoundState()
	if not soundId then
		return
	end
	
	-- Play sound for the player
	PlaySoundAtPosition(soundId, position or Camera.CFrame.Position)
end

-- Main Connecting function that init the logic. A revolver it is passed to the player to use and then all the input event are connected here so one function will set up the whole weapon flow
function Shared.Init()
	-- check for players character, Humanoid, and HumanoidRootPart
	Player:WaitForChild("Backpack")
	Player.Character:WaitForChild("Humanoid")
	Player.Character:WaitForChild("HumanoidRootPart")
	
	-- Put gun in the backpack
	local RevolverClone = Player.Backpack:WaitForChild("Revolver")
	
	-- Mouse input: when gun is Equipped
	RevolverClone.Equipped:Connect(function()
		Local.StartAim()
		PlayAnim("Hold")
		PlaySound("Hold", Camera.CFrame.Position)
		Player.PlayerGui.Ammo.Ammotext.Visible = true
		Equiped = true
	end)
	
	-- Mouse input: when gun is Unequipped
	RevolverClone.Unequipped:Connect(function()
		Player.PlayerGui.Ammo.Ammotext.Visible = false
		Local.StopAim()
		StopHoldAnim()
		Equiped = false
	end)
	
	-- Mouse input: when gun is shot
	RevolverClone.Activated:Connect(function()
		local currentTime = time()
		if currentTime - LastShotTime < FireCooldown then
			return
		end

		local didShoot = NewGun:Shoot(Mouse.Hit.Position, RevolverClone)
		if not didShoot then
			return
		end

		LastShotTime = currentTime
		PlayAnim("Shoot")
		if RevolverClone:FindFirstChild("Handle") then
			PlaySound("Shoot", RevolverClone.Handle.Position)
		end
	end)
	
	-- Zoom in
	Mouse.Button2Down:Connect(function()
		if Equiped then
			Camera.FieldOfView = 60 -- Zoom in
		end
	end)
	
	-- Zoom out
	Mouse.Button2Up:Connect(function()
		if Equiped then
			Camera.FieldOfView = 90 -- Zoom out
		end
	end)
	
	-- Sound to whole server
	GunSoundRemote.OnClientEvent:Connect(function(shooter, position)
		if shooter == Player then
			return
		end

		PlaySound("Shoot", position)
	end)

	-- Reload
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.R and Equiped then
			local didReload = NewGun:Reload()
			if not didReload then
				return
			end

			PlayAnim("Reload")
			PlaySound("Reload", Camera.CFrame.Position)
		end
	end)
end

-- Make the OTS aim work for the player by setting a offset to the camera by (2, 2, 8) and update every frame.
function Local.StartAim()
	-- Set up the camera and mouse movement
	local lookVector = Camera.CFrame.LookVector
	local CameraAngleX = math.deg(math.atan2(-lookVector.X, -lookVector.Z))
	local CameraAngleY = math.deg(math.asin(math.clamp(lookVector.Y, -1, 1)))
	local CameraOffset = Vector3.new(2, 2, 8)

	--Change camera to scriptable since we need to make a custom camera and then just change the icon and mousebehavior
	Camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	Mouse.Icon = "http://www.roblox.com/asset/?id=5681283745"

	--Mouse Movement
	local function PlayerInput(actionName, inputState, inputObject)
		CameraAngleX -= (inputObject.Delta.X - inputObject.Delta.X * 0.5)
		CameraAngleY = math.clamp(CameraAngleY - inputObject.Delta.Y * 0.5, -80, 80)
	end
	ContextActionService:BindAction("PlayerInput", PlayerInput, false, Enum.UserInputType.MouseMovement)

	--Camera Movement
	RenderConnection = RunService.RenderStepped:Connect(function()
		local StartCframe = CFrame.new(HumanoidRootPart.CFrame.Position) * CFrame.Angles(0, math.rad(CameraAngleX), 0) * CFrame.Angles(math.rad(CameraAngleY), 0, 0)

		local CameraCframe = StartCframe:PointToWorldSpace(CameraOffset)
		local CameraFocus = StartCframe:PointToWorldSpace(Vector3.new(CameraOffset.X, CameraOffset.Y, -10000))

		Camera.CFrame = CFrame.lookAt(CameraCframe, CameraFocus)


		local Looking = Camera.CFrame:PointToWorldSpace(Vector3.new(0,0,-10000))
		HumanoidRootPart.CFrame = CFrame.lookAt(HumanoidRootPart.Position, Vector3.new(Looking.X, HumanoidRootPart.Position.Y, Looking.Z))
	end)	
end

-- Stop the OTS aim by resetting the camera and mouse behavior
function Local.StopAim()
	ContextActionService:UnbindAction("PlayerInput")

	if RenderConnection then
		RenderConnection:Disconnect()
		RenderConnection = nil
	end

	Camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	Player.CameraMinZoomDistance = 10
	Player.CameraMaxZoomDistance = 50
	Camera.FieldOfView = 70

	Mouse.Icon = ""
end

-- Return the table to the module loader
return Shared