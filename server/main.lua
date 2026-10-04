Garages = {}   -- id -> normalised garage
Spawned = {}   -- plate -> { netId, src, garage, misses }
Pending = {}   -- plate -> { src, prev, garage, paid }
local Locks = {}

local function vec3From(c) return vec3(c.x, c.y, c.z) end
local function vec4From(c) return vec4(c.x, c.y, c.z, c.w or c.h or 0.0) end

function Normalise(g)
    g.coords = vec3From(g.coords)
    g.radius = g.radius or 3.0
    g.slots = g.slots or 10
    g.type = g.type or 'public'
    local spawns = {}
    for _, s in ipairs(g.spawns or {}) do spawns[#spawns + 1] = vec4From(s) end
    g.spawns = spawns
    if g.preview then g.preview = vec4From(g.preview) end
    return g
end

function LoadGarages()
    Garages = {}
    for _, g in ipairs(Config.Garages) do
        g.static = true
        Garages[g.id] = Normalise(g)
    end
    local rows = MySQL.query.await('SELECT id, data FROM as_garage_locations')
    for _, r in ipairs(rows or {}) do
        local ok, g = pcall(json.decode, r.data)
        if ok and type(g) == 'table' then
            g.id = r.id
            Garages[g.id] = Normalise(g)
        end
    end
end

-- What a given player may see: public + impound always, job/gang only with the right group.
function CanUse(p, g)
    if g.type == 'public' or g.type == 'impound' then return true end
    if g.type == 'job' then return Bridge.hasGroup(p.job, p.grade, g.jobs) end
    if g.type == 'gang' then return Bridge.hasGroup(p.gang, p.gangGrade, g.gangs) end
    return false
end

function InRange(src, g)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - g.coords) <= (g.radius + 12.0)
end

function Log(title, desc)
    Debug(title, desc)
    if Config.Webhook == '' then return end
    PerformHttpRequest(Config.Webhook, function() end, 'POST', json.encode({
        username = 'AS Garages',
        embeds = {{ title = title, description = desc, color = 10855935,
                    footer = { text = os.date('%Y-%m-%d %H:%M:%S') } }},
    }), { ['Content-Type'] = 'application/json' })
end

local function setup()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `as_garage_vehicles` (
        `plate` VARCHAR(12) NOT NULL, `garage` VARCHAR(64) NOT NULL, `state` TINYINT NOT NULL DEFAULT 1,
        `fuel` TINYINT UNSIGNED NOT NULL DEFAULT 100, `engine` TINYINT UNSIGNED NOT NULL DEFAULT 100,
        `body` TINYINT UNSIGNED NOT NULL DEFAULT 100, `mileage` DOUBLE NOT NULL DEFAULT 0,
        `fav` TINYINT NOT NULL DEFAULT 0, `stored_at` BIGINT NOT NULL DEFAULT 0,
        `impound_reason` VARCHAR(255) NULL, `impound_by` VARCHAR(100) NULL,
        `impound_fee` INT NOT NULL DEFAULT 0, `impound_at` BIGINT NOT NULL DEFAULT 0,
        `impound_until` BIGINT NOT NULL DEFAULT 0, `owner_release` TINYINT NOT NULL DEFAULT 1,
        PRIMARY KEY (`plate`), KEY `garage_state` (`garage`, `state`))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `as_garage_locations` (
        `id` VARCHAR(64) NOT NULL, `data` LONGTEXT NOT NULL, PRIMARY KEY (`id`))]])
    LoadGarages()

    -- Anything still marked "out" at startup was lost with the previous server session.
    if Config.StuckBehaviour == 'impound' then
        MySQL.update.await([[UPDATE as_garage_vehicles SET state = 2, garage = ?, impound_reason = ?,
            impound_by = 'System', impound_fee = ?, impound_at = ?, impound_until = 0, owner_release = 1
            WHERE state = 0]], { Config.DefaultImpound, L('stuck_reason'), Config.StuckImpoundFee, os.time() })
    else
        MySQL.update.await('UPDATE as_garage_vehicles SET state = 1 WHERE state = 0')
    end
end

CreateThread(function()
    if not Bridge.waitReady() then return end
    setup()
end)

