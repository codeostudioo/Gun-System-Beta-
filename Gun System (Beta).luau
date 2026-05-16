-- Roblox: Azan_Dev (azanlava) | Discord: azanullah or codeostudio

-- Services
-- I keep these here becuase this script uses them alot.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- Player Info
-- This is a local gun script so everything starts from LocalPlayer.
-- HumanoidRootPart matters here becuase the camera turns the player from that part
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

-- Update these refs when the player gets a new character after respawn.
Player.CharacterAdded:Connect(function(NewCharacter)
	Character = NewCharacter
	HumanoidRootPart = NewCharacter:WaitForChild("HumanoidRootPart")
end)

-- Required modules and remotes
-- Prefix just has the gun data.
-- ShootRemote tells the server to shoot, and GunSoundRemote lets other players hear the shot.
local Prefix = require(ReplicatedStorage.GunData.Prefix)
local ShootRemote = ReplicatedStorage:WaitForChild("ShootRemote")
local GunSoundRemote = ReplicatedStorage:WaitForChild("GunSoundRemote")

-- These tables hold the animation and sound ids for each state.
local AnimationIds = {
	Hold = Prefix.Pistol.Revolver.HoldAnim,
	Shoot = Prefix.Pistol.Revolver.ShootAnim,
	Reload = Prefix.Pistol.Revolver.ReloadAnim,
}

local SoundIds = {
	Hold = Prefix.Pistol.Revolver.EquipSFX,
	Shoot = Prefix.Pistol.Revolver.ShootSFX,
	Reload = Prefix.Pistol.Revolver.ReloadSFX,
}

-- Table will be returned
local Shared = {}

local Gun = {}	-- Class
Gun.__index = Gun	-- Lets the gun object use the methods inside the Gun class.

-- This makes a new gun object.
-- Most of the local gun values are stored here.
function Gun.New()	--Method
	-- setmetatable links this new table back to Gun so it can use the methods below.
	local self = setmetatable({}, Gun)
	
	-- Basic refs the gun keeps using.
	self.Player = Player
	self.Mouse = Player:GetMouse()
	self.Camera = workspace.CurrentCamera
	
	-- Main state values.
	self.Weapon = nil
	self.IsEquipped = false
	self.IsReloading = false
	
	-- These are stored so I can stop or replace them later.
	self.RenderConnection = nil
	self.HoldTrack = nil
	self.ZoomTween = nil
	-- This is the camera position for the over the shoulder view.
	self.CameraOffset = Vector3.new(2.6, 2, 8.5)
	-- These store the recoil kick and then go back to 0 over time.
	self.CameraShake = Vector2.new(0, 0)
	self.CameraShakeRecoverySpeed = 12
	self.CameraShakeHorizontalKick = 0.45
	self.CameraShakeVerticalKick = 1.1
	
	-- These are the main values this revolver uses.
	self.FireCooldown = 0.25
	self.LastShotTime = 0
	self.Ammo = 12
	self.MaxAmmo = 12
	self.Damage = 15
	self.Range = 2
	return self
end

-- This tween makes aiming feel smoother.
function Gun:TweenAimCamera(isAiming)
	-- Aim uses 50 FOV, normal view uses 60.
	local targetFov = 60
	if isAiming then
		targetFov = 50
	end
	
	-- Short tween so it feels smooth but still quick.
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	-- Cancel the old tween first incase the player right clicks really fast.
	if self.ZoomTween then
		self.ZoomTween:Cancel()
	end

	self.ZoomTween = TweenService:Create(self.Camera, tweenInfo, {FieldOfView = targetFov})
	self.ZoomTween:Play()
end

-- This handes all the gun animations.
-- I do it in one place so I dont repeat the same setup 3 times
function Gun:PlayAnimation(state)	--Method
	-- Get the right animation id for the state.
	local animationId = AnimationIds[state]
	
	-- If there is no animation id, just stop here so it doesent error.
	if not animationId then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local humanoid = self.Player.Character and self.Player.Character:FindFirstChildOfClass("Humanoid")
	
	-- Character might not be ready in some edge cases, so I check first.
	if not humanoid then
		return
	end

	-- Use the Animator if its already there, if not just make one.
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	-- Stop the old hold anim first if one is still playing.
	if state == "Hold" and self.HoldTrack then
		self.HoldTrack:Stop(0.1)
		self.HoldTrack = nil
	end

	-- Load the animation and play it right away.
	local animationTrack = animator:LoadAnimation(animation)
	animationTrack:Play()

	-- Save the hold anim so I can stop it later.
	-- If that same hold anim ends, clear the saved track.
	if state == "Hold" then
		self.HoldTrack = animationTrack
		animationTrack.Stopped:Connect(function()
			if self.HoldTrack == animationTrack then
				self.HoldTrack = nil
			end
		end)
	end

	-- Clean up the temp Animation object after a bit.
	Debris:AddItem(animation, 5)
