Garages = {}
local Points, Blips = {}, {}
local Current
local lastPrompt
local Km = {}
local interact
local TargetZones = {}

function Notify(key, ...)
    lib.notify({ description = L(key, ...), type = 'inform' })
end

function VehLabel(model)
    local hash = type(model) == 'number' and model or joaat(model or '')
    local label = GetLabelText(GetDisplayNameFromVehicleModel(hash))
    return label ~= 'NULL' and label or tostring(model)
end

-- Target resource in use (ox_target / qb-target), or nil to use the [E] prompt only.
local function targetResource()
    local mode, want = Config.Interaction.mode, Config.Interaction.target
    if mode ~= 'target' and mode ~= 'both' then return nil end
    if (want == 'ox_target' or want == 'qb-target') then
        return GetResourceState(want) == 'started' and want or nil
    end
    if GetResourceState('ox_target') == 'started' then return 'ox_target' end
    if GetResourceState('qb-target') == 'started' then return 'qb-target' end
end

-- The [E] prompt is used in 'prompt'/'both' mode, when no target resource is running, and
-- always while sitting in a vehicle (storing a vehicle is not a target interaction).
local function promptWanted(g)
    local mode = Config.Interaction.mode
    if mode == 'prompt' or mode == 'both' or not targetResource() then return true end
    return cache.vehicle and cache.seat == -1 and g.type ~= 'impound' and not g.forSale
end

local function promptFor(g)
    if g.forSale then return L('buy_garage', g.price or 0) end
    if g.interior and not (cache.vehicle and cache.seat == -1) then return L('enter_garage') end
    if g.type == 'impound' then return L('open_impound') end
    if cache.vehicle and cache.seat == -1 then return L('store_vehicle') end
    return L('open_garage')
end

local function makeBlip(g)
    if not g.blip then return end
    local b = AddBlipForCoord(g.coords.x, g.coords.y, g.coords.z)
    SetBlipSprite(b, g.blip.sprite or 357)
    SetBlipColour(b, g.forSale and 2 or g.blip.color or 3)
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
    local text = promptWanted(self.garage) and promptFor(self.garage) or nil
    if text ~= lastPrompt and not Open then
        lastPrompt = text
        if text then lib.showTextUI(text) else lib.hideTextUI() end
    end
end

local function targetKind(g)
    if g.forSale then return 'buy' end
    if g.type == 'impound' then return 'impound' end
    if g.interior then return 'interior' end
    return 'garage'
end

local function addTargetZone(g)
    local res = targetResource()
    if not res then return end
    local o = Config.Interaction.options[targetKind(g)]
    local radius, dist = g.radius or 3.0, Config.Interaction.distance
    if res == 'ox_target' then
        TargetZones[g.id] = { res = res, id = exports.ox_target:addSphereZone({
            coords = g.coords, radius = radius, debug = false,
            options = {{
                name = 'asg_' .. g.id, icon = o.icon, label = o.label, distance = dist,
                canInteract = function() return not cache.vehicle and not Open end,
                onSelect = function() interact(g) end,
            }},
        }) }
    else
        local name = 'asg_' .. g.id
        exports['qb-target']:AddCircleZone(name, g.coords, radius, { name = name, debugPoly = false, useZ = true }, {
            options = {{
                icon = o.icon, label = o.label,
                canInteract = function() return not cache.vehicle and not Open end,
                action = function() interact(g) end,
            }},
            distance = dist,
        })
        TargetZones[g.id] = { res = res, id = name }
    end
end

local function removeTargetZones()
    for _, z in pairs(TargetZones) do
        if z.res == 'ox_target' then pcall(function() exports.ox_target:removeZone(z.id) end)
        else pcall(function() exports['qb-target']:RemoveZone(z.id) end) end
    end
    TargetZones = {}
end

function RefreshGarages()
    local list = lib.callback.await('asg:getGarages', false) or {}
    for _, p in pairs(Points) do p:remove() end
    for _, b in pairs(Blips) do RemoveBlip(b) end
    removeTargetZones()
    Points, Blips, Garages, Current = {}, {}, {}, nil
    lib.hideTextUI()
    lastPrompt = nil

    for _, g in ipairs(list) do
        g.coords = vec3(g.coords.x, g.coords.y, g.coords.z)
        local spawns = {}
        for i, s in ipairs(g.spawns or {}) do spawns[i] = vec4(s.x, s.y, s.z, s.w) end
        g.spawns = spawns
        if g.preview then g.preview = vec4(g.preview.x, g.preview.y, g.preview.z, g.preview.w) end
        -- No preview point set? Show the preview car on the first bay so the 3D preview still works.
        if not g.preview and g.spawns[1] then g.preview = g.spawns[1] end
        if g.interior then
            local i = g.interior
            local bays = {}
            for n, b in ipairs(i.bays or {}) do bays[n] = vec4(b.x, b.y, b.z, b.w) end
            g.interior = { enter = vec4(i.enter.x, i.enter.y, i.enter.z, i.enter.w), exit = vec3(i.exit.x, i.exit.y, i.exit.z),
                           bays = bays, ipl = i.ipl, entitySets = i.entitySets }
        end
        Garages[g.id] = g
        addTargetZone(g)
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
    pcall(Config.Fuel.set, veh, p.props.fuelLevel or 100.0)
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
    local okFuel, fuel = pcall(Config.Fuel.get, veh)
    if okFuel and fuel then props.fuelLevel = fuel + 0.0 end
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

interact = function(g)
    if g.forSale then
        if not cache.vehicle then BuyGarage(g) end
    elseif g.interior and g.type ~= 'impound' and not cache.vehicle then
        EnterInterior(g)
    elseif g.type == 'impound' then
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
        if Current and not Open and promptWanted(Current) then
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

-- Buying a private / house garage that is for sale
function BuyGarage(g)
    local answer = lib.alertDialog({
        header = L('buy_garage_title'), content = L('buy_confirm', g.label, g.price or 0), centered = true, cancel = true,
    })
    if answer ~= 'confirm' then return end
    local ok, key, extra = lib.callback.await('asg:buy', false, g.id)
    if ok then
        Sfx('confirm')
        Notify('garage_bought', key)
    else
        Sfx('error')
        Notify(key or 'unavailable', extra)
    end
end

-- Another player wants to sell us a vehicle. Auto-declines after 30s.
lib.callback.register('asg:confirmSale', function(d)
    local answered = false
    CreateThread(function()
        Wait(30000)
        if not answered then pcall(lib.closeAlertDialog) end
    end)
    local answer = lib.alertDialog({
        header = L('sale_title'), content = L('sale_text', d.seller, VehLabel(d.model), d.plate, d.price),
        centered = true, cancel = true,
    })
    answered = true
    return answer == 'confirm'
end)
