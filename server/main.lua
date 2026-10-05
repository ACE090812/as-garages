Garages = {}      -- id -> normalised garage
TempGarages = {}  -- id -> garage registered by other resources at runtime (not saved)
Spawned = {}      -- plate -> { netId, src, garage, misses, idleSince }
Pending = {}      -- plate -> { src, prev, garage, paid }
Locks = {}        -- plate -> true while a state change is in flight
Access = {}       -- private garage id -> { [identifier] = true }
Inside = {}       -- player source -> garage id, while inside a walk-in interior

local function vec3From(c) return vec3(c.x, c.y, c.z) end
local function vec4From(c) return vec4(c.x, c.y, c.z, c.w or c.h or 0.0) end
local function plain3(v) return { x = v.x, y = v.y, z = v.z } end
local function plain4(v) return { x = v.x, y = v.y, z = v.z, w = v.w } end

-- Vehicle classes a garage can accept. Chips in the admin editor use these keys.
local CLASS_TYPES = {
    cars = { 'automobile', 'quadbike' }, bikes = { 'bike' },
    boats = { 'boat', 'submarine' }, air = { 'heli', 'plane', 'blimp' },
}

-- Total slots: base + purchased upgrades.
function Slots(g) return (g.slots or 10) + (g.extra or 0) end

