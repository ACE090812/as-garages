-- Per-vehicle actions: preview data, rename, move between garages, sell to a player.

local function ownerOf(src, plate)
    local p = Bridge.getPlayer(src)
    if not p then return end
    local v = Bridge.getVehicle(plate)
    if v and v.owner == p.id then return p, v end
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
    name = tostring(name or ''):gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    name = name:sub(1, 24)
    local nick = name ~= '' and name or nil
    MySQL.update.await('UPDATE as_garage_vehicles SET nick = ? WHERE plate = ?', { nick, plate })
    return true, nick or ''
end)

lib.callback.register('asg:transfer', function(src, plate, fromId, toId)
    local from, to, p = Garages[fromId], Garages[toId], Bridge.getPlayer(src)
    if not from or not to or not p or from == to then return false, 'unavailable' end
    if from.type == 'impound' or to.type == 'impound' or IsForSale(to) then return false, 'unavailable' end
    if not InRange(src, from) then return false, 'too_far' end
    if not CanUse(p, from) or not CanUse(p, to) then return false, 'no_access' end

    plate = NormPlate(plate)
    if not ownerOf(src, plate) then return false, 'not_owner' end
    if Locks[plate] or Pending[plate] then return false, 'unavailable' end

    local used = MySQL.scalar.await('SELECT COUNT(*) FROM as_garage_vehicles WHERE garage = ? AND state = 1', { to.id }) or 0
    if used >= to.slots then return false, 'garage_full' end

    Locks[plate] = true
    local moved = MySQL.update.await('UPDATE as_garage_vehicles SET garage = ? WHERE plate = ? AND state = 1 AND garage = ?',
        { to.id, plate, from.id })
    if moved ~= 1 then Locks[plate] = nil return false, 'not_stored' end

    local fee = Config.TransferFee
    if fee > 0 and not Bridge.pay(src, fee, 'garage transfer') then
        MySQL.update.await('UPDATE as_garage_vehicles SET garage = ? WHERE plate = ? AND state = 1', { from.id, plate })
        Locks[plate] = nil
        return false, 'funds', fee
    end
    Bridge.setNative(plate, true, to.id)
    Locks[plate] = nil
    Log('Vehicle transferred', ('%s (%s) moved %s from %s to %s'):format(p.name, p.id, plate, from.label, to.label), plate)
    return true, to.label
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
        local row = MySQL.single.await('SELECT state, garage FROM as_garage_vehicles WHERE plate = ?', { plate })
        return row and row.state == 1 and row.garage == g.id
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
    MySQL.update.await('UPDATE as_garage_vehicles SET fav = 0, nick = NULL WHERE plate = ?', { plate })
    Locks[plate] = nil
    Bridge.notify(buyerSrc, L('bought', plate, price), 'success')
    Log('Vehicle sold', ('%s (%s) sold %s to %s (%s) for $%s'):format(p.name, p.id, plate, buyer.name, buyer.id, price), plate)
    return true, plate, price
end)

exports('GetVehicleState', function(plate)
    plate = NormPlate(plate)
    local row = MySQL.single.await('SELECT garage, state FROM as_garage_vehicles WHERE plate = ?', { plate })
    if not row then return nil end
    return { garage = row.garage, state = ({ [0] = 'out', [1] = 'stored', [2] = 'impounded' })[row.state] }
end)
