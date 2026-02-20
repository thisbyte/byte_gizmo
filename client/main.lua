local gizmoActive = false
local responseData = nil
local mode = 'translate'
local cam = nil
local enableCam
local maxDistance
local maxCamDistance
local minY
local maxY
local movementSpeed
local stored
local hookedFunc
local promptTitle = _('Gizmo')
local promptSettings = {}

--- Export Handler
--- @param resourceName string
--- @param exportName string
--- @param fn function
local function ExportHandler(resourceName, exportName, fn)
    AddEventHandler(('__cfx_export_%s_%s'):format(resourceName, exportName), function(cb)
        cb(fn)
    end)
end

--- Initializes UI focus, camera, and other misc
--- @param bool boolean
local function Init(bool)
    local ped = PlayerPedId()
    if bool then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(true)

        if enableCam then
            local coords = GetGameplayCamCoord()
            local rot = GetGameplayCamRot(2)
            local fov = GetGameplayCamFov()

            cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

            SetCamCoord(cam, coords.x, coords.y, coords.z + 0.5)
            SetCamRot(cam, rot.x, rot.y, rot.z, 2)
            SetCamFov(cam, fov)
            RenderScriptCams(true, true, 500, true, true)
            FreezeEntityPosition(ped, true)
        end
        
        SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    else
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(IsNuiFocusKeepingInput())
        FreezeEntityPosition(ped, false)

        if cam then
            RenderScriptCams(false, true, 500, true, true)
            SetCamActive(cam, false)
            DetachCam(cam)
            DestroyCam(cam, true)
            cam = nil
        end

        stored = nil
        hookedFunc = nil
        
        SendNUIMessage({
            action = 'SetupGizmo',
            data = {
                handle = nil,
            }
        })
    end

    gizmoActive = bool
end

--- Disables controls, Radar, and Player Firing
function DisableControlsAndUI()
    DisableControlAction(0, 0x07CE1E61, true)
    HideHudAndRadarThisFrame()
    DisablePlayerFiring(U.Cache.PlayerId, true)
end

--- Get the normal value of a control(s) used for movement & rotation
--- @param control number | table
--- @return number
local function GetSmartControlNormal(control)
    if type(control) == 'table' then
        local normal1 = GetDisabledControlNormal(0, control[1])
        local normal2 = GetDisabledControlNormal(0, control[2])
        return normal1 - normal2
    end

    return GetDisabledControlNormal(0, control)
end

--- Handle camera rotations
local function Rotations()
    local newX
    local rAxisX = GetControlNormal(0, 0xA987235F)
    local rAxisY = GetControlNormal(0, 0xD2047988)

    local rot = GetCamRot(cam, 2)
    
    local yValue = rAxisY * 5
    local newZ = rot.z + (rAxisX * -10)
    local newXval = rot.x - yValue

    if (newXval >= minY) and (newXval <= maxY) then
        newX = newXval
    end

    if newX and newZ then
        SetCamRot(cam, vector3(newX, rot.y, newZ), 2)
    end
end

--- Handle camera movement
local function Movement()
    local x, y, z = table.unpack(GetCamCoord(cam))
    local rot = GetCamRot(cam, 2)

    local dx = math.sin(-rot.z * math.pi / 180) * movementSpeed
    local dy = math.cos(-rot.z * math.pi / 180) * movementSpeed
    local dz = math.tan(rot.x * math.pi / 180) * movementSpeed

    local dx2 = math.sin(math.floor(rot.z + 90.0) % 360 * -1.0 * math.pi / 180) * movementSpeed
    local dy2 = math.cos(math.floor(rot.z + 90.0) % 360 * -1.0 * math.pi / 180) * movementSpeed

    local moveX = GetSmartControlNormal(U.Keys['A_D']) -- Left & Right
    local moveY = GetSmartControlNormal(U.Keys['W_S']) -- Forward & Backward
    local moveZ = GetSmartControlNormal({U.Keys['Q'], U.Keys['E']}) -- Up & Down

    if moveX ~= 0.0 then
        x = x - dx2 * moveX
        y = y - dy2 * moveX
    end

    if moveY ~= 0.0 then
        x = x - dx * moveY
        y = y - dy * moveY
    end

    if moveZ ~= 0.0 then
        z = z + dz * moveZ
    end

    if #(GetEntityCoords(PlayerPedId()) - vec3(x, y, z)) <= maxCamDistance and (not hookedFunc or hookedFunc(vec3(x, y, z))) then
        SetCamCoord(cam, x, y, z)
    end
