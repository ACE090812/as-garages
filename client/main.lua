Garages = {}
local Points, Blips = {}, {}
local Current
local lastPrompt
local Km = {}

function Notify(key, ...)
    lib.notify({ description = L(key, ...), type = 'inform' })
end

function VehLabel(model)
    local hash = type(model) == 'number' and model or joaat(model or '')
    local label = GetLabelText(GetDisplayNameFromVehicleModel(hash))
    return label ~= 'NULL' and label or tostring(model)
end

local function promptFor(g)
    if g.type == 'impound' then return L('open_impound') end
    if cache.vehicle and cache.seat == -1 then return L('store_vehicle') end
    return L('open_garage')
end

local function makeBlip(g)
    if not g.blip then return end
    local b = AddBlipForCoord(g.coords.x, g.coords.y, g.coords.z)
    SetBlipSprite(b, g.blip.sprite or 357)
    SetBlipColour(b, g.blip.color or 3)
    SetBlipScale(b, g.blip.scale or 0.7)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(g.label)
    EndTextCommandSetBlipName(b)
    return b
end

local function onEnter(self)
    Current = self.garage
end

local function onExit(self)
    if Current == self.garage then Current = nil end
    lastPrompt = nil
    lib.hideTextUI()
end

local function nearby(self)
    local c = self.garage.coords
    DrawMarker(27, c.x, c.y, c.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.6, 1.6, 0.5,
        165, 148, 255, 150, false, false, 2, false, nil, nil, false)
    local text = promptFor(self.garage)
    if text ~= lastPrompt and not Open then
        lastPrompt = text
        lib.showTextUI(text)
    end
end

function RefreshGarages()
    local list = lib.callback.await('asg:getGarages', false) or {}
    for _, p in pairs(Points) do p:remove() end
    for _, b in pairs(Blips) do RemoveBlip(b) end
    Points, Blips, Garages, Current = {}, {}, {}, nil
    lib.hideTextUI()
    lastPrompt = nil

    for _, g in ipairs(list) do
        g.coords = vec3(g.coords.x, g.coords.y, g.coords.z)
        local spawns = {}
        for i, s in ipairs(g.spawns or {}) do spawns[i] = vec4(s.x, s.y, s.z, s.w) end
        g.spawns = spawns
        if g.preview then g.preview = vec4(g.preview.x, g.preview.y, g.preview.z, g.preview.w) end
        Garages[g.id] = g
        Blips[g.id] = makeBlip(g)
        Points[g.id] = lib.points.new({
            coords = g.coords, distance = (g.radius or 3.0) + 1.0, garage = g,
            onEnter = onEnter, onExit = onExit, nearby = nearby,
        })
    end
end

local function findBay(g)
    for i, s in ipairs(g.spawns) do
        if not IsAnyVehicleNearPoint(s.x, s.y, s.z, 2.5) then return i end
    end
end
FindBay = findBay

-- Server has already reserved the plate; build the vehicle, then tell the server its netId.
function SpawnVehicle(p)
    local plate = p.plate
    local function fail()
        lib.callback.await('asg:spawnFailed', false, plate)
        Notify('spawn_failed')
    end

    local model = type(p.model) == 'number' and p.model or joaat(p.model or '')
    if not IsModelInCdimage(model) or not pcall(lib.requestModel, model, 10000) then return fail() end

    local sp = p.spawn
    local veh = CreateVehicle(model, sp.x, sp.y, sp.z, sp.w, true, true)
    local t = GetGameTimer()
    while not DoesEntityExist(veh) and GetGameTimer() - t < 5000 do Wait(0) end
    if not DoesEntityExist(veh) then return fail() end

    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    lib.setVehicleProperties(veh, p.props)
    SetModelAsNoLongerNeeded(model)
    if Config.WarpIntoVehicle then TaskWarpPedIntoVehicle(cache.ped, veh, -1) end
    Config.GiveKeys(veh, plate)
    lib.callback.await('asg:spawned', false, plate, NetworkGetNetworkIdFromEntity(veh))
    return veh
end