-- Garages visible to this player. Clients call this on load and when their job changes.
lib.callback.register('asg:getGarages', function(src)
    local p = Bridge.getPlayer(src)
    if not p then return {} end
    local out = {}
    for _, g in pairs(Garages) do
        if CanUse(p, g) then
            out[#out + 1] = {
                id = g.id, label = g.label, sub = g.sub, type = g.type, radius = g.radius, slots = g.slots,
                coords = { x = g.coords.x, y = g.coords.y, z = g.coords.z },
                spawns = g.spawns, preview = g.preview, blip = g.blip,
            }
        end
    end
    return out
end)

local function statusFor(row, g)
    if row.state == 2 then return 'imp' end
    if row.state == 0 then return 'out' end
    return row.garage == g.id and 'in' or 'away'
end

local function listVehicles(p, g)
    local owned = {}
    if g.shared then
        local rows = MySQL.query.await('SELECT plate FROM as_garage_vehicles WHERE garage = ? AND state = 1', { g.id })
        for _, r in ipairs(rows or {}) do
            local v = Bridge.getVehicle(r.plate)
            if v then owned[#owned + 1] = v end
        end
    else
        owned = Bridge.getOwned(p.id)
    end
    if #owned == 0 then return {} end

    local plates = {}
    for i, v in ipairs(owned) do plates[i] = v.plate end
    local rows = MySQL.query.await('SELECT * FROM as_garage_vehicles WHERE plate IN (?)', { plates })
    local byPlate = {}
    for _, r in ipairs(rows or {}) do byPlate[r.plate] = r end

    local out = {}
    for _, v in ipairs(owned) do
        local row = byPlate[v.plate]
        if not row then
            -- first time we see this vehicle: assume it is parked in the default garage
            local props = v.props
            row = { plate = v.plate, garage = Config.DefaultGarage, state = 1, mileage = 0, fav = 0, stored_at = 0,
                    fuel = math.floor(props.fuelLevel or 100), engine = math.floor((props.engineHealth or 1000) / 10),
                    body = math.floor((props.bodyHealth or 1000) / 10) }
            MySQL.insert('INSERT IGNORE INTO as_garage_vehicles (plate, garage, state, fuel, engine, body) VALUES (?, ?, 1, ?, ?, ?)',
                { v.plate, row.garage, row.fuel, row.engine, row.body })
        end
        local at = row.garage ~= g.id and Garages[row.garage]
        out[#out + 1] = {
            plate = v.plate, model = v.model, status = statusFor(row, g), at = at and at.label or nil,
            fuel = row.fuel, eng = row.engine, body = row.body, km = math.floor(row.mileage or 0),
            storedAt = row.stored_at, fav = row.fav == 1,
        }
    end
    return out
end

local function storageFee(row)
    if not row.impound_at or row.impound_at == 0 then return 0, 0 end
    local days = math.floor((os.time() - row.impound_at) / 86400)
    days = math.min(math.max(days, 0), Config.MaxStorageDays)
    return days * Config.StoragePerDay, days
end

local function listImpounded(p, g, officer)
    local rows
    if officer then
        rows = MySQL.query.await('SELECT * FROM as_garage_vehicles WHERE state = 2 ORDER BY impound_at DESC LIMIT 100')
    else
        local owned = Bridge.getOwned(p.id)
        if #owned == 0 then return {} end
        local plates = {}
        for i, v in ipairs(owned) do plates[i] = v.plate end
        rows = MySQL.query.await('SELECT * FROM as_garage_vehicles WHERE state = 2 AND plate IN (?)', { plates })
    end
    local out = {}
    for _, row in ipairs(rows or {}) do
        local v = Bridge.getVehicle(row.plate)
        if v then
            local storage, days = storageFee(row)
            out[#out + 1] = {
                plate = row.plate, model = v.model, status = 'imp', fuel = row.fuel, eng = row.engine, body = row.body,
                km = math.floor(row.mileage or 0), storedAt = row.impound_at, fav = false,
                imp = { reason = row.impound_reason, by = row.impound_by, at = row.impound_at, until_ = row.impound_until,
                        fee = row.impound_fee, storage = storage, days = days, ownerRelease = row.owner_release == 1 },
            }
        end
    end
    return out
end

local function isOfficer(p)
    return p ~= nil and Bridge.hasGroup(p.job, p.grade, Config.ImpoundJobs)
end
IsOfficer = isOfficer

lib.callback.register('asg:getGarage', function(src, id)
    local g = Garages[id]
    local p = Bridge.getPlayer(src)
    if not g or not p or not InRange(src, g) or not CanUse(p, g) then return nil end

    local data = {
        garage = { id = g.id, label = g.label, sub = g.sub, type = g.type, slots = g.slots },
        now = os.time(),
    }
    if g.type == 'impound' then
        local officer = isOfficer(p)
        data.vehicles = listImpounded(p, g, officer)
        data.officer = officer
        data.tab = 'impound'
    else
        data.vehicles = listVehicles(p, g)
        data.tab = g.type == 'public' and 'mine' or g.type
        data.garage.used = MySQL.scalar.await('SELECT COUNT(*) FROM as_garage_vehicles WHERE garage = ? AND state = 1', { g.id }) or 0
    end
    return data
end)

-- Vehicle leaves the garage. The row is flipped atomically before anything spawns, so two
-- players (or one player spamming) can never pull the same plate out twice.
local function reserve(src, plate, prev, garage, paid)
    Pending[plate] = { src = src, prev = prev, garage = garage, paid = paid }
    SetTimeout(20000, function()
        local pend = Pending[plate]
        if pend and pend.src == src then
            Pending[plate] = nil
            MySQL.update('UPDATE as_garage_vehicles SET state = ? WHERE plate = ? AND state = 0', { pend.prev, plate })
            if pend.paid and pend.paid > 0 then Bridge.refund(src, pend.paid, 'as-garages refund') end
        end
    end)
end
Reserve = reserve

lib.callback.register('asg:takeOut', function(src, garageId, plate, bay)
    local g = Garages[garageId]
    local p = Bridge.getPlayer(src)
    if not g or not p or g.type == 'impound' then return false, 'unavailable' end
    if not InRange(src, g) then return false, 'too_far' end
    if not CanUse(p, g) then return false, 'no_access' end
    plate = NormPlate(plate)
    local spawn = g.spawns[tonumber(bay) or 0]
    if not spawn then return false, 'unavailable' end
    if Locks[plate] or Pending[plate] then return false, 'unavailable' end

    local v = Bridge.getVehicle(plate)
    if not v then return false, 'unavailable' end
    if not g.shared and v.owner ~= p.id then return false, 'not_owner' end

    Locks[plate] = true
    local flipped = MySQL.update.await('UPDATE as_garage_vehicles SET state = 0 WHERE plate = ? AND state = 1 AND garage = ?', { plate, g.id })
    Locks[plate] = nil
    if flipped ~= 1 then return false, 'unavailable' end

    Bridge.setNative(plate, false, g.id)
    reserve(src, plate, 1, g.id)
    Log('Vehicle taken out', ('%s (%s) took %s from %s'):format(p.name, p.id, plate, g.label))
    return true, { model = v.model, props = v.props, spawn = spawn, plate = plate }
end)

lib.callback.register('asg:spawned', function(src, plate, netId)
    plate = NormPlate(plate)
    local pend = Pending[plate]
    if not pend or pend.src ~= src then return false end
    Pending[plate] = nil
    Spawned[plate] = { netId = netId, src = src, garage = pend.garage, misses = 0 }
    return true
end)

lib.callback.register('asg:spawnFailed', function(src, plate)
    plate = NormPlate(plate)
    local pend = Pending[plate]
    if not pend or pend.src ~= src then return false end
    Pending[plate] = nil
    MySQL.update.await('UPDATE as_garage_vehicles SET state = ? WHERE plate = ? AND state = 0', { pend.prev, plate })
    if pend.prev == 1 then Bridge.setNative(plate, true, pend.garage) end
    if pend.paid and pend.paid > 0 then Bridge.refund(src, pend.paid, 'as-garages refund') end
    return true
end)

local function sanitiseProps(props, rawPlate)
    if type(props) ~= 'table' then return nil end
    props.plate = rawPlate
    return props
end

lib.callback.register('asg:store', function(src, garageId, netId, props, km)
    local g = Garages[garageId]
    local p = Bridge.getPlayer(src)
    if not g or not p or g.type == 'impound' then return false, 'no_access' end
    if not InRange(src, g) then return false, 'too_far' end
    if not CanUse(p, g) then return false, 'no_access' end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false, 'unavailable' end
    if #(GetEntityCoords(entity) - g.coords) > g.radius + 20.0 then return false, 'too_far' end

    local rawPlate = GetVehicleNumberPlateText(entity)
    local plate = NormPlate(rawPlate)
    if Locks[plate] then return false, 'unavailable' end

    local v = Bridge.getVehicle(plate)
    if not v then return false, 'invalid_vehicle' end
    if not g.shared and v.owner ~= p.id then return false, 'not_owner' end

    Locks[plate] = true
    local row = MySQL.single.await('SELECT state, garage FROM as_garage_vehicles WHERE plate = ?', { plate })
    if row and row.state == 2 then Locks[plate] = nil return false, 'unavailable' end
    if not (row and row.state == 1 and row.garage == g.id) then
        local used = MySQL.scalar.await('SELECT COUNT(*) FROM as_garage_vehicles WHERE garage = ? AND state = 1', { g.id }) or 0
        if used >= g.slots then Locks[plate] = nil return false, 'garage_full' end
    end

    props = sanitiseProps(props, rawPlate)
    if props then
        props.model = props.model or v.model
        Bridge.saveProps(plate, props)
    end
    props = props or v.props
    km = math.min(math.max(tonumber(km) or 0, 0), 500)

    MySQL.update.await([[INSERT INTO as_garage_vehicles (plate, garage, state, fuel, engine, body, mileage, stored_at)
        VALUES (?, ?, 1, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE garage = VALUES(garage), state = 1, fuel = VALUES(fuel), engine = VALUES(engine),
        body = VALUES(body), mileage = mileage + VALUES(mileage), stored_at = VALUES(stored_at)]], {
        plate, g.id,
        math.min(100, math.max(0, math.floor(props.fuelLevel or 100))),
        math.min(100, math.max(0, math.floor((props.engineHealth or 1000) / 10))),
        math.min(100, math.max(0, math.floor((props.bodyHealth or 1000) / 10))),
        km, os.time(),
    })
    Bridge.setNative(plate, true, g.id)
    Spawned[plate] = nil
    DeleteEntity(entity)
    Locks[plate] = nil
    Log('Vehicle stored', ('%s (%s) stored %s in %s'):format(p.name, p.id, plate, g.label))
    return true, plate
end)

lib.callback.register('asg:fav', function(src, plate)
    local p = Bridge.getPlayer(src)
    plate = NormPlate(plate)
    local v = p and Bridge.getVehicle(plate)
    if not v or v.owner ~= p.id then return false end
    MySQL.update.await('UPDATE as_garage_vehicles SET fav = 1 - fav WHERE plate = ?', { plate })
    return true
end)

lib.callback.register('asg:locate', function(src, plate)
    local p = Bridge.getPlayer(src)
    plate = NormPlate(plate)
    local v = p and Bridge.getVehicle(plate)
    if not v or v.owner ~= p.id then return nil end
    local s = Spawned[plate]
    local entity = s and NetworkGetEntityFromNetworkId(s.netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    local c = GetEntityCoords(entity)
    return { x = c.x, y = c.y }
end)

-- Vehicles that vanish (culled, deleted, crashed out of the world) are treated as lost.
function MarkLost(plate)
    local s = Spawned[plate]
    Spawned[plate] = nil
    if Config.StuckBehaviour == 'impound' then
        MySQL.update([[UPDATE as_garage_vehicles SET state = 2, garage = ?, impound_reason = ?, impound_by = 'System',
            impound_fee = ?, impound_at = ?, impound_until = 0, owner_release = 1 WHERE plate = ? AND state = 0]],
            { Config.DefaultImpound, L('stuck_reason'), Config.StuckImpoundFee, os.time(), plate })
    else
        MySQL.update('UPDATE as_garage_vehicles SET state = 1 WHERE plate = ? AND state = 0', { plate })
        Bridge.setNative(plate, true, s and s.garage or Config.DefaultGarage)
    end
    Log('Vehicle lost', plate .. ' no longer exists in the world')
end

CreateThread(function()
    while true do
        Wait(30000)
        if Config.WatchSpawned then
            for plate, s in pairs(Spawned) do
                local e = NetworkGetEntityFromNetworkId(s.netId)
                if not e or e == 0 or not DoesEntityExist(e) then
                    s.misses = s.misses + 1
                    if s.misses >= 2 then MarkLost(plate) end
                else
                    s.misses = 0
                end
            end
        end
    end
end)