function Normalise(g)
    g.coords = vec3From(g.coords)
    g.radius = g.radius or 3.0
    g.slots = g.slots or 10
    g.type = g.type or 'public'
    if g.type == 'private' then g.shared = true end
    local spawns = {}
    for _, s in ipairs(g.spawns or {}) do spawns[#spawns + 1] = vec4From(s) end
    g.spawns = spawns
    if g.preview then g.preview = vec4From(g.preview) end
    g.allowed = nil
    if g.vehicleClasses and #g.vehicleClasses > 0 then
        g.allowed = {}
        for _, key in ipairs(g.vehicleClasses) do
            for _, t in ipairs(CLASS_TYPES[key] or {}) do g.allowed[t] = true end
        end
    end
    -- Walk-in interior: { enter = vec4, exit = vec3, bays = { vec4... }, ipl?, entitySets? }
    if g.interior and g.interior.enter then
        local i = g.interior
        local bays = {}
        for _, b in ipairs(i.bays or {}) do bays[#bays + 1] = vec4From(b) end
        g.interior = { enter = vec4From(i.enter), exit = vec3From(i.exit or i.enter), bays = bays,
                       ipl = i.ipl, entitySets = i.entitySets }
    else
        g.interior = nil
    end
    return g
end

function LoadGarages()
    Garages = {}
    for _, g in ipairs(Config.Garages) do
        g.inConfig = true
        Garages[g.id] = Normalise(g)
    end
    local rows = MySQL.query.await('SELECT id, data FROM as_garage_locations')
    for _, r in ipairs(rows or {}) do
        local ok, g = pcall(json.decode, r.data)
        if ok and type(g) == 'table' then
            g.id = r.id
            g.override = true
            g.inConfig = Garages[g.id] ~= nil
            Garages[g.id] = Normalise(g)
        end
    end
    for id, g in pairs(TempGarages) do Garages[id] = g end
end

function LoadAccess()
    Access = {}
    local rows = MySQL.query.await('SELECT garage, identifier FROM as_garage_access')
    for _, r in ipairs(rows or {}) do
        Access[r.garage] = Access[r.garage] or {}
        Access[r.garage][r.identifier] = true
    end
    for id, g in pairs(TempGarages) do Access[id] = g.members or {} end
end

-- Can this player use the garage right now?
function CanUse(p, g)
    if g.type == 'public' or g.type == 'impound' then return true end
    if g.type == 'job' then return Bridge.hasGroup(p.job, p.grade, g.jobs) end
    if g.type == 'gang' then return Bridge.hasGroup(p.gang, p.gangGrade, g.gangs) end
    if g.type == 'private' then
        if not g.owner then return false end
        return g.owner == p.id or (Access[g.id] ~= nil and Access[g.id][p.id] == true)
    end
    return false
end

function IsForSale(g) return g.type == 'private' and not g.owner and not g.temp end

function InRange(src, g)
    if Inside[src] == g.id then return true end
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - g.coords) <= (g.radius + 12.0)
end

-- Plain table safe to send to clients / save as JSON.
function Plain(g, forAdmin)
    local out = {
        id = g.id, label = g.label, sub = g.sub, type = g.type, radius = g.radius, slots = Slots(g), baseSlots = g.slots,
        coords = plain3(g.coords), spawns = {}, blip = g.blip or nil, price = g.price, forSale = IsForSale(g) or nil,
        extra = g.extra, temp = g.temp,
    }
    for i, s in ipairs(g.spawns) do out.spawns[i] = plain4(s) end
    if g.preview then out.preview = plain4(g.preview) end
    if g.interior then
        out.interior = { enter = plain4(g.interior.enter), exit = plain3(g.interior.exit), bays = {},
                         ipl = g.interior.ipl, entitySets = g.interior.entitySets }
        for i, b in ipairs(g.interior.bays) do out.interior.bays[i] = plain4(b) end
    end
    if forAdmin then
        out.shared, out.jobs, out.gangs = g.shared, g.jobs, g.gangs
        out.vehicleClasses = g.vehicleClasses or {}
        out.owner, out.ownerName = g.owner, g.ownerName
        out.inConfig, out.override = g.inConfig or false, g.override or false
        out.blipOn = g.blip ~= nil and g.blip ~= false
    end
    return out
end

function PersistGarage(g)
    if g.temp then return end
    local data = Plain(g, true)
    data.id, data.inConfig, data.override, data.blipOn, data.forSale, data.baseSlots, data.temp = nil, nil, nil, nil, nil, nil, nil
    data.slots = g.slots -- base slots; purchased upgrades are kept in `extra`
    MySQL.update.await('INSERT INTO as_garage_locations (id, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
        { g.id, json.encode(data) })
end

function RefreshAll()
    LoadGarages()
    TriggerClientEvent('asg:refresh', -1)
end

-- Server-side events other resources can listen to. See docs/API.md.
function Emit(name, ...)
    TriggerEvent('as-garages:server:' .. name, ...)
end

-- Everything that happens is logged. `garage` and `amount` feed the admin stats page.
function Log(action, desc, plate, garage, amount)
    Debug(action, desc)
    MySQL.insert('INSERT INTO as_garage_logs (ts, action, plate, detail, garage, amount) VALUES (?, ?, ?, ?, ?, ?)',
        { os.time(), action, plate, tostring(desc):sub(1, 400), garage, math.floor(amount or 0) })
    if Config.Webhook == '' then return end
    PerformHttpRequest(Config.Webhook, function() end, 'POST', json.encode({
        username = 'AS Garages',
        embeds = {{ title = action, description = desc, color = 10855935,
                    footer = { text = os.date('%Y-%m-%d %H:%M:%S') } }},
    }), { ['Content-Type'] = 'application/json' })
end

-- Per-vehicle history shown on the vehicle card (sales, impounds, losses).
function History(plate, action, detail)
    MySQL.insert('INSERT INTO as_garage_history (plate, ts, action, detail) VALUES (?, ?, ?, ?)',
        { plate, os.time(), action, tostring(detail or ''):sub(1, 200) })
end

local function ensureColumn(tbl, col, ddl)
    local n = MySQL.scalar.await([[SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?]], { tbl, col })
    if (n or 0) == 0 then MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN %s'):format(tbl, ddl)) end
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
    ensureColumn('as_garage_vehicles', 'nick', '`nick` VARCHAR(40) NULL')
    ensureColumn('as_garage_vehicles', 'folder', '`folder` VARCHAR(24) NULL')
    ensureColumn('as_garage_vehicles', 'transit_to', '`transit_to` VARCHAR(64) NULL')
    ensureColumn('as_garage_vehicles', 'transit_at', '`transit_at` BIGINT NOT NULL DEFAULT 0')
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `as_garage_locations` (
        `id` VARCHAR(64) NOT NULL, `data` LONGTEXT NOT NULL, PRIMARY KEY (`id`))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `as_garage_access` (
        `garage` VARCHAR(64) NOT NULL, `identifier` VARCHAR(64) NOT NULL, `name` VARCHAR(100) NULL,
        PRIMARY KEY (`garage`, `identifier`))]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `as_garage_logs` (
        `id` INT NOT NULL AUTO_INCREMENT, `ts` BIGINT NOT NULL, `action` VARCHAR(64) NOT NULL,
        `plate` VARCHAR(12) NULL, `detail` VARCHAR(400) NULL,
        PRIMARY KEY (`id`), KEY `ts` (`ts`), KEY `plate` (`plate`))]])
    ensureColumn('as_garage_logs', 'garage', '`garage` VARCHAR(64) NULL')
    ensureColumn('as_garage_logs', 'amount', '`amount` INT NOT NULL DEFAULT 0')
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `as_garage_history` (
        `id` INT NOT NULL AUTO_INCREMENT, `plate` VARCHAR(12) NOT NULL, `ts` BIGINT NOT NULL,
        `action` VARCHAR(32) NOT NULL, `detail` VARCHAR(200) NULL,
        PRIMARY KEY (`id`), KEY `plate` (`plate`))]])
    MySQL.update('DELETE FROM as_garage_logs WHERE ts < ?', { os.time() - Config.LogDays * 86400 })
    MySQL.update('DELETE FROM as_garage_history WHERE ts < ?', { os.time() - Config.HistoryDays * 86400 })

    LoadGarages()
    LoadAccess()

    -- Anything still marked "out" at startup was lost with the previous server session.
    if Config.StuckBehaviour == 'impound' then
        MySQL.update.await([[UPDATE as_garage_vehicles SET state = 2, garage = ?, impound_reason = ?,
            impound_by = 'System', impound_fee = ?, impound_at = ?, impound_until = 0, owner_release = 1
            WHERE state = 0]], { Config.DefaultImpound, L('stuck_reason'), Config.StuckImpoundFee, os.time() })
    else
        MySQL.update.await('UPDATE as_garage_vehicles SET state = 1 WHERE state = 0')
    end
    Ready = true