end

--- Hanndle camera controls (movement & rotation)
local function CamControls()
    Rotations()
    Movement()
end

--- Setup Gizmo
--- @param entity number
--- @param cfg table | nil
--- @param allowPlace function | nil
--- @return table | nil
function ToggleGizmo(entity, cfg, allowPlace)
    if not entity then return end

    if gizmoActive then
        Init(false)
    end

    enableCam = (cfg?.EnableCam == nil and Config.EnableCam) or cfg.EnableCam
    maxDistance = (cfg?.MaxDistance == nil and Config.MaxDistance) or cfg.MaxDistance
    maxCamDistance = (cfg?.MaxCamDistance == nil and Config.MaxCamDistance) or cfg.MaxCamDistance
    minY = (cfg?.MinY == nil and Config.MinY) or cfg.MinY
    maxY = (cfg?.MaxY == nil and Config.MaxY) or cfg.MaxY
    movementSpeed = (cfg?.MovementSpeed == nil and Config.MovementSpeed) or cfg.MovementSpeed
    mode = 'translate'
	
	promptTitle = (cfg?.Title == nil and _('Gizmo')) or cfg.Title
	
	promptSettings = {
		["translate"] = {
			["title"] = (cfg?.Prompts?.translate?.title == nil and _('rotate')) or cfg.Prompts.translate.title,
			["secondTitle"] = (cfg?.Prompts?.translate?.secondTitle == nil and _('translate')) or cfg.Prompts.translate.secondTitle,
			["button"] = (cfg?.Prompts?.translate?.button == nil and U.Keys[Config.Keybinds.ToggleMode]) or cfg.Prompts.translate.button,
			["enabled"] = true,
			["mode"] = (cfg?.Prompts?.translate?.mode == nil and "click") or cfg.Prompts.translate.mode,
			["options"] = (cfg?.Prompts?.translate?.options == nil and {tab = 0}) or cfg.Prompts.translate.options,
		},
		["snap"] = {
			["title"] = (cfg?.Prompts?.snap?.title == nil and _('Snap To Ground')) or cfg.Prompts.snap.title,
			["secondTitle"] = cfg?.Prompts?.snap?.secondTitle,
			["button"] = (cfg?.Prompts?.snap?.button == nil and U.Keys[Config.Keybinds.SnapToGround]) or cfg.Prompts.snap.button,
			["enabled"] = true,
			["mode"] = (cfg?.Prompts?.snap?.mode == nil and "click") or cfg.Prompts.snap.mode,
			["options"] = (cfg?.Prompts?.snap?.options == nil and {tab = 0}) or cfg.Prompts.snap.options,
		},
		["done"] = {
			["title"] = (cfg?.Prompts?.done?.title == nil and _('Done Editing')) or cfg.Prompts.done.title,
			["secondTitle"] = cfg?.Prompts?.done?.secondTitle,
			["button"] = (cfg?.Prompts?.done?.button == nil and U.Keys[Config.Keybinds.Finish]) or cfg.Prompts.done.button,
			["enabled"] = true,
			["mode"] = (cfg?.Prompts?.done?.mode == nil and "click") or cfg.Prompts.done.mode,
			["options"] = (cfg?.Prompts?.done?.options == nil and {tab = 0}) or cfg.Prompts.done.options,
		},
		["cancel"] = {
			["title"] = (cfg?.Prompts?.cancel?.title == nil and _('Cancel')) or cfg.Prompts.cancel.title,
			["secondTitle"] = cfg?.Prompts?.cancel?.secondTitle,
			["button"] = (cfg?.Prompts?.cancel?.button == nil and U.Keys[Config.Keybinds.Cancel]) or cfg.Prompts.cancel.button,
			["enabled"] = true,
			["mode"] = (cfg?.Prompts?.cancel?.mode == nil and "click") or cfg.Prompts.cancel.mode,
			["options"] = (cfg?.Prompts?.cancel?.options == nil and {tab = 0}) or cfg.Prompts.cancel.options,
		},
		["lr"] = {
			["title"] = (cfg?.Prompts?.lr?.title == nil and _('Move L/R')) or cfg.Prompts.lr.title,
			["secondTitle"] = cfg?.Prompts?.lr?.secondTitle,
			["button"] = (cfg?.Prompts?.lr?.button == nil and U.Keys['A_D']) or cfg.Prompts.lr.button,
			["enabled"] = (cam and true or false),
			["mode"] = (cfg?.Prompts?.lr?.mode == nil and "click") or cfg.Prompts.lr.mode,
			["options"] = (cfg?.Prompts?.lr?.options == nil and {tab = 0}) or cfg.Prompts.lr.options,
		},
		["fb"] = {
			["title"] = (cfg?.Prompts?.fb?.title == nil and _('Move F/B')) or cfg.Prompts.fb.title,
			["secondTitle"] = cfg?.Prompts?.fb?.secondTitle,
			["button"] = (cfg?.Prompts?.fb?.button == nil and U.Keys['W_S']) or cfg.Prompts.fb.button,
			["enabled"] = (cam and true or false),
			["mode"] = (cfg?.Prompts?.fb?.mode == nil and "click") or cfg.Prompts.fb.mode,
			["options"] = (cfg?.Prompts?.fb?.options == nil and {tab = 0}) or cfg.Prompts.fb.options,
		},
		["up"] = {
			["title"] = (cfg?.Prompts?.up?.title == nil and _('Move Up')) or cfg.Prompts.up.title,
			["secondTitle"] = cfg?.Prompts?.up?.secondTitle,
			["button"] = (cfg?.Prompts?.up?.button == nil and U.Keys['E']) or cfg.Prompts.up.button,
			["enabled"] = (cam and true or false),
			["mode"] = (cfg?.Prompts?.up?.mode == nil and "click") or cfg.Prompts.up.mode,
			["options"] = (cfg?.Prompts?.up?.options == nil and {tab = 0}) or cfg.Prompts.up.options,
		},
		["down"] = {
			["title"] = (cfg?.Prompts?.down?.title == nil and _('Move Down')) or cfg.Prompts.down.title,
			["secondTitle"] = cfg?.Prompts?.down?.secondTitle,
			["button"] = (cfg?.Prompts?.down?.button == nil and U.Keys['Q']) or cfg.Prompts.down.button,
			["enabled"] = (cam and true or false),
			["mode"] = (cfg?.Prompts?.down?.mode == nil and "click") or cfg.Prompts.down.mode,
			["options"] = (cfg?.Prompts?.down?.options == nil and {tab = 0}) or cfg.Prompts.down.options,
		},
	}
	
	if cfg?.Prompts?.custom and #cfg?.Prompts?.custom > 0 then
		for index, data in ipairs(cfg?.Prompts?.custom) do
			if data.title and data.button then
				local thisPrompt = {
					["title"] = data.title,
					["secondTitle"] = data.secondTitle,
					["button"] = data.button,
					["enabled"] = true,
					["mode"] = (data.mode == nil and "click") or data.mode,
					["options"] = (data.options == nil and {tab = 0}) or data.options,
					["action"] = data.action
				}
				promptSettings["custom_" .. index] = thisPrompt
			end
		end
	end

    stored = {
        coords = GetEntityCoords(entity),
        rotation = GetEntityRotation(entity)
    }

    hookedFunc = allowPlace

    SendNUIMessage({
        action = 'SetupGizmo',
        data = {
            handle = entity,
            position = stored.coords,
            rotation = stored.rotation,
            gizmoMode = mode
        }
    })

    Init(true)

    responseData = promise.new()

    CreateThread(function()
        while gizmoActive do
            Wait(0)
            SendNUIMessage({
                action = 'SetCameraPosition',
                data = {
                    position = GetFinalRenderedCamCoord(),
                    rotation = GetFinalRenderedCamRot(0)
                }
            })
        end
    end)

    CreateThread(function()
        while gizmoActive do
            Wait(0)
            DisableControlsAndUI()

            if cam then
                CamControls()
            end
        end
    end)

    CreateThread(function()
        local PromptGroup = U.Prompts:SetupPromptGroup()
        local TranslatePrompt = PromptGroup:RegisterPrompt(promptSettings["translate"].title, promptSettings["translate"].button, promptSettings["translate"].enabled, promptSettings["translate"].enabled, true, promptSettings["translate"].mode, promptSettings["translate"].options)
        local SnapToGroundPrompt = PromptGroup:RegisterPrompt(promptSettings["snap"].title, promptSettings["snap"].button, promptSettings["snap"].enabled, promptSettings["snap"].enabled, true, promptSettings["snap"].mode, promptSettings["snap"].options)
        local DonePrompt = PromptGroup:RegisterPrompt(promptSettings["done"].title, promptSettings["done"].button, promptSettings["done"].enabled, promptSettings["done"].enabled, true, promptSettings["done"].mode, promptSettings["done"].options)
        local CancelPrompt = PromptGroup:RegisterPrompt(promptSettings["cancel"].title, promptSettings["cancel"].button, promptSettings["cancel"].enabled, promptSettings["cancel"].enabled, true, promptSettings["cancel"].mode, promptSettings["cancel"].options)
        local LRPrompt = PromptGroup:RegisterPrompt(promptSettings["lr"].title, promptSettings["lr"].button, promptSettings["lr"].enabled, promptSettings["lr"].enabled, true, promptSettings["lr"].mode, promptSettings["lr"].options)
        local FBPrompt = PromptGroup:RegisterPrompt(promptSettings["fb"].title, promptSettings["fb"].button, promptSettings["fb"].enabled, promptSettings["fb"].enabled, true, promptSettings["fb"].mode, promptSettings["fb"].options)
        local UpPrompt = PromptGroup:RegisterPrompt(promptSettings["up"].title, promptSettings["up"].button, promptSettings["up"].enabled, promptSettings["up"].enabled, true, promptSettings["up"].mode, promptSettings["up"].options)
        local DownPrompt = PromptGroup:RegisterPrompt(promptSettings["down"].title, promptSettings["down"].button, promptSettings["down"].enabled, promptSettings["down"].enabled, true, promptSettings["down"].mode, promptSettings["down"].options)
		local CustomPrompts = {}
		if cfg?.Prompts?.custom and #cfg?.Prompts?.custom > 0 then
			for index, data in ipairs(cfg?.Prompts?.custom) do
				if data.title and data.button then
					local prompt = PromptGroup:RegisterPrompt(promptSettings["custom_" .. index].title, promptSettings["custom_" .. index].button, promptSettings["custom_" .. index].enabled, promptSettings["custom_" .. index].enabled, true, promptSettings["custom_" .. index].mode, promptSettings["custom_" .. index].options)
					table.insert(CustomPrompts, {["index"] = index, ["prompt"] = prompt})
				end
			end
		end
		

        while gizmoActive do
            Wait(5)
            PromptGroup:ShowGroup(promptTitle)

            if TranslatePrompt:HasCompleted() then
                mode = (mode == 'translate' and 'rotate' or 'translate')
                SendNUIMessage({
                    action = 'SetGizmoMode',
                    data = mode
                })

                TranslatePrompt:PromptText((mode == 'translate' and promptSettings["translate"].title) or promptSettings["translate"].secondTitle)
            end

            if SnapToGroundPrompt:HasCompleted() then
                PlaceObjectOnGroundProperly(entity)
				
                SendNUIMessage({
                    action = 'UpdateGizmo',
                    data = {
                        position = GetEntityCoords(entity),
                        rotation = GetEntityRotation(entity)
                    }
                })
            end

            if DonePrompt:HasCompleted() then
                local coords = GetEntityCoords(entity)
                responseData:resolve({
                    entity = entity,
                    coords = coords,
                    position = coords, -- Alias
                    rotation = GetEntityRotation(entity)
                })

                Init(false)
            end

            if CancelPrompt:HasCompleted() then

                responseData:resolve({
                    canceled = true,
                    entity = entity,
                    coords = stored.coords,
                    position = stored.coords, -- Alias
                    rotation = stored.rotation
                })

                SetEntityCoordsNoOffset(entity, stored.coords.x, stored.coords.y, stored.coords.z)
                SetEntityRotation(entity, stored.rotation.x, stored.rotation.y, stored.rotation.z)

                Init(false)

            end
			
			for key, data in pairs(CustomPrompts) do
				if data.prompt:HasCompleted() then
					local settings = promptSettings["custom_" .. data.index]
					if settings.action and settings.action.name and settings.action.type then
						if settings.action.type == "server_event" then
							TriggerServerEvent(settings.action.name)
						elseif settings.action.type == "client_event" then
							TriggerEvent(settings.action.name)
						elseif settings.action.type == "export" and settings.action.resource then
							exports[settings.action.resource][settings.action.name]()
						end
					end
				end
			end
        end

        TranslatePrompt:DeletePrompt()
        SnapToGroundPrompt:DeletePrompt()
        DonePrompt:DeletePrompt()
        LRPrompt:DeletePrompt()
        FBPrompt:DeletePrompt()
        UpPrompt:DeletePrompt()
        DownPrompt:DeletePrompt()
		for key, data in pairs(CustomPrompts) do
			data.prompt:DeletePrompt()
		end
    end)

    return Citizen.Await(responseData)
