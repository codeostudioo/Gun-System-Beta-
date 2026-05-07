--Created by:
--	Roblox: Azan_Dev (azanlava)
--	Discord: azanullah or codeostudio

-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- Player Info
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

-- Required modules and remotes
local Prefix = require(ReplicatedStorage.GunModules.Prefix)
local ShootRemote = ReplicatedStorage:WaitForChild("ShootRemote")
local GunSoundRemote = ReplicatedStorage:WaitForChild("GunSoundRemote")

-- Table will be returned
local Shared = {}

local Gun = {}	-- Class
Gun.__index = Gun	-- Lets the gun object use the methods inside the Gun class.

--[[

	Explanation of OOP in Luau:
	
	To start, a class is basically a blueprint or a like a template for creating objects.
	A class defines the main propertise and method all objects made from the class will have
	
	When we do Gun.new() we are basically calling the method new from the class and passing any perpamiter if they have any.
	That new method will then create the object.
	
	Then we link the object to the class using setmetatable, and by doing this the object can use the other methods and properties from the class.
	By using self in the method the script can look back to specific object and can call other methods from it.

	So a class is basically the whole process of creating objects that give the same propertise and methods. but if the script would change something in the class it would only change it for the object.
	So the class is like the starting properties and methods that all the objects created by the new function will have.
	
	Another way to see class that class is basically the whole process of OOP is:
	Defining the class (local Gun = {}) 
	Creating objects with Gun.new() 
	Linking objects to the class using setmetatable 
	Calling methods using self to refer to the object
		
--]]

-- This makes a new gun object from the Gun class.
-- It stores all the main values the gun needs like the player, mouse, camera,
-- ammo, damage, range, reload state, and some other values used for the gun behavior.
-- Creating Object 
function Gun.New()	--Method
	local self = setmetatable({}, Gun)
	self.Player = Player
	self.Mouse = Player:GetMouse()
	self.Camera = workspace.CurrentCamera
	self.Weapon = nil
	self.IsEquipped = false
	self.IsReloading = false
	self.RenderConnection = nil
	self.HoldTrack = nil
	self.FireCooldown = 0.25
	self.LastShotTime = 0
	self.Ammo = 12
	self.MaxAmmo = 12
	self.Damage = 15
	self.Range = 2
	return self
end

-- This updates the ammo text on the player's screen.
-- If a custom text is passed in like "Reloading", it shows that instead of the normal ammo text.
function Gun:UpdateAmmoText(text)	--Method
	self.Player.PlayerGui.Ammo.Ammotext.Text = text or (self.Ammo.."/"..self.MaxAmmo)
end

-- This is what happens when the gun plays a animation.
-- First it checks what animation should be played based on the state, 
-- then it makes sure the animation is valid, then it creates the animation, then makes sure the player has a humanoid and animator, then stops the old hold animation if needed,
-- then plays the new animation, then saves the hold animation track, and then removes the animation object after a short time.
function Gun:PlayAnimation(state)	--Method
	local function AnimationState()
		if state == "Hold" then
			return Prefix.Pistol.Revolver.HoldAnim
		elseif state == "Shoot" then
			return Prefix.Pistol.Revolver.ShootAnim
		elseif state == "Reload" then
			return Prefix.Pistol.Revolver.ReloadAnim
		end
	end

	local animationId = AnimationState()
	if not animationId then
		return
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local humanoid = self.Player.Character and self.Player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	if state == "Hold" and self.HoldTrack then
		self.HoldTrack:Stop(0.1)
		self.HoldTrack = nil
	end

	local animationTrack = animator:LoadAnimation(animation)
	animationTrack:Play()

	if state == "Hold" then
		self.HoldTrack = animationTrack
		animationTrack.Stopped:Connect(function()
			if self.HoldTrack == animationTrack then
				self.HoldTrack = nil
			end
		end)
	end

	Debris:AddItem(animation, 5)
end

-- This is what happens when the gun plays a sound.
-- First it checks what sound should be played based on the state, then it makes sure the sound is valid, then it makes a invisible part in the world,
-- then puts the sound inside it, then plays it, and then removes it after a short time.
function Gun:PlaySound(state, position)	--Method
	local function SoundState()
		if state == "Hold" then
			return Prefix.Pistol.Revolver.EquipSFX
		elseif state == "Shoot" then
			return Prefix.Pistol.Revolver.ShootSFX
		elseif state == "Reload" then
			return Prefix.Pistol.Revolver.ReloadSFX
		end
	end

	local soundId = SoundState()
	if not soundId then
		return
	end

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
	sound.RollOffMaxDistance = 150
	sound.Parent = soundPart
	sound:Play()

	Debris:AddItem(soundPart, 5)
end

