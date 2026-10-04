-- Public API for other resources: exports and server events. See docs/API.md.
-- (Garage ownership and temporary garage exports live in server/private.lua,
-- vehicle exports in server/vehicles.lua and server/admin.lua.)

exports('GetGarages', function()
    local out = {}
    for _, g in pairs(Garages) do out[#out + 1] = Plain(g) end
    return out
end)

exports('GetGarage', function(id)
    local g = Garages[id]
    return g and Plain(g) or nil
end)

-- Impound a vehicle by plate from code (towing, MDT, admin tools). Deletes it from the world if it is out.
-- opts = { reason = '', fee = 0, holdMinutes = 0, ownerRelease = true, by = 'System', lot = 'davis_impound' }
exports('ImpoundVehicle', function(plate, opts)
    plate = NormPlate(plate)
    opts = type(opts) == 'table' and opts or {}
    local v = Bridge.getVehicle(plate)
    if not v then return false end

    local s = Spawned[plate]
    if s then
        local e = NetworkGetEntityFromNetworkId(s.netId)
        if e and e ~= 0 and DoesEntityExist(e) then DeleteEntity(e) end
        Spawned[plate] = nil
    end
    local lot = Garages[opts.lot] and Garages[opts.lot].type == 'impound' and opts.lot or Config.DefaultImpound
    DoImpound(plate, v.props, {
        lot = lot, reason = tostring(opts.reason or ''):sub(1, 200),
        fee = math.min(math.max(math.floor(tonumber(opts.fee) or 0), 0), Config.MaxImpoundFee),
        holdMin = math.max(math.floor(tonumber(opts.holdMinutes) or 0), 0),
        ownerRelease = opts.ownerRelease ~= false, by = tostring(opts.by or 'System'):sub(1, 100),
    })
    Log('Vehicle impounded', ('%s impounded %s via export'):format(opts.by or 'System', plate), plate, lot, opts.fee)
    Emit('vehicleImpounded', nil, plate, lot, opts.fee or 0)
    return true
end)
