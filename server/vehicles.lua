-- Per-vehicle actions: preview data, rename, folders, history, move between garages, sell,
-- lend keys and repair.

local function ownerOf(src, plate)
    local p = Bridge.getPlayer(src)
    if not p then return end
    local v = Bridge.getVehicle(plate)
    if v and v.owner == p.id then return p, v end
end

local function cleanText(text, max)
    text = tostring(text or ''):gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return text:sub(1, max)
end

-- Mods for the 3D preview. Fetched on demand so the garage list stays small.
lib.callback.register('asg:props', function(src, garageId, plate)
    local g, p = Garages[garageId], Bridge.getPlayer(src)
    if not g or not p or not InRange(src, g) or not CanUse(p, g) then return nil end
    plate = NormPlate(plate)
    local v = Bridge.getVehicle(plate)
    if not v then return nil end
    if v.owner == p.id then return v.props end

    local row = MySQL.single.await('SELECT state, garage FROM as_garage_vehicles WHERE plate = ?', { plate })
    if not row then return nil end
    if g.type == 'impound' then
        return (row.state == 2 and IsOfficer(p)) and v.props or nil
    end
    return (g.shared and row.state == 1 and row.garage == g.id) and v.props or nil
end)

lib.callback.register('asg:rename', function(src, plate, name)
    plate = NormPlate(plate)
    if not ownerOf(src, plate) then return false, 'not_owner' end
    name = cleanText(name, 24)
    local nick = name ~= '' and name or nil
    MySQL.update.await('UPDATE as_garage_vehicles SET nick = ? WHERE plate = ?', { nick, plate })
    return true, nick or ''
end)

lib.callback.register('asg:folder', function(src, plate, name)
    plate = NormPlate(plate)
    if not ownerOf(src, plate) then return false, 'not_owner' end
    name = cleanText(name, 20)
    local folder = name ~= '' and name or nil
    MySQL.update.await('UPDATE as_garage_vehicles SET folder = ? WHERE plate = ?', { folder, plate })
    return true, folder or ''
end)

-- Owner count, impound count and the latest events for the history window.
lib.callback.register('asg:history', function(src, plate)
    local p = Bridge.getPlayer(src)
    plate = NormPlate(plate)
    local v = p and Bridge.getVehicle(plate)
    if not v or (v.owner ~= p.id and not IsOfficer(p)) then return nil end
    local sales = MySQL.scalar.await("SELECT COUNT(*) FROM as_garage_history WHERE plate = ? AND action = 'sold'", { plate }) or 0
    local impounds = MySQL.scalar.await("SELECT COUNT(*) FROM as_garage_history WHERE plate = ? AND action IN ('impounded', 'abandoned', 'lost')", { plate }) or 0
    local events = MySQL.query.await('SELECT ts, action, detail FROM as_garage_history WHERE plate = ? ORDER BY id DESC LIMIT 12', { plate }) or {}
    return { owners = sales + 1, impounds = impounds, events = events }
end)

local function garageCount(garageId)
    local n = MySQL.scalar.await('SELECT COUNT(*) FROM as_garage_vehicles WHERE garage = ? AND state = 1', { garageId }) or 0
    local incoming = MySQL.scalar.await('SELECT COUNT(*) FROM as_garage_vehicles WHERE transit_to = ? AND transit_at > 0', { garageId }) or 0
    return n + incoming
end

lib.callback.register('asg:transfer', function(src, plate, fromId, toId)
    local from, to, p = Garages[fromId], Garages[toId], Bridge.getPlayer(src)
    if not from or not to or not p or from == to then return false, 'unavailable' end
    if from.type == 'impound' or to.type == 'impound' or IsForSale(to) then return false, 'unavailable' end
    if not InRange(src, from) then return false, 'too_far' end
    if not CanUse(p, from) or not CanUse(p, to) then return false, 'no_access' end

    plate = NormPlate(plate)
    if not ownerOf(src, plate) then return false, 'not_owner' end
    if Locks[plate] or Pending[plate] then return false, 'unavailable' end
    if garageCount(to.id) >= Slots(to) then return false, 'garage_full' end

    local delay = math.max(tonumber(Config.TransferDelay) or 0, 0)
    Locks[plate] = true
    SettleTransit()
    local moved
    if delay > 0 then
        moved = MySQL.update.await([[UPDATE as_garage_vehicles SET transit_to = ?, transit_at = ?
            WHERE plate = ? AND state = 1 AND garage = ? AND transit_at = 0]], { to.id, os.time() + delay, plate, from.id })
    else
        moved = MySQL.update.await('UPDATE as_garage_vehicles SET garage = ? WHERE plate = ? AND state = 1 AND garage = ? AND transit_at = 0',
            { to.id, plate, from.id })
    end
    if moved ~= 1 then Locks[plate] = nil return false, 'not_stored' end

    local fee = Config.TransferFee
    if fee > 0 and not Bridge.pay(src, fee, 'garage transfer') then
        MySQL.update.await('UPDATE as_garage_vehicles SET garage = ?, transit_to = NULL, transit_at = 0 WHERE plate = ? AND state = 1', { from.id, plate })
        Locks[plate] = nil
        return false, 'funds', fee
    end
    if delay == 0 then Bridge.setNative(plate, true, to.id) end
    Locks[plate] = nil
    Log('Vehicle transferred', ('%s (%s) moved %s from %s to %s'):format(p.name, p.id, plate, from.label, to.label), plate, to.id, fee)
    Emit('vehicleTransferred', src, plate, from.id, to.id)
    return true, to.label, delay > 0 and (os.time() + delay) or 0
end)