end

CreateThread(function()
    if not Bridge.waitReady() then return end
    setup()
end)

-- Vehicles whose delivery time has passed arrive at their new garage.
function SettleTransit()
    MySQL.update.await([[UPDATE as_garage_vehicles SET garage = transit_to, transit_to = NULL, transit_at = 0
        WHERE transit_at > 0 AND transit_at <= ?]], { os.time() })
end

-- Garages visible to this player. Clients call this on load and when their job changes.
lib.callback.register('asg:getGarages', function(src)
    local p = Bridge.getPlayer(src)
    if not p then return {} end
    local out = {}
    for _, g in pairs(Garages) do
        if IsForSale(g) or CanUse(p, g) then out[#out + 1] = Plain(g) end
    end
    return out
end)

local function statusFor(row, g)
    if row.state == 2 then return 'imp' end
    if row.state == 0 then return 'out' end
    if row.transit_at and row.transit_at > os.time() then return 'transit' end
    return row.garage == g.id and 'in' or 'away'
end

local function repairCost(engine, body)
    local r = Config.Repair
    if not r.enabled then return 0 end
    return math.ceil(((100 - (engine or 100)) + (100 - (body or 100))) * r.pricePerPercent)
end
RepairCost = repairCost

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
                    body = math.floor((props.bodyHealth or 1000) / 10), transit_at = 0 }
            MySQL.insert('INSERT IGNORE INTO as_garage_vehicles (plate, garage, state, fuel, engine, body) VALUES (?, ?, 1, ?, ?, ?)',
                { v.plate, row.garage, row.fuel, row.engine, row.body })
        end
        local status = statusFor(row, g)
        local at
        if status == 'transit' then at = Garages[row.transit_to] and Garages[row.transit_to].label
        elseif row.garage ~= g.id then at = Garages[row.garage] and Garages[row.garage].label end
        out[#out + 1] = {
            plate = v.plate, model = v.model, status = status, at = at, arrive = status == 'transit' and row.transit_at or nil,
            fuel = row.fuel, eng = row.engine, body = row.body, km = math.floor(row.mileage or 0),
            storedAt = row.stored_at, fav = row.fav == 1, nick = row.nick, folder = row.folder, mine = v.owner == p.id,
            plateIndex = v.props.plateIndex or 0, repair = repairCost(row.engine, row.body),
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
                km = math.floor(row.mileage or 0), storedAt = row.impound_at, fav = false, nick = row.nick,
                plateIndex = v.props.plateIndex or 0,
                imp = { reason = row.impound_reason, by = row.impound_by, at = row.impound_at, until_ = row.impound_until,
                        fee = row.impound_fee, storage = storage, days = days, ownerRelease = row.owner_release == 1 },
            }
        end
    end
    return out