end

-- This handles the gun sounds.
-- I do it this way so the sound comes from the gun area and not just the camera.
function Gun:PlaySound(state, position)	--Method
	-- Get the right sound id for the state
	local soundId = SoundIds[state]
	
	-- If there is no Sound id, just stop here so it doesent error.
	if not soundId then
		return
	end

	-- Tiny invisible part so Roblox has a spot to play the 3D sound from.
	local soundPart = Instance.new("Part")
	soundPart.Name = "GunSoundPart"
	soundPart.Transparency = 1
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.CanQuery = false
	soundPart.CanTouch = false
	soundPart.Size = Vector3.new(1, 1, 1)
	soundPart.CFrame = CFrame.new(position or self.Camera.CFrame.Position)
	soundPart.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	
	-- This controls how far away the sound can still be heard from.
	sound.RollOffMaxDistance = 150
	sound.Parent = soundPart
	sound:Play()

	-- Clean the whole sound part up later so these do not pile up.
	Debris:AddItem(soundPart, 5)
end

-- This is the main over the shoulder camera setup.
-- Once the gun is equipped, this takes over the normal camera.
function Gun:StartAim()	--Method
	
	-- Gets the direction the camera is currently facing.
	local lookVector = self.Camera.CFrame.LookVector
	
	-- Gets the left and right camera angle from where the camera is facing.
	local CameraAngleX = math.deg(math.atan2(-lookVector.X, -lookVector.Z))
	
	-- Gets the up/down camera angle from the direction the camera is facing.
	local CameraAngleY = math.deg(math.asin(math.clamp(lookVector.Y, -1, 1)))
	
	-- Scriptable is needed here or Roblox's normal camera will fight this.
	self.Camera.CameraType = Enum.CameraType.Scriptable
	
	-- This is the normal gun camera fov before right click aim changes it
	self.Camera.FieldOfView = 60
	
	-- Lock the mouse for aiming instead of a free cursor.
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	
	-- I swap the icon too so it feels more like a gun.
	self.Mouse.Icon = "http://www.roblox.com/asset/?id=5681283745"
	
	-- MOUSE MOVEMENT
	-- This turns mouse movement into two angle values.
	-- Then the camera code below uses those every frame.
	local function PlayerInput(_actionName, _inputState, inputObject)
		-- The first two values are unused here, but BindAction stil sends them.
		
		-- Scale X down a bit so the camera doesent feel too fast.
		CameraAngleX -= (inputObject.Delta.X - inputObject.Delta.X * 0.5)
		
		-- Clamp Y so the camera cant flip.
		CameraAngleY = math.clamp(CameraAngleY - inputObject.Delta.Y * 0.5, -80, 80)
	end

	-- I use BindAction here since I only want this while the gun camera is on.
	ContextActionService:BindAction("PlayerInput", PlayerInput, false, Enum.UserInputType.MouseMovement)
	
	-- CAMERA MOVEMENT
	-- This is the main loop for the gun camera.
	self.RenderConnection = RunService.Heartbeat:Connect(function(deltaTime)
		-- deltaTime is used so the recoil fade stays smooth even if fps changes.
		
		-- Recoil fades back here so each shot kicks, then settles.
		self.CameraShake = self.CameraShake:Lerp(Vector2.new(0, 0), math.clamp(deltaTime * self.CameraShakeRecoverySpeed, 0, 1))
		
		-- This is the camera base. Player position first, then left right, up down, and recoil.
		local StartCframe = CFrame.new(HumanoidRootPart.CFrame.Position) * CFrame.Angles(0, math.rad(CameraAngleX + self.CameraShake.X), 0) * CFrame.Angles(math.rad(CameraAngleY + self.CameraShake.Y), 0, 0)
	
		-- Use the camera offset for the shoulder view
		local CameraOffset = self.CameraOffset
		
		-- Turn the local offset into a real world position.
		local CameraCframe = StartCframe:PointToWorldSpace(CameraOffset)
		
		-- Far focus point so the camera keeps aiming forward.
		local CameraFocus = StartCframe:PointToWorldSpace(Vector3.new(CameraOffset.X, CameraOffset.Y, -10000))

		-- lookAt is the easy way to place the camera and keep it facing the right way.
		self.Camera.CFrame = CFrame.lookAt(CameraCframe, CameraFocus)

		-- I also use that same forward direction to turn the player.
		local Looking = self.Camera.CFrame:PointToWorldSpace(Vector3.new(0,0,-10000))
		
		-- This keeps the body, camera, and shot direction lined up.
		HumanoidRootPart.CFrame = CFrame.lookAt(HumanoidRootPart.Position, Vector3.new(Looking.X, HumanoidRootPart.Position.Y, Looking.Z))
	end)
