-- Garage admin: the in-game editor (/asgarage) and its server callbacks.

local function isAdmin(src)
    return src ~= 0 and IsPlayerAceAllowed(src, Config.AdminAce)
end

local VALID_TYPES = { public = true, job = true, gang = true, private = true, impound = true }
local VALID_CLASSES = { cars = true, bikes = true, boats = true, air = true }
local BLIP_COLOR = { public = 3, job = 38, gang = 1, private = 3, impound = 1 }

local function clamp(n, lo, hi) return math.min(math.max(n, lo), hi) end

-- 'police, sheriff:2' -> { police = 0, sheriff = 2 }
local function parseGroups(str)
    local out
    for token in tostring(str or ''):gmatch('[^,%s]+') do
        local name, grade = token:match('^([%w_%-]+):?(%d*)$')
        if name then
            out = out or {}
            out[name] = tonumber(grade) or 0
        end
    end
    return out
end

local function groupString(t)
    local parts = {}
    for name, grade in pairs(t or {}) do parts[#parts + 1] = grade > 0 and ('%s:%d'):format(name, grade) or name end
    table.sort(parts)
    return table.concat(parts, ', ')
end

local function point(p, withHeading)
    if type(p) ~= 'table' then return nil end
    local x, y, z, w = tonumber(p.x), tonumber(p.y), tonumber(p.z), tonumber(p.w) or 0.0
    if not (x and y and z) then return nil end
    return withHeading and { x = x, y = y, z = z, w = w } or { x = x, y = y, z = z }
end

-- Validates editor input and saves it as a database override of the config entry (if any).
function SaveGarage(d, actor)
    if type(d) ~= 'table' then return false, 'Bad data.' end
    local id = tostring(d.id or ''):lower()
    if not id:match('^[a-z0-9_]+$') or #id < 2 or #id > 32 then return false, 'Id: 2-32 letters, numbers or _.' end
    if not VALID_TYPES[d.type] then return false, 'Pick a type.' end
    local coords = point(d.coords)
    if not coords then return false, 'Place the interaction point first.' end

    local existing = Garages[id]
    local g = {
        id = id, type = d.type, coords = coords,
        label = tostring(d.label or id):sub(1, 40), sub = tostring(d.sub or ''):sub(1, 60),
        radius = clamp(tonumber(d.radius) or 3.0, 1.5, 10.0),
        slots = clamp(math.floor(tonumber(d.slots) or 10), 1, 200),
        price = clamp(math.floor(tonumber(d.price) or 0), 0, 100000000),
        shared = d.shared == true, spawns = {}, vehicleClasses = {},
    }

    for _, s in ipairs(type(d.spawns) == 'table' and d.spawns or {}) do
        local sp = point(s, true)
        if sp and #g.spawns < 20 then g.spawns[#g.spawns + 1] = sp end
    end
    g.preview = point(d.preview, true)
    for _, key in ipairs(type(d.vehicleClasses) == 'table' and d.vehicleClasses or {}) do
        if VALID_CLASSES[key] then g.vehicleClasses[#g.vehicleClasses + 1] = key end
    end

    if g.type == 'job' then
        g.jobs = parseGroups(d.group)
        if not g.jobs then return false, 'Enter at least one job name.' end
    elseif g.type == 'gang' then
        g.gangs = parseGroups(d.group)
        if not g.gangs then return false, 'Enter at least one gang name.' end
    elseif g.type == 'private' then
        g.shared = true
        if existing then g.owner, g.ownerName = existing.owner, existing.ownerName end
    end
    if g.type == 'impound' or g.type == 'public' then g.shared = false end
    if d.blipOn then
        g.blip = { sprite = g.type == 'impound' and 68 or 357, color = BLIP_COLOR[g.type], scale = 0.7 }
    end

    PersistGarage(g)
    RefreshAll()
    Log('Garage saved', ('%s saved garage %s (%s)'):format(actor or 'system', id, g.type))
    return true, 'Saved.'
end
exports('CreateGarage', function(data) return SaveGarage(data, 'export') end)

lib.addCommand('asgarage', {
    help = 'Open the garage admin editor',
    restricted = Config.AdminAce,
}, function(src)
    if src ~= 0 then TriggerClientEvent('asg:admin:open', src) end
end)

lib.callback.register('asg:admin:data', function(src)
    if not isAdmin(src) then return nil end
    local list = {}
    for _, g in pairs(Garages) do
        local row = Plain(g, true)
        row.group = g.type == 'job' and groupString(g.jobs) or g.type == 'gang' and groupString(g.gangs) or ''
        list[#list + 1] = row
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return { garages = list, maxLogDays = Config.LogDays }
end)

lib.callback.register('asg:admin:save', function(src, d)
    if not isAdmin(src) then return false, 'No permission.' end
    return SaveGarage(d, GetPlayerName(src))
end)

lib.callback.register('asg:admin:delete', function(src, id)
    if not isAdmin(src) then return false, 'No permission.' end
    local g = Garages[tostring(id)]
    if not g then return false, 'Unknown garage.' end
    if not g.override then return false, 'This garage only exists in config.lua. Remove it there.' end
    MySQL.update.await('DELETE FROM as_garage_locations WHERE id = ?', { g.id })
    RefreshAll()
    Log('Garage deleted', ('%s deleted/reset garage %s'):format(GetPlayerName(src), g.id))
    return true, g.inConfig and 'Reset to the config.lua version.' or 'Deleted.'
end)

lib.callback.register('asg:admin:clearOwner', function(src, id)
    if not isAdmin(src) then return false, 'No permission.' end
    local g = Garages[tostring(id)]
    if not g or g.type ~= 'private' then return false, 'Not a private garage.' end
    exports[GetCurrentResourceName()]:SetGarageOwner(g.id, nil, nil)
    Log('Garage owner cleared', ('%s cleared the owner of %s'):format(GetPlayerName(src), g.id))
    return true, 'Owner cleared. The garage is for sale again.'
end)

local STATES = { [0] = 'Out', [1] = 'Stored', [2] = 'Impounded' }

lib.callback.register('asg:admin:vehicles', function(src, query)
    if not isAdmin(src) then return nil end
    query = tostring(query or ''):sub(1, 40)
    local rows
    if query == '' then
        rows = MySQL.query.await('SELECT * FROM as_garage_vehicles ORDER BY stored_at DESC LIMIT 40')
    else
        rows = MySQL.query.await('SELECT * FROM as_garage_vehicles WHERE plate LIKE ? LIMIT 40', { '%' .. query:upper() .. '%' })
        if #rows == 0 then
            -- maybe an owner id (citizenid / identifier)
            local plates = {}
            for i, v in ipairs(Bridge.getOwned(query)) do plates[i] = v.plate end
            if #plates > 0 then rows = MySQL.query.await('SELECT * FROM as_garage_vehicles WHERE plate IN (?) LIMIT 40', { plates }) end
        end
    end
    local out = {}
    for _, row in ipairs(rows or {}) do
        local v = Bridge.getVehicle(row.plate)
        local g = Garages[row.garage]
        out[#out + 1] = {
            plate = row.plate, owner = v and v.owner or '?', model = v and tostring(v.model) or '?',
            state = STATES[row.state] or '?', garage = g and g.label or row.garage, nick = row.nick,
        }
    end
    return out
end)

lib.callback.register('asg:admin:force', function(src, plate, garageId)
    if not isAdmin(src) then return false, 'No permission.' end
    plate = NormPlate(plate)
    local g = Garages[garageId or Config.DefaultGarage]
    if not g or g.type == 'impound' then return false, 'Pick a normal garage.' end
    if not Bridge.getVehicle(plate) then return false, 'Unknown vehicle.' end

    local s = Spawned[plate]
    if s then
        local e = NetworkGetEntityFromNetworkId(s.netId)
        if e and e ~= 0 and DoesEntityExist(e) then DeleteEntity(e) end
        Spawned[plate] = nil
    end
    Pending[plate] = nil
    MySQL.update.await([[INSERT INTO as_garage_vehicles (plate, garage, state, stored_at) VALUES (?, ?, 1, ?)
        ON DUPLICATE KEY UPDATE garage = VALUES(garage), state = 1]], { plate, g.id, os.time() })
    Bridge.setNative(plate, true, g.id)
    Log('Admin force return', ('%s returned %s to %s'):format(GetPlayerName(src), plate, g.label), plate)
    return true, ('%s is stored at %s.'):format(plate, g.label)
end)

lib.callback.register('asg:admin:logs', function(src, query)
    if not isAdmin(src) then return nil end
    query = '%' .. tostring(query or ''):sub(1, 40) .. '%'
    local rows = MySQL.query.await([[SELECT ts, action, plate, detail FROM as_garage_logs
        WHERE action LIKE ? OR plate LIKE ? OR detail LIKE ? ORDER BY id DESC LIMIT 100]], { query, query, query })
    return rows or {}
end)