-- This function make the OTS gun system aim work for the player by setting the players camera offset to (2, 2, 8) and then it will update every frame.
function Gun:StartAim()	--Method
	-- This is the main aim function for the custom over the shoulder camera.

	-- Gets the direction the camera is currently facing.
	local lookVector = self.Camera.CFrame.LookVector
	
	-- Gets the left and right camera angle from where the camera is facing.
	local CameraAngleX = math.deg(math.atan2(-lookVector.X, -lookVector.Z))
	
	-- Gets the up/down camera angle from the direction the camera is facing.
	local CameraAngleY = math.deg(math.asin(math.clamp(lookVector.Y, -1, 1)))
	
	-- Sets the camera offset so the aim view stays above, behind, and a little to the side of the player.
	local CameraOffset = Vector3.new(2, 2, 8)
	
	-- Sets the camera to scriptable so this script can control it instead of Roblox default camera.
	self.Camera.CameraType = Enum.CameraType.Scriptable
	
	-- Sets the Mouse To be locked to the center of the screen.
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	
	-- Sets the mouse icon to the given icon.
	self.Mouse.Icon = "http://www.roblox.com/asset/?id=5681283745"
	
	--MOUSE MOVEMENT
	-- Just makes a function that later we can call once the mouse starts moving to update the camera based off which direction the mouse is moving.
	-- actionName: The action name we could use this to check if the action type and run the correct action
	-- inputState: The current state of the input (Enum.UserInputState.Begin, Enum.UserInputState.End, Enum.UserInputState.Change) Example is when the mouse starts moving it would be inputState.Change
	-- inputObject: This holds the Input mouse movement data in our case so Delta.X and Delta.Y. It can be used to rotate the camera horizontally and vertically.
	local function PlayerInput(actionName, inputState, inputObject)
		
		-- This just updates CameraAngleX based on how much the mouse had moved in that frame.
		-- A example for this is, if inputObject.Delta.X is 10, that means the mouse moved 10 on
		-- the X axis in one frame. So this code only uses half of that, so the camera
		-- would update by 5 instead. Using the full Delta.X would still work, but
		-- the sensitivity would be hard to cotrol.
		CameraAngleX -= (inputObject.Delta.X - inputObject.Delta.X * 0.5)
		
		-- This updates CameraAngleY based on how much the mouse moved in that frame.
		-- A example for this is, if inputObject.Delta.Y is 10, that means the mouse moved 10 on
		-- the Y axis in one frame. This code only uses half of that, so the camera
		-- would update by 5 instead. The main difference from CameraAngleX is that
		-- this one uses math.clamp so the player cannot look too far up or down. since if we let it would flip.
		CameraAngleY = math.clamp(CameraAngleY - inputObject.Delta.Y * 0.5, -80, 80)
	end

	-- Binds the PlayerInput function to mouse movement so the camera updates when the mouse moves.
	ContextActionService:BindAction("PlayerInput", PlayerInput, false, Enum.UserInputType.MouseMovement)
	
	--CAMERA MOVEMENT
	-- Connects a function to RenderStepped so it runs every frame and keeps
	-- updating the camera and the player direction while aiming.
	self.RenderConnection = RunService.RenderStepped:Connect(function()
		
		-- This will makes the starting CFrame from the HumanoidRootPart position.
		-- Then after that it rotates that CFrame using cameraAnglex for left and right and then
		-- ameraAngley for up and down. A example is, if cameraAnglex was 30, the
		-- camera would turn 30 degrees to the side from the starting direction
		local StartCframe = CFrame.new(HumanoidRootPart.CFrame.Position) * CFrame.Angles(0, math.rad(CameraAngleX), 0) * CFrame.Angles(math.rad(CameraAngleY), 0, 0)
	
		-- This will get the camera to where it should be placed by using the cameraOffset.
		-- For example because the offset is (2, 2, 8), the camera stays above,
		-- behind, and a little to the side of the player.
		local CameraCframe = StartCframe:PointToWorldSpace(CameraOffset)
		
		-- This will get the point the camera should look at. the -10000 is used so the
		-- camera keeps looking forward in the same direction
		local CameraFocus = StartCframe:PointToWorldSpace(Vector3.new(CameraOffset.X, CameraOffset.Y, -10000))

		-- This will set the actual camera CFrame by placing the camera at CameraCframe
		-- and making it look toward CameraFocus.
		self.Camera.CFrame = CFrame.lookAt(CameraCframe, CameraFocus)

		-- This will gets a point very far in front of where the camera is looking.
		local Looking = self.Camera.CFrame:PointToWorldSpace(Vector3.new(0,0,-10000))
		
		-- This will rotates the HumanoidRootPart so the player faces the same direction all the time when
		-- the camera is aiming, while still keepig the player at the same position.
		HumanoidRootPart.CFrame = CFrame.lookAt(HumanoidRootPart.Position, Vector3.new(Looking.X, HumanoidRootPart.Position.Y, Looking.Z))
	end)
end

-- This is what happens when the gun stops aiming.
-- first it unbinds the mouse movement action, disconnects the RenderStepped connection, then resets the camera back to normal, then resets the mouse behavior,
-- then sets the zoom and field of view back to normal, and then clears the mouse icon.
function Gun:StopAim()	--Method
	ContextActionService:UnbindAction("PlayerInput")

	if self.RenderConnection then
		self.RenderConnection:Disconnect()
		self.RenderConnection = nil
	end

	self.Camera.CameraType = Enum.CameraType.Custom
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	self.Player.CameraMinZoomDistance = 10
	self.Player.CameraMaxZoomDistance = 50
	self.Camera.FieldOfView = 70
	self.Mouse.Icon = ""