end

-- This cleans up the gun camera.
-- This puts the normal camera and input back.
function Gun:StopAim()	--Method
	-- Stop reading the mouse first.
	ContextActionService:UnbindAction("PlayerInput")

	-- Disconnect the camera loop if its still running.
	if self.RenderConnection then
		self.RenderConnection:Disconnect()
		self.RenderConnection = nil
	end

	-- Stop any tween that might still be going.
	if self.ZoomTween then
		self.ZoomTween:Cancel()
		self.ZoomTween = nil
	end

	-- Reset everything, including the recoil so the next equip starts clean.
	self.CameraShake = Vector2.new(0, 0)
	self.Camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	self.Player.CameraMinZoomDistance = 10
	self.Player.CameraMaxZoomDistance = 50
	self.Camera.FieldOfView = 70
	self.Mouse.Icon = ""
end

-- Equip mostly just turns all the local gun stuff on.
-- Camera, hold anim, hold sound, and ammo ui start here.
function Gun:Equip(weapon: Instance)	--Method
	-- Store the tool first so the rest of the gun code knows what is equipped
	self.Weapon = weapon
	self.IsEquipped = true
	
	-- This starts the main local gun stuff right away.
	self:StartAim()
	self:PlayAnimation("Hold")
	self:PlaySound("Hold", self.Camera.CFrame.Position)
	self.Player.PlayerGui.Ammo.Ammotext.Text = self.Ammo.."/"..self.MaxAmmo
	
	-- Show ammo ui only while the gun is actually equipped.
	self.Player.PlayerGui.Ammo.Ammotext.Visible = true
end

-- Unequip does the opposite and shuts the local gun state down.
-- I also stop the hold anim here so the player doesent get stuck like that.
function Gun:Unequip()	--Method
	-- Hide the ammo ui first since the gun is going away.
	self.Player.PlayerGui.Ammo.Ammotext.Visible = false
	self:StopAim()
	
	-- Stop the hold track if its still playing.
	if self.HoldTrack then
		self.HoldTrack:Stop(0.1)
		self.HoldTrack = nil
	end
	
	self.IsEquipped = false
end

-- This is the local fire flow.
-- Ammo, anim, sound, and recoil happen right away here then the real shot stil goes to the server.
function Gun:Shoot(mousePosition)	--Method
	local currentTime = time()
	
	-- Basic fire rate check so the player cant spam faster than the gun should shoot.
	if currentTime - self.LastShotTime < self.FireCooldown then
		return false
	end

	-- If ammo is gone, stop here and show the message.
	if self.Ammo <= 0 then
		print("No ammo!")
		self.Player.PlayerGui.Ammo.Ammotext.Text = "No ammo!"
		return false
	end

	-- Dont let the player shoot in the middle of a reload.
	if self.IsReloading then
		return false
	end

	-- Update ammo first so the player sees the shot right away.
	self.Ammo -= 1
	self.Player.PlayerGui.Ammo.Ammotext.Text = self.Ammo.."/"..self.MaxAmmo
	
	-- This is the part that tells the server about the shot.
	ShootRemote:FireServer(self.Weapon, self.Ammo, mousePosition, self.Damage, self.Range)
	self.LastShotTime = currentTime
	self:PlayAnimation("Shoot")
	
	-- Random left/right so every shot doesent feel exactly the same
	local HorizontalKick = (math.random() * 2 - 1) * self.CameraShakeHorizontalKick
	local VerticalKick = self.CameraShakeVerticalKick

	-- Add the new kick on top of whatever recoil is still there.
	self.CameraShake += Vector2.new(HorizontalKick, VerticalKick)
	
	-- Only play the local gun sound if the weapon still has a handle.
	if self.Weapon and self.Weapon:FindFirstChild("Handle") then
		self:PlaySound("Shoot", self.Weapon.Handle.Position)
	end
	
	return true
