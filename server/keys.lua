-- Vehicle keys. as-garages gives the player keys whenever a vehicle is taken out or retrieved,
-- can optionally require keys to store a vehicle, and lends keys to other players.
--
-- Pick your keys resource with Config.Keys.resource ('auto' detects it). For a resource that is
-- not built in, use 'custom' and fill in Config.Keys.custom. See docs/KEYS.md.

Keys = {}

local AUTO = { 'as-vehiclekeys', 'qbx_vehiclekeys', 'qb-vehiclekeys', 'Renewed-Vehiclekeys' }

local function adapterName()
    local want = Config.Keys.resource
    if want ~= 'auto' then return want end
    for _, name in ipairs(AUTO) do
        if GetResourceState(name) == 'started' then return name end
    end
end

-- Some resources only have client exports: ask the player's client to run the call.
local function viaClient(adapter, action)
    return function(src, plate, entity)
        local netId = entity and entity ~= 0 and NetworkGetNetworkIdFromEntity(entity) or nil
        TriggerClientEvent('asg:keys:' .. action, src, adapter, plate, netId)
    end
end

-- Display name shown on the key item, taken from the model name when the framework stores one.
local function keyLabel(plate)
    local v = Bridge.getVehicle(plate)
    if v and type(v.model) == 'string' and v.model ~= '' then
        return (v.model:gsub('^%l', string.upper))
    end
end

local ADAPTERS = {
    -- as-vehiclekeys: keys are inventory items. It hands the key back when a vehicle is taken out
    -- and takes it when the vehicle is stored.
    ['as-vehiclekeys'] = {
        give = function(src, plate) exports['as-vehiclekeys']:GiveKey(src, plate, keyLabel(plate)) end,
        remove = function(src, plate) exports['as-vehiclekeys']:TakeKey(src, plate) end,
        has = function(src, plate) return exports['as-vehiclekeys']:HasKey(src, plate) == true end,
    },
    qbx_vehiclekeys = {
        give = function(src, plate, entity) if entity then exports.qbx_vehiclekeys:GiveKeys(src, entity) end end,
        remove = function(src, plate, entity) if entity then exports.qbx_vehiclekeys:RemoveKeys(src, entity) end end,
        has = function(src, plate, entity)
            if not entity then return true end
            return exports.qbx_vehiclekeys:HasKeys(src, entity) == true
        end,
    },
    ['qb-vehiclekeys'] = {
        give = function(src, plate) TriggerClientEvent('vehiclekeys:client:SetOwner', src, plate) end,
    },
    ['Renewed-Vehiclekeys'] = {
        give = viaClient('Renewed-Vehiclekeys', 'give'),
        remove = viaClient('Renewed-Vehiclekeys', 'remove'),
    },
    -- Keys as inventory items (ox_inventory): an item with the plate in its metadata.
    ox_inventory = {
        give = function(src, plate)
            exports.ox_inventory:AddItem(src, Config.Keys.item, 1, { plate = plate, description = plate })
        end,
        remove = function(src, plate)
            exports.ox_inventory:RemoveItem(src, Config.Keys.item, 1, { plate = plate })
        end,
        has = function(src, plate)
            return (exports.ox_inventory:Search(src, 'count', Config.Keys.item, { plate = plate }) or 0) > 0
        end,
    },
    -- Your own resource: fill in Config.Keys.custom in config.lua.
    custom = {
        give = function(src, plate, entity)
            local c = Config.Keys.custom
            if c.give then c.give(src, plate, entity) end
            if c.clientGive then viaClient('custom', 'give')(src, plate, entity) end
        end,
        remove = function(src, plate, entity)
            local c = Config.Keys.custom
            if c.remove then c.remove(src, plate, entity) end
            if c.clientRemove then viaClient('custom', 'remove')(src, plate, entity) end
        end,
        has = function(src, plate, entity)
            local c = Config.Keys.custom
            if c.has then return c.has(src, plate, entity) end
            return true
        end,
    },
}

local function call(action, src, plate, entity)
    local name = adapterName()
    local adapter = name and ADAPTERS[name]
    if not adapter or not adapter[action] then return nil end
    local ok, res = pcall(adapter[action], src, plate, entity)
    if not ok then
        print(('^1[as-garages] keys adapter "%s" failed on %s: %s^0'):format(name, action, tostring(res)))
        return nil
    end
    return res
end

function Keys.give(src, plate, entity) call('give', src, plate, entity) end
function Keys.remove(src, plate, entity) call('remove', src, plate, entity) end

-- true when the player holds keys. If the adapter cannot tell, assume yes.
function Keys.has(src, plate, entity)
    local res = call('has', src, plate, entity)
    if res == nil then return true end
    return res == true
end

-- Should the keys be taken away when a vehicle is stored? Config.Keys.removeOnStore = true / false
-- decides; left as nil it is automatic (on for as-vehiclekeys, off for everything else).
function Keys.removeOnStore()
    local setting = Config.Keys.removeOnStore
    if setting ~= nil then return setting == true end
    return adapterName() == 'as-vehiclekeys'
end
