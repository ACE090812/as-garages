-- Walk-in garage interiors: the player is moved into an interior (an MLO, an IPL or any
-- interior you configure) inside their own routing bucket, where their stored vehicles are
-- shown parked in a showroom. Configure with `interior = { ... }` on a garage.

lib.callback.register('asg:interior:enter', function(src, garageId)
    local g, p = Garages[garageId], Bridge.getPlayer(src)
    if not g or not p or not g.interior or g.type == 'impound' or IsForSale(g) then return nil end
    if not InRange(src, g) or not CanUse(p, g) then return nil end

    SettleTransit()
    local rows = MySQL.query.await([[SELECT plate FROM as_garage_vehicles WHERE garage = ? AND state = 1 AND transit_at = 0
        ORDER BY fav DESC, stored_at DESC LIMIT 40]], { g.id }) or {}
    local vehicles = {}
    for _, r in ipairs(rows) do
        if #vehicles >= #g.interior.bays then break end
        local v = Bridge.getVehicle(r.plate)
        if v and (g.shared or v.owner == p.id) then
            vehicles[#vehicles + 1] = { plate = v.plate, model = v.model, props = v.props }
        end
    end

    local bucket = 5000 + src
    SetPlayerRoutingBucket(src, bucket)
    SetRoutingBucketPopulationEnabled(bucket, false)
    Inside[src] = g.id
    return { vehicles = vehicles }
end)

lib.callback.register('asg:interior:exit', function(src)
    SetPlayerRoutingBucket(src, 0)
    Inside[src] = nil
    return true
end)

AddEventHandler('playerDropped', function()
    Inside[source] = nil
end)
