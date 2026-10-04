-- Private / house garages: bought by a player, shared with a short list of members.

local function ownerOnly(src, garageId)
    local g, p = Garages[garageId], Bridge.getPlayer(src)
    if g and p and g.type == 'private' and g.owner == p.id then return g, p end
end

local function setOwner(g, identifier, name)
    g.owner, g.ownerName = identifier, name
    MySQL.update.await('DELETE FROM as_garage_access WHERE garage = ?', { g.id })
    Access[g.id] = {}
    PersistGarage(g)
    RefreshAll()
end

lib.callback.register('asg:buy', function(src, garageId)
    local g, p = Garages[garageId], Bridge.getPlayer(src)
    if not g or not p or not IsForSale(g) then return false, 'garage_owned' end
    if not InRange(src, g) then return false, 'too_far' end

    local owned = 0
    for _, other in pairs(Garages) do
        if other.type == 'private' and other.owner == p.id then owned = owned + 1 end
    end
    if owned >= Config.MaxPrivateGarages then return false, 'garage_limit' end

    local lock = 'garage:' .. g.id
    if Locks[lock] then return false, 'unavailable' end
    Locks[lock] = true
    local price = g.price or 0
    if not Bridge.pay(src, price, 'garage purchase') then Locks[lock] = nil return false, 'funds', price end

    setOwner(g, p.id, p.name)
    Locks[lock] = nil
    Log('Garage bought', ('%s (%s) bought %s for $%s'):format(p.name, p.id, g.id, price))
    return true, g.label
end)

lib.callback.register('asg:members', function(src, garageId)
    local g = ownerOnly(src, garageId)
    if not g then return nil end
    return MySQL.query.await('SELECT identifier, name FROM as_garage_access WHERE garage = ?', { g.id }) or {}
end)

lib.callback.register('asg:addMember', function(src, garageId, targetSrc)
    local g, p = ownerOnly(src, garageId)
    if not g then return false, 'not_garage_owner' end
    targetSrc = tonumber(targetSrc)
    local t = targetSrc and targetSrc ~= src and Bridge.getPlayer(targetSrc)
    if not t then return false, 'no_buyer' end
    if #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(targetSrc))) > 20.0 then return false, 'no_buyer' end

    local count = 0
    for _ in pairs(Access[g.id] or {}) do count = count + 1 end
    if count >= Config.MaxMembers then return false, 'member_limit' end

    MySQL.update.await('INSERT IGNORE INTO as_garage_access (garage, identifier, name) VALUES (?, ?, ?)', { g.id, t.id, t.name })
    Access[g.id] = Access[g.id] or {}
    Access[g.id][t.id] = true
    TriggerClientEvent('asg:refresh', targetSrc)
    Bridge.notify(targetSrc, L('member_you', g.label), 'success')
    Log('Garage access granted', ('%s (%s) added %s (%s) to %s'):format(p.name, p.id, t.name, t.id, g.id))
    return true, t.name
end)

lib.callback.register('asg:removeMember', function(src, garageId, identifier)
    local g, p = ownerOnly(src, garageId)
    if not g then return false, 'not_garage_owner' end
    MySQL.update.await('DELETE FROM as_garage_access WHERE garage = ? AND identifier = ?', { g.id, tostring(identifier) })
    if Access[g.id] then Access[g.id][tostring(identifier)] = nil end
    TriggerClientEvent('asg:refresh', -1)
    Log('Garage access removed', ('%s (%s) removed %s from %s'):format(p.name, p.id, tostring(identifier), g.id))
    return true
end)

-- Exports for housing scripts and other resources ------------------------------

exports('SetGarageOwner', function(garageId, identifier, name)
    local g = Garages[garageId]
    if not g or g.type ~= 'private' then return false end
    setOwner(g, identifier, name)
    return true
end)

exports('GrantAccess', function(garageId, identifier, name)
    local g = Garages[garageId]
    if not g or g.type ~= 'private' then return false end
    MySQL.update.await('INSERT IGNORE INTO as_garage_access (garage, identifier, name) VALUES (?, ?, ?)', { g.id, identifier, name })
    Access[g.id] = Access[g.id] or {}
    Access[g.id][identifier] = true
    TriggerClientEvent('asg:refresh', -1)
    return true
end)

exports('RevokeAccess', function(garageId, identifier)
    local g = Garages[garageId]
    if not g then return false end
    MySQL.update.await('DELETE FROM as_garage_access WHERE garage = ? AND identifier = ?', { g.id, identifier })
    if Access[g.id] then Access[g.id][identifier] = nil end
    TriggerClientEvent('asg:refresh', -1)
    return true
end)