-- Ask the buyer; never wait forever (they may ignore the dialog or disconnect).
local function askBuyer(buyerSrc, data)
    local pr, done = promise.new(), false
    local function finish(v)
        if done then return end
        done = true
        pr:resolve(v)
    end
    CreateThread(function() finish(lib.callback.await('asg:confirmSale', buyerSrc, data) == true) end)
    SetTimeout(35000, function() finish(false) end)
    return Citizen.Await(pr)
end

lib.callback.register('asg:sell', function(src, garageId, plate, buyerId, price)
    local g, p = Garages[garageId], Bridge.getPlayer(src)
    if not g or not p or g.type == 'impound' then return false, 'unavailable' end
    if not InRange(src, g) or not CanUse(p, g) then return false, 'too_far' end

    price = math.floor(tonumber(price) or -1)
    if price < 0 or price > Config.MaxSalePrice then return false, 'bad_price' end

    local buyerSrc = tonumber(buyerId)
    local buyer = buyerSrc and buyerSrc ~= src and Bridge.getPlayer(buyerSrc)
    if not buyer then return false, 'no_buyer' end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(buyerSrc))) > 10.0 then return false, 'no_buyer' end

    plate = NormPlate(plate)
    local _, v = ownerOf(src, plate)
    if not v then return false, 'not_owner' end
    if Locks[plate] or Pending[plate] then return false, 'sale_busy' end

    local function stored()
        local row = MySQL.single.await('SELECT state, garage, transit_at FROM as_garage_vehicles WHERE plate = ?', { plate })
        return row and row.state == 1 and row.garage == g.id and row.transit_at == 0
    end
    if not stored() then return false, 'not_stored' end

    Locks[plate] = true
    local accepted = askBuyer(buyerSrc, { seller = p.name, plate = plate, price = price, model = v.model })
    if not accepted then Locks[plate] = nil return false, 'sale_declined' end

    -- Things can change while the buyer thinks about it.
    local _, still = ownerOf(src, plate)
    if not still or not stored() then Locks[plate] = nil return false, 'not_stored' end
    if not Bridge.pay(buyerSrc, price, 'vehicle purchase') then
        Locks[plate] = nil
        Bridge.notify(buyerSrc, L('funds', price), 'error')
        return false, 'sale_declined'
    end

    Bridge.give(src, price, 'vehicle sale')
    Bridge.setOwner(plate, buyer.id, buyerSrc)
    MySQL.update.await('UPDATE as_garage_vehicles SET fav = 0, nick = NULL, folder = NULL WHERE plate = ?', { plate })
    Locks[plate] = nil
    Bridge.notify(buyerSrc, L('bought', plate, price), 'success')
    History(plate, 'sold', ('%s to %s for $%s'):format(p.name, buyer.name, price))
    Log('Vehicle sold', ('%s (%s) sold %s to %s (%s) for $%s'):format(p.name, p.id, plate, buyer.name, buyer.id, price), plate, g.id, price)
    Emit('vehicleSold', src, buyerSrc, plate, price)
    return true, plate, price
end)