end

--- Register NUI Callback for updating entity position and rotation
--- @param data table
--- @param cb function
RegisterNUICallback('UpdateEntity', function(data, cb)
    local entity = data.handle
    local position = data.position
    local rotation = data.rotation

    if (maxDistance and #(vec3(position.x, position.y, position.z) - stored.coords) <= maxDistance) and (not hookedFunc or hookedFunc(position)) then
        SetEntityCoordsNoOffset(entity, position.x, position.y, position.z)
        SetEntityRotation(entity, rotation.x, rotation.y, rotation.z)
        return cb({status = 'ok'})
    end

    position = GetEntityCoords(entity)
    rotation = GetEntityRotation(entity)

    cb({
        status = 'Distance is too far',
        position = {x = position.x, y = position.y, z = position.z},
        rotation = {x = rotation.x, y = rotation.y, z = rotation.z}
    })
end)

--- If DevMode is enabled, register a command to spawn a crate for testing
if Config.DevMode then
RegisterCommand('gizmo', function()
    RequestModel('p_crate14x')

    while not HasModelLoaded('p_crate14x') do
        Wait(100)
    end

    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local forward = GetEntityForwardVector(ped)
    local offset = coords + (forward * 3)
    local entity = CreateObject(joaat('p_crate14x'), offset.x, offset.y, offset.z, true, true, true)

    while not DoesEntityExist(entity) do 
        Wait(100) 
    end

    local data = ToggleGizmo(entity)

    print(json.encode(data, {indent = true}))

    if entity then
        DeleteEntity(entity)
    end
end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource == U.Cache.Resource then
        Init(false)
    end
end)

--- Export ToggleGizmo function
--- @usage exports.byte_gizmo:Toggle(entity, {}, function(position) return true end)
exports('Toggle', ToggleGizmo)

--- Export Handler for https://github.com/GlitchOo/gs_gizmo
ExportHandler('gs_gizmo', 'Toggle', ToggleGizmo)
--- Export Handler for https://github.com/outsider31000/object_gizmo/tree/main
ExportHandler('object_gizmo', 'useGizmo', ToggleGizmo)