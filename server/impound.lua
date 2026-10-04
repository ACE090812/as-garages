lib.callback.register('asg:canImpound', function(src)
    return IsOfficer(Bridge.getPlayer(src))
end)

local function pct(n, scale) return math.min(100, math.max(0, math.floor((n or scale) / (scale / 100)))) end

-- Writes the impound record. Used by officers (/impound) and by the ImpoundVehicle export.
-- info = { lot, reason, fee, holdMin, ownerRelease (bool), by }
function DoImpound(plate, props, info)
    local now = os.time()
    props = props or {}
    MySQL.update.await([[INSERT INTO as_garage_vehicles
        (plate, garage, state, fuel, engine, body, impound_reason, impound_by, impound_fee, impound_at, impound_until, owner_release)
        VALUES (?, ?, 2, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE garage = VALUES(garage), state = 2, fuel = VALUES(fuel), engine = VALUES(engine),
        body = VALUES(body), impound_reason = VALUES(impound_reason), impound_by = VALUES(impound_by),
        impound_fee = VALUES(impound_fee), impound_at = VALUES(impound_at), impound_until = VALUES(impound_until),
        owner_release = VALUES(owner_release), transit_to = NULL, transit_at = 0]], {
        plate, info.lot, pct(props.fuelLevel, 100), pct(props.engineHealth, 1000), pct(props.bodyHealth, 1000),
        info.reason, info.by, info.fee, now, now + info.holdMin * 60, info.ownerRelease and 1 or 0,
    })
    Bridge.setNative(plate, false, info.lot)
    History(plate, 'impounded', ('%s: %s'):format(info.by, info.reason ~= '' and info.reason or '-'))
end

-- Officer impounds the vehicle in front of them.
lib.callback.register('asg:impound', function(src, netId, data, props)
    local p = Bridge.getPlayer(src)
    if not IsOfficer(p) then return false, 'not_allowed' end
    if type(data) ~= 'table' then return false, 'unavailable' end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false, 'unavailable' end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(entity)) > 15.0 then return false, 'too_far' end

    local rawPlate = GetVehicleNumberPlateText(entity)
    local plate = NormPlate(rawPlate)
    local fee = math.min(math.max(math.floor(tonumber(data.fee) or 0), 0), Config.MaxImpoundFee)
    local holdMin = math.min(math.max(math.floor(tonumber(data.hold) or 0), 0), 10080)
    local lot = Garages[data.lot] and Garages[data.lot].type == 'impound' and data.lot or Config.DefaultImpound
    local reason = tostring(data.reason or ''):sub(1, 200)

    local v = Bridge.getVehicle(plate)
    Spawned[plate] = nil
    if not v then
        DeleteEntity(entity)
        return true, 'impound_removed'
    end

    if type(props) == 'table' then
        props.plate = rawPlate
        props.model = props.model or v.model
        Bridge.saveProps(plate, props)
    else
        props = v.props
    end

    DoImpound(plate, props, {
        lot = lot, reason = reason, fee = fee, holdMin = holdMin, ownerRelease = data.ownerRelease ~= false,
        by = ('%s (%s)'):format(p.name, p.job),
    })
    DeleteEntity(entity)
    Log('Vehicle impounded', ('%s (%s) impounded %s | fee $%s | hold %s min | %s'):format(p.name, p.id, plate, fee, holdMin, reason), plate, lot)
    Emit('vehicleImpounded', src, plate, lot, fee)
    return true, 'impounded_ok', plate
end)

local function storageFee(row)
    if not row.impound_at or row.impound_at == 0 then return 0 end
    local days = math.floor((os.time() - row.impound_at) / 86400)
    return math.min(math.max(days, 0), Config.MaxStorageDays) * Config.StoragePerDay
end

-- Owner pays and drives out. Officers release for free, ignoring holds.
lib.callback.register('asg:retrieve', function(src, lotId, plate, bay)
    local g = Garages[lotId]
    local p = Bridge.getPlayer(src)
    if not g or not p or g.type ~= 'impound' then return false, 'unavailable' end
    if not InRange(src, g) then return false, 'too_far' end
    plate = NormPlate(plate)
    local spawn = g.spawns[tonumber(bay) or 0]
    if not spawn then return false, 'unavailable' end
    if Pending[plate] then return false, 'unavailable' end

    local row = MySQL.single.await('SELECT * FROM as_garage_vehicles WHERE plate = ? AND state = 2', { plate })
    local v = row and Bridge.getVehicle(plate)
    if not v then return false, 'unavailable' end

    local officer = IsOfficer(p)
    local total = 0
    if not officer then
        if v.owner ~= p.id then return false, 'not_owner' end
        if row.owner_release == 0 then return false, 'officers_only' end
        if row.impound_until > os.time() then return false, 'still_held' end
        total = row.impound_fee + storageFee(row)
    end

    local flipped = MySQL.update.await('UPDATE as_garage_vehicles SET state = 0 WHERE plate = ? AND state = 2', { plate })
    if flipped ~= 1 then return false, 'unavailable' end

    if total > 0 and not Bridge.pay(src, total, 'impound fee') then
        MySQL.update.await('UPDATE as_garage_vehicles SET state = 2 WHERE plate = ? AND state = 0', { plate })
        return false, 'funds', total
    end

    Reserve(src, plate, 2, g.id)
    Pending[plate].paid = total
    History(plate, 'retrieved', total > 0 and ('Paid $%s'):format(total) or (officer and 'Released by an officer' or 'Released'))
    Log('Vehicle retrieved from impound', ('%s (%s) retrieved %s from %s | paid $%s%s'):format(
        p.name, p.id, plate, g.label, total, officer and ' (officer release)' or ''), plate, g.id, total)
    Emit('vehicleRetrieved', src, plate, g.id, total)
    return true, { model = v.model, props = v.props, spawn = spawn, plate = plate, fee = total }
end)
