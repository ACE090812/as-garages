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
function SaveGarage(d, actor, quiet)
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
        extra = existing and existing.extra or nil,
    }

    -- Optional walk-in interior (entry point inside, exit point, showroom bays).
    local ci = type(d.interior) == 'table' and d.interior or nil
    local enter = ci and point(ci.enter, true)
    if enter then
        g.interior = { enter = enter, exit = point(ci.exit) or point(ci.enter), bays = {},
                       ipl = type(ci.ipl) == 'string' and ci.ipl ~= '' and ci.ipl:sub(1, 64) or nil }
        for _, b in ipairs(type(ci.bays) == 'table' and ci.bays or {}) do
            local bay = point(b, true)
            if bay and #g.interior.bays < 12 then g.interior.bays[#g.interior.bays + 1] = bay end
        end
    end

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
    if not quiet then RefreshAll() end
    Log('Garage saved', ('%s saved garage %s (%s)'):format(actor or 'system', id, g.type), nil, id)
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

-- Stats ---------------------------------------------------------------------------------------

lib.callback.register('asg:admin:stats', function(src)
    if not isAdmin(src) then return nil end
    local now = os.time()
    local totals = MySQL.single.await([[SELECT COUNT(*) AS total, COALESCE(SUM(state = 1), 0) AS stored,
        COALESCE(SUM(state = 0), 0) AS out_, COALESCE(SUM(state = 2), 0) AS impounded FROM as_garage_vehicles]]) or {}
    local garages = 0
    for _ in pairs(Garages) do garages = garages + 1 end

    -- last 7 rolling days: index 0 = the last 24 hours
    local days = {}
    for d = 6, 0, -1 do days[#days + 1] = { label = os.date('%a', now - d * 86400), d = d, takeouts = 0, stores = 0, impounds = 0 } end
    local rows = MySQL.query.await([[SELECT FLOOR((? - ts) / 86400) AS d, action, COUNT(*) AS c FROM as_garage_logs
        WHERE ts > ? AND action IN ('Vehicle taken out', 'Vehicle stored', 'Vehicle impounded') GROUP BY d, action]],
        { now, now - 7 * 86400 }) or {}
    for _, r in ipairs(rows) do
        for _, day in ipairs(days) do
            if day.d == r.d then
                if r.action == 'Vehicle taken out' then day.takeouts = r.c
                elseif r.action == 'Vehicle stored' then day.stores = r.c
                else day.impounds = r.c end
            end
        end
    end

    local revenue = {}
    for _, r in ipairs(MySQL.query.await([[SELECT action, COALESCE(SUM(amount), 0) AS total, COUNT(*) AS c FROM as_garage_logs
        WHERE ts > ? AND amount > 0 GROUP BY action ORDER BY total DESC]], { now - 30 * 86400 }) or {}) do
        revenue[#revenue + 1] = { action = r.action, total = r.total, count = r.c }
    end

    local top = {}
    for _, r in ipairs(MySQL.query.await([[SELECT garage, COUNT(*) AS c FROM as_garage_logs
        WHERE ts > ? AND garage IS NOT NULL AND action IN ('Vehicle taken out', 'Vehicle stored')
        GROUP BY garage ORDER BY c DESC LIMIT 6]], { now - 30 * 86400 }) or {}) do
        top[#top + 1] = { garage = Garages[r.garage] and Garages[r.garage].label or r.garage, count = r.c }
    end

    return {
        totals = { vehicles = totals.total or 0, stored = totals.stored or 0, out = totals.out_ or 0, impounded = totals.impounded or 0, garages = garages },
        days = days, revenue = revenue, top = top,
    }
end)

-- Bulk tools ----------------------------------------------------------------------------------

lib.callback.register('asg:admin:tool', function(src, kind, args)
    if not isAdmin(src) then return false, 'No permission.' end
    args = type(args) == 'table' and args or {}
    local who = GetPlayerName(src)

    if kind == 'returnStuck' then
        local keep = {}
        for plate in pairs(Spawned) do keep[#keep + 1] = plate end
        local n
        if #keep > 0 then
            n = MySQL.update.await('UPDATE as_garage_vehicles SET state = 1 WHERE state = 0 AND plate NOT IN (?)', { keep })
        else
            n = MySQL.update.await('UPDATE as_garage_vehicles SET state = 1 WHERE state = 0')
        end
        Log('Admin tool', ('%s returned %d stuck vehicles to their garages'):format(who, n))
        return true, ('%d vehicles returned to their garages.'):format(n)

    elseif kind == 'moveGarage' then
        local from, to = Garages[tostring(args.from)], Garages[tostring(args.to)]
        if not from or not to or from == to or from.type == 'impound' or to.type == 'impound' then return false, 'Pick two different normal garages.' end
        local n = MySQL.update.await('UPDATE as_garage_vehicles SET garage = ? WHERE garage = ? AND state = 1', { to.id, from.id })
        Log('Admin tool', ('%s moved %d vehicles from %s to %s'):format(who, n, from.id, to.id), nil, to.id)
        return true, ('%d vehicles moved to %s.'):format(n, to.label)

    elseif kind == 'releaseOldImpounds' then
        local days = math.max(math.floor(tonumber(args.days) or 30), 1)
        local n = MySQL.update.await('UPDATE as_garage_vehicles SET state = 1, garage = ? WHERE state = 2 AND impound_at < ?',
            { Config.DefaultGarage, os.time() - days * 86400 })
        Log('Admin tool', ('%s released %d vehicles impounded for more than %d days'):format(who, n, days))
        return true, ('%d old impounds released to %s.'):format(n, Config.DefaultGarage)

    elseif kind == 'cleanOrphans' then
        local n = Bridge.cleanOrphans()
        Log('Admin tool', ('%s removed %d orphaned garage records'):format(who, n))
        return true, ('%d orphaned records removed.'):format(n)

    elseif kind == 'purgeLogs' then
        local days = math.max(math.floor(tonumber(args.days) or 30), 1)
        local n = MySQL.update.await('DELETE FROM as_garage_logs WHERE ts < ?', { os.time() - days * 86400 })
        return true, ('%d log entries deleted.'):format(n)

    elseif kind == 'scanDuplicates' then
        local list = Bridge.findDuplicatePlates()
        return true, #list == 0 and 'No duplicate plates found.' or ('%d duplicated plates found.'):format(#list), list
    end
    return false, 'Unknown tool.'
end)

-- Export / import garages ---------------------------------------------------------------------

lib.callback.register('asg:admin:export', function(src)
    if not isAdmin(src) then return nil end
    local list = {}
    for _, g in pairs(Garages) do
        if not g.temp then
            local row = Plain(g, true)
            row.group = g.type == 'job' and groupString(g.jobs) or g.type == 'gang' and groupString(g.gangs) or ''
            row.owner, row.ownerName, row.override, row.inConfig, row.forSale, row.extra = nil, nil, nil, nil, nil, nil
            row.slots = g.slots
            list[#list + 1] = row
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return json.encode({ format = 'as-garages', version = 1, garages = list })
end)

lib.callback.register('asg:admin:import', function(src, text)
    if not isAdmin(src) then return false, 'No permission.' end
    local ok, data = pcall(json.decode, tostring(text or ''))
    if not ok or type(data) ~= 'table' then return false, 'That is not valid JSON.' end
    local list = data.garages or data
    if type(list) ~= 'table' or #list == 0 then return false, 'No garages found in that text.' end

    local saved, errors = 0, {}
    for _, d in ipairs(list) do
        local done, msg = SaveGarage(d, GetPlayerName(src), true)
        if done then saved = saved + 1 else errors[#errors + 1] = ('%s: %s'):format(tostring(d.id), msg) end
    end
    RefreshAll()
    local message = ('%d garages imported.'):format(saved)
    if #errors > 0 then message = message .. ' Skipped: ' .. table.concat(errors, ' | '):sub(1, 300) end
    return saved > 0, message
end)