local function storeVehicle(g)
    local veh = cache.vehicle
    if not veh or cache.seat ~= -1 then return end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local props = lib.getVehicleProperties(veh)
    local km = Km[veh] or 0

    TaskLeaveVehicle(cache.ped, veh, 0)
    local t = GetGameTimer()
    while IsPedInVehicle(cache.ped, veh, false) and GetGameTimer() - t < 4000 do Wait(50) end

    local ok, res = lib.callback.await('asg:store', false, g.id, netId, props, km)
    if ok then
        Km[veh] = nil
        Notify('stored', VehLabel(props.model))
    else
        Notify(res or 'unavailable')
    end
end

local function interact(g)
    if g.type == 'impound' then
        if not cache.vehicle then OpenGarage(g) end
    elseif cache.vehicle and cache.seat == -1 then
        storeVehicle(g)
    elseif not cache.vehicle then
        OpenGarage(g)
    end
end

lib.addKeybind({
    name = 'asg_interact',
    description = 'Garage: open / store',
    defaultKey = 'E',
    onPressed = function()
        if Current and not Open then
            lib.hideTextUI()
            lastPrompt = nil
            interact(Current)
        end
    end,
})

-- Mileage: distance driven since the vehicle was last stored, reported when it is stored.
CreateThread(function()
    while true do
        Wait(2000)
        local veh = cache.vehicle
        if veh and cache.seat == -1 then
            Km[veh] = (Km[veh] or 0) + (GetEntitySpeed(veh) * 2) / 1000.0
        end
    end
end)

CreateThread(function()
    Wait(2000)
    RefreshGarages()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in pairs(Blips) do RemoveBlip(b) end
    lib.hideTextUI()
end)

-- /impound: the officer's form for the nearest vehicle
RegisterCommand('impound', function()
    if Open then return end
    if not lib.callback.await('asg:canImpound', false) then return Notify('not_allowed') end

    local veh = cache.vehicle
    if not veh then veh = lib.getClosestVehicle(GetEntityCoords(cache.ped), 6.0, false) end
    if not veh or veh == 0 then return Notify('no_vehicle_near') end
    if cache.vehicle then
        TaskLeaveVehicle(cache.ped, veh, 0)
        Wait(1500)
    end
    OpenOfficer(veh)
end, false)

-- /asgarage helpers (admin)
RegisterNetEvent('asg:admin:create', function()
    local input = lib.inputDialog('New garage', {
        { type = 'input', label = 'Id (letters, numbers, _)', required = true },
        { type = 'input', label = 'Label', required = true },
        { type = 'input', label = 'Subtitle' },
        { type = 'select', label = 'Type', required = true, default = 'public', options = {
            { value = 'public', label = 'Public' }, { value = 'job', label = 'Job' },
            { value = 'gang', label = 'Gang' }, { value = 'impound', label = 'Impound lot' } } },
        { type = 'input', label = 'Job or gang name (job/gang types)' },
        { type = 'number', label = 'Slots', default = 10, min = 1, max = 200 },
    })
    if not input then return end
    local c = GetEntityCoords(cache.ped)
    local ok, msg = lib.callback.await('asg:admin:save', false,
        { id = input[1], label = input[2], sub = input[3], type = input[4], group = input[5], slots = input[6] },
        { x = c.x, y = c.y, z = c.z })
    lib.notify({ description = msg or (ok and 'Saved.' or 'Failed.'), type = ok and 'success' or 'error' })
end)

RegisterNetEvent('asg:admin:capture', function(action, id)
    local c, h = GetEntityCoords(cache.ped), GetEntityHeading(cache.ped)
    -- If sitting in a vehicle, use the vehicle's position and heading (what a bay should match).
    if cache.vehicle then c, h = GetEntityCoords(cache.vehicle), GetEntityHeading(cache.vehicle) end
    local ok, msg = lib.callback.await('asg:admin:point', false, action, id, { x = c.x, y = c.y, z = c.z, w = h })
    lib.notify({ description = ok and ('Saved %s for %s.'):format(action, id) or msg, type = ok and 'success' or 'error' })
end)