-- Lend keys for a while. The vehicle has to be out in the world.
lib.callback.register('asg:shareKeys', function(src, plate, targetSrc)
    local cfg = Config.ShareKeys
    if not cfg.enabled then return false, 'not_allowed' end
    plate = NormPlate(plate)
    local p = ownerOf(src, plate)
    if not p then return false, 'not_owner' end

    targetSrc = tonumber(targetSrc)
    local t = targetSrc and targetSrc ~= src and Bridge.getPlayer(targetSrc)
    if not t then return false, 'no_buyer' end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(targetSrc))) > 15.0 then return false, 'no_buyer' end

    local s = Spawned[plate]
    local entity = s and NetworkGetEntityFromNetworkId(s.netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false, 'keys_need_out' end

    cfg.give(targetSrc, plate, entity)
    Bridge.notify(targetSrc, L('keys_received', plate, cfg.minutes), 'success')
    SetTimeout(cfg.minutes * 60000, function()
        local still = Spawned[plate]
        local e = still and NetworkGetEntityFromNetworkId(still.netId)
        pcall(cfg.remove, targetSrc, plate, e or entity)
        Bridge.notify(targetSrc, L('keys_expired', plate), 'inform')
    end)
    Log('Keys shared', ('%s (%s) lent keys for %s to %s (%s) for %s min'):format(p.name, p.id, plate, t.name, t.id, cfg.minutes), plate)
    return true, t.name
end)

-- Repair a stored vehicle from the garage screen.
lib.callback.register('asg:repair', function(src, garageId, plate)
    local g, p = Garages[garageId], Bridge.getPlayer(src)
    if not Config.Repair.enabled then return false, 'not_allowed' end
    if not g or not p or g.type == 'impound' then return false, 'unavailable' end
    if not InRange(src, g) or not CanUse(p, g) then return false, 'too_far' end

    plate = NormPlate(plate)
    local _, v = ownerOf(src, plate)
    if not v then return false, 'not_owner' end
    if Locks[plate] or Pending[plate] then return false, 'unavailable' end

    local row = MySQL.single.await('SELECT state, garage, engine, body, transit_at FROM as_garage_vehicles WHERE plate = ?', { plate })
    if not row or row.state ~= 1 or row.garage ~= g.id or row.transit_at ~= 0 then return false, 'not_stored' end
    local cost = RepairCost(row.engine, row.body)
    if cost <= 0 then return false, 'nothing_to_repair' end

    Locks[plate] = true
    if not Bridge.pay(src, cost, 'vehicle repair') then Locks[plate] = nil return false, 'funds', cost end

    local props = v.props
    props.engineHealth, props.bodyHealth, props.tankHealth, props.dirtLevel = 1000.0, 1000.0, 1000.0, 0.0
    props.tyres, props.windows, props.doors, props.bumpers = nil, nil, nil, nil
    Bridge.saveProps(plate, props)
    MySQL.update.await('UPDATE as_garage_vehicles SET engine = 100, body = 100 WHERE plate = ?', { plate })
    Locks[plate] = nil

    if Config.Repair.onRepair then pcall(Config.Repair.onRepair, src, plate) end
    History(plate, 'repaired', ('Repaired for $%s'):format(cost))
    Log('Vehicle repaired', ('%s (%s) repaired %s for $%s'):format(p.name, p.id, plate, cost), plate, g.id, cost)
    Emit('vehicleRepaired', src, plate, cost)
    return true, cost
end)

exports('GetVehicleState', function(plate)
    plate = NormPlate(plate)
    local row = MySQL.single.await('SELECT garage, state, transit_at FROM as_garage_vehicles WHERE plate = ?', { plate })
    if not row then return nil end
    local state = ({ [0] = 'out', [1] = 'stored', [2] = 'impounded' })[row.state]
    if state == 'stored' and row.transit_at > os.time() then state = 'in_transit' end
    return { garage = row.garage, state = state }
end)

-- Let mechanic / tuning resources update a stored vehicle's condition (values are percent, 0-100).
exports('SetVehicleCondition', function(plate, condition)
    plate = NormPlate(plate)
    local v = Bridge.getVehicle(plate)
    if not v or type(condition) ~= 'table' then return false end
    local function pct(n) return n and math.min(100, math.max(0, math.floor(tonumber(n) or 100))) or nil end
    local props = v.props
    if condition.engine then props.engineHealth = pct(condition.engine) * 10.0 end
    if condition.body then props.bodyHealth = pct(condition.body) * 10.0 end
    if condition.fuel then props.fuelLevel = pct(condition.fuel) + 0.0 end
    Bridge.saveProps(plate, props)
    MySQL.update.await([[UPDATE as_garage_vehicles SET engine = COALESCE(?, engine), body = COALESCE(?, body),
        fuel = COALESCE(?, fuel) WHERE plate = ?]], { pct(condition.engine), pct(condition.body), pct(condition.fuel), plate })
    return true
end)