end

function IsOfficer(p)
    return p ~= nil and Bridge.hasGroup(p.job, p.grade, Config.ImpoundJobs)
end

lib.callback.register('asg:getGarage', function(src, id)
    local g = Garages[id]
    local p = Bridge.getPlayer(src)
    if not g or not p or not InRange(src, g) then return nil end

    local info = { id = g.id, label = g.label, sub = g.sub, type = g.type, slots = Slots(g), price = g.price }
    if IsForSale(g) then return { garage = info, forSale = true } end
    if not CanUse(p, g) then return nil end

    SettleTransit()
    local data = {
        garage = info, now = os.time(),
        features = { repair = Config.Repair.enabled, keys = Config.ShareKeys.enabled, keysMinutes = Config.ShareKeys.minutes },
    }
    if g.type == 'impound' then
        local officer = IsOfficer(p)
        data.vehicles = listImpounded(p, g, officer)
        data.officer = officer
        data.tab = 'impound'
    else
        data.vehicles = listVehicles(p, g)
        data.tab = g.type == 'public' and 'mine' or g.type
        info.used = MySQL.scalar.await('SELECT COUNT(*) FROM as_garage_vehicles WHERE garage = ? AND state = 1', { g.id }) or 0
        if g.type == 'private' and g.owner == p.id then
            data.isOwner = true
            local up = Config.Upgrades
            data.upgrade = up.enabled and (g.extra or 0) < up.maxExtra and { price = up.price, per = up.slotsPer, extra = g.extra or 0, max = up.maxExtra } or nil
        end
    end
    return data
end)

-- Vehicle leaves the garage. The row is flipped atomically before anything spawns, so two
-- players (or one player spamming) can never pull the same plate out twice.
function Reserve(src, plate, prev, garage, paid)
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
    SettleTransit()
    local flipped = MySQL.update.await('UPDATE as_garage_vehicles SET state = 0 WHERE plate = ? AND state = 1 AND garage = ? AND transit_at = 0', { plate, g.id })
    Locks[plate] = nil
    if flipped ~= 1 then return false, 'unavailable' end

    Bridge.setNative(plate, false, g.id)
    Reserve(src, plate, 1, g.id)
    Log('Vehicle taken out', ('%s (%s) took %s from %s'):format(p.name, p.id, plate, g.label), plate, g.id)
    Emit('vehicleTakenOut', src, plate, g.id)
    return true, { model = v.model, props = v.props, spawn = spawn, plate = plate }
end)