end

-- Reload gives feedback now, then refills the ammo after the reload time.
function Gun:Reload()	--Method
	-- If its already reloading, or already full, there is nothing to do.
	if self.IsReloading or self.Ammo >= self.MaxAmmo then
		if self.Ammo >= self.MaxAmmo then
			print("Ammo already full")
		end
		return false
	end

	-- This starts the reload feedback striaght away.
	self.IsReloading = true
	self.Player.PlayerGui.Ammo.Ammotext.Text = "Reloading"
	self:PlayAnimation("Reload")
	self:PlaySound("Reload", self.Camera.CFrame.Position)
	
	-- Wait 3 seconds, then fill the ammo back up.
	task.delay(3, function()
		self.Ammo = self.MaxAmmo
		self.IsReloading = false
		self.Player.PlayerGui.Ammo.Ammotext.Text = self.Ammo.."/"..self.MaxAmmo
	end)
	
	return true
end

-- This is the one local gun object the client uses.
local NewGun = Gun.New()

-- This hooks the events up to one revolver tool.
local function ConnectRevolver(Revolver)
	if not Revolver then
		return
	end

	-- When the tool is equipped, turn all the local gun systems on.
	Revolver.Equipped:Connect(function()
		NewGun:Equip(Revolver)
	end)

	-- Same thing here, just the cleanup side.
	Revolver.Unequipped:Connect(function()
		NewGun:Unequip()
	end)

	-- Activated is the easiest Tool event to use for firing.
	Revolver.Activated:Connect(function()
		NewGun:Shoot(NewGun.Mouse.Hit.Position)
	end)
end

-- If the player respawns while using the gun, clear the old local gun state.
Player.CharacterAdded:Connect(function()
	if NewGun.IsEquipped then
		NewGun:StopAim()
	end

	NewGun.Weapon = nil
	NewGun.IsEquipped = false
	NewGun.IsReloading = false
	NewGun.HoldTrack = nil
	NewGun.Ammo = NewGun.MaxAmmo
	NewGun.Player.PlayerGui.Ammo.Ammotext.Visible = false

	local NewRevolver = Player:WaitForChild("Backpack"):WaitForChild("Revolver")
	ConnectRevolver(NewRevolver)
end)

-- Shared.Init is the start point for the module.
-- All the tool events, mouse input, and remotes get connected here.
function Shared.Init()
	-- I still wait here becuase studio can sometimes run this before the backpack stuff is ready.
	local CurrentCharacter = Player.Character or Player.CharacterAdded:Wait()
	local Backpack = Player:WaitForChild("Backpack")
	CurrentCharacter:WaitForChild("Humanoid")
	CurrentCharacter:WaitForChild("HumanoidRootPart")
	
	-- This script is built for one revolver.
	local Revolver = Backpack:WaitForChild("Revolver")
	ConnectRevolver(Revolver)
	
	-- Right click aims in if the gun is equiped.
	NewGun.Mouse.Button2Down:Connect(function()
		if NewGun.IsEquipped then
			NewGun:TweenAimCamera(true)
		end
	end)
	
	-- When right click is let go, go back to the normal view.
	NewGun.Mouse.Button2Up:Connect(function()
		if NewGun.IsEquipped then
			NewGun:TweenAimCamera(false)
		end
	end)
	
	-- I skip the local shooter here since their own shot already played.
	GunSoundRemote.OnClientEvent:Connect(function(shooter, position)
		-- If the shooter is us, dont play the same sound twice.
		if shooter == Player then
			return
		end

		NewGun:PlaySound("Shoot", position)
	end)
	
	-- Reload is simple enough that raw keyboard input is fine here
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		-- Only reload when R is pressed and the gun is actually equipped.
		if input.KeyCode == Enum.KeyCode.R and NewGun.IsEquipped then
			NewGun:Reload()
		end
	end)
end

--return modulescript
return Shared