end

-- This is what happens when the gun gets equipped.
-- first It stores the weapon, then sets the gun to equipped, then starts the aim, then plays the hold animation, then plays the hold sound, then updates the ammo text, and then shows the ammo ui on the players screen.
function Gun:Equip(weapon: Instance)	--Method
	self.Weapon = weapon
	self.IsEquipped = true
	self:StartAim()
	self:PlayAnimation("Hold")
	self:PlaySound("Hold", self.Camera.CFrame.Position)
	self:UpdateAmmoText()
	self.Player.PlayerGui.Ammo.Ammotext.Visible = true
end

-- This is what happens when the gun gets unequipped.
-- first It hides the ammo ui, then stops the aim, then stops the hold animation, then and sets the gun back to unequipped.
function Gun:Unequip()	--Method
	self.Player.PlayerGui.Ammo.Ammotext.Visible = false
	self:StopAim()
	if self.HoldTrack then
		self.HoldTrack:Stop(0.1)
		self.HoldTrack = nil
	end
	self.IsEquipped = false
end

-- This is what happens when the gun shoots.
-- first it checks the fire cooldown, then makes sure the gun is not out of ammo, then check if it's not reloading, then it removes a bullet, 
-- then it updates the ammo ui text, then fires the shot to the server, then tracks the last shot time, then plays the animation and sound, then returns true.
function Gun:Shoot(mousePosition)	--Method
	local currentTime = time()
	if currentTime - self.LastShotTime < self.FireCooldown then
		return false
	end

	if self.Ammo <= 0 then
		print("No ammo!")
		self:UpdateAmmoText("No ammo!")
		return false
	end

	if self.IsReloading then
		return false
	end

	self.Ammo -= 1
	self:UpdateAmmoText()
	ShootRemote:FireServer(self.Weapon, self.Ammo, mousePosition, self.Damage, self.Range)
	self.LastShotTime = currentTime
	self:PlayAnimation("Shoot")
	if self.Weapon and self.Weapon:FindFirstChild("Handle") then
		self:PlaySound("Shoot", self.Weapon.Handle.Position)
	end
	return true
end

-- This is what happens when the gun reloads.
-- first it checks if the gun is already reloading or if the ammo is already full, then if it needs a reload it sets the gun to reloading, then updates the ammo ui text, 
-- then plays the reload animation and sound, then waits 3 seconds, then sets the ammo to full, then sets the gun to not reloading, then updates the ammo ui text, and then returns true.
function Gun:Reload()	--Method
	if self.IsReloading or self.Ammo >= self.MaxAmmo then
		if self.Ammo >= self.MaxAmmo then
			print("Ammo already full")
		end
		return false
	end

	self.IsReloading = true
	self:UpdateAmmoText("Reloading")
	self:PlayAnimation("Reload")
	self:PlaySound("Reload", self.Camera.CFrame.Position)
	task.spawn(function()
		task.wait(3)
		self.Ammo = self.MaxAmmo
		self.IsReloading = false
		self:UpdateAmmoText()
	end)
	return true
end

-- Makes the gun object from the gun class so we can use all the gun methods and properties from it.
local NewGun = Gun.New()

-- Starts the gun system and connects all the main gun events.
function Shared.Init()
	-- Make sure the player is fully loaded.
	Player:WaitForChild("Backpack")
	Player.Character:WaitForChild("Humanoid")
	Player.Character:WaitForChild("HumanoidRootPart")
	
	-- Defineing the gun.
	local Revolver = Player.Backpack:WaitForChild("Revolver")
	
	-- Event for when the gun is equiped.
	Revolver.Equipped:Connect(function()
		NewGun:Equip(Revolver)
	end)
	
	-- Event for when the gun is unequiped.
	Revolver.Unequipped:Connect(function()
		NewGun:Unequip()
	end)
	
	-- Event for when the gun is shot.
	Revolver.Activated:Connect(function()
		NewGun:Shoot(NewGun.Mouse.Hit.Position)
	end)
	
	-- Event for when the mouse is pressed.
	NewGun.Mouse.Button2Down:Connect(function()
		if NewGun.IsEquipped then
			NewGun.Camera.FieldOfView = 40
		end
	end)
	
	-- Event for when the mouse is going up.
	NewGun.Mouse.Button2Up:Connect(function()
		if NewGun.IsEquipped then
			NewGun.Camera.FieldOfView = 60
		end
	end)
	
	-- Event to play other players shoot sounds on this client.
	GunSoundRemote.OnClientEvent:Connect(function(shooter, position)
		if shooter == Player then
			return
		end

		NewGun:PlaySound("Shoot", position)
	end)
	
	-- Event to reload the gun when the player presses R.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.R and NewGun.IsEquipped then
			NewGun:Reload()
		end
	end)
end

--return modulescript
return Shared