lib.callback.register('asg:spawned', function(src, plate, netId)
    plate = NormPlate(plate)
    local pend = Pending[plate]
    if not pend or pend.src ~= src then return false end
    Pending[plate] = nil
    Spawned[plate] = { netId = netId, src = src, garage = pend.garage, misses = 0 }

    -- The client has just created the vehicle: wait briefly for it to exist on the server, then give keys.
    local entity = NetworkGetEntityFromNetworkId(netId)
    for _ = 1, 20 do
        if entity and entity ~= 0 and DoesEntityExist(entity) then break end
        Wait(100)
        entity = NetworkGetEntityFromNetworkId(netId)
    end
    Keys.give(src, plate, (entity and entity ~= 0 and DoesEntityExist(entity)) and entity or nil)
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

lib.callback.register('asg:store', function(src, garageId, netId, props, km)
    local g = Garages[garageId]
    local p = Bridge.getPlayer(src)
    if not g or not p or g.type == 'impound' then return false, 'no_access' end
    if not InRange(src, g) then return false, 'too_far' end
    if not CanUse(p, g) then return false, 'no_access' end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false, 'unavailable' end
    if #(GetEntityCoords(entity) - g.coords) > g.radius + 20.0 then return false, 'too_far' end
    if g.allowed and not g.allowed[GetVehicleType(entity)] then return false, 'type_not_allowed' end

    local rawPlate = GetVehicleNumberPlateText(entity)
    local plate = NormPlate(rawPlate)
    if Locks[plate] then return false, 'unavailable' end

    -- Players can only store vehicles they own, even in shared garages.
    local v = Bridge.getVehicle(plate)
    if not v then return false, 'invalid_vehicle' end
    if v.owner ~= p.id then return false, 'not_owner' end
    if Config.Keys.requireKeysToStore and not Keys.has(src, plate, entity) then return false, 'keys_required' end

    Locks[plate] = true
    local row = MySQL.single.await('SELECT state, garage FROM as_garage_vehicles WHERE plate = ?', { plate })
    if row and row.state == 2 then Locks[plate] = nil return false, 'unavailable' end
    if not (row and row.state == 1 and row.garage == g.id) then
        local used = MySQL.scalar.await('SELECT COUNT(*) FROM as_garage_vehicles WHERE garage = ? AND state = 1', { g.id }) or 0
        if used >= Slots(g) then Locks[plate] = nil return false, 'garage_full' end
    end

    if type(props) == 'table' then
        props.plate = rawPlate
        props.model = props.model or v.model
        Bridge.saveProps(plate, props)
    else
        props = v.props
    end
    km = math.min(math.max(tonumber(km) or 0, 0), 500)

    MySQL.update.await([[INSERT INTO as_garage_vehicles (plate, garage, state, fuel, engine, body, mileage, stored_at)
        VALUES (?, ?, 1, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE garage = VALUES(garage), state = 1, fuel = VALUES(fuel), engine = VALUES(engine),
        body = VALUES(body), mileage = mileage + VALUES(mileage), stored_at = VALUES(stored_at),
        transit_to = NULL, transit_at = 0]], {
        plate, g.id,
        math.min(100, math.max(0, math.floor(props.fuelLevel or 100))),
        math.min(100, math.max(0, math.floor((props.engineHealth or 1000) / 10))),
        math.min(100, math.max(0, math.floor((props.bodyHealth or 1000) / 10))),
        km, os.time(),
    })
    Bridge.setNative(plate, true, g.id)
    Spawned[plate] = nil
    if Config.Keys.removeOnStore then Keys.remove(src, plate, entity) end
    DeleteEntity(entity)
    Locks[plate] = nil
    Log('Vehicle stored', ('%s (%s) stored %s in %s'):format(p.name, p.id, plate, g.label), plate, g.id)
    Emit('vehicleStored', src, plate, g.id)
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
    History(plate, 'lost', 'Vehicle disappeared from the world')
    Log('Vehicle lost', plate .. ' no longer exists in the world', plate, s and s.garage)
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

-- Abandoned vehicles: nobody in it and no player nearby for Config.Abandoned.minutes.
-- They are impounded or returned to the garage they came from (Config.Abandoned.action).
local function playersNear(coords, dist)
    for _, id in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(id)
        if ped ~= 0 and #(GetEntityCoords(ped) - coords) <= dist then return true end
    end
    return false
end

local function abandon(plate, s)
    local cfg = Config.Abandoned
    if cfg.action == 'garage' then
        MySQL.update('UPDATE as_garage_vehicles SET state = 1 WHERE plate = ? AND state = 0', { plate })
        Bridge.setNative(plate, true, s.garage or Config.DefaultGarage)
    else
        MySQL.update([[UPDATE as_garage_vehicles SET state = 2, garage = ?, impound_reason = ?, impound_by = 'System',
            impound_fee = ?, impound_at = ?, impound_until = 0, owner_release = 1 WHERE plate = ? AND state = 0]],
            { Config.DefaultImpound, L('abandoned_reason'), cfg.fee, os.time(), plate })
    end
    History(plate, 'abandoned', cfg.action == 'garage' and 'Returned to garage' or 'Impounded')
    Log('Vehicle abandoned', ('%s was left on the road and was %s'):format(plate, cfg.action == 'garage' and 'returned to its garage' or 'impounded'), plate, s.garage)
    Emit('vehicleAbandoned', plate, cfg.action)
end

CreateThread(function()
    while true do
        Wait(60000)
        local cfg = Config.Abandoned
        if cfg.enabled then
            local now = os.time()
            for plate, s in pairs(Spawned) do
                local e = NetworkGetEntityFromNetworkId(s.netId)
                if e and e ~= 0 and DoesEntityExist(e) then
                    if GetPedInVehicleSeat(e, -1) ~= 0 or playersNear(GetEntityCoords(e), cfg.radius) then
                        s.idleSince = nil
                    else
                        s.idleSince = s.idleSince or now
                        if now - s.idleSince >= cfg.minutes * 60 then
                            DeleteEntity(e)
                            Spawned[plate] = nil
                            abandon(plate, s)
                        end
                    end
                end
            end
        end
    end
end)
