local function isAdmin(src)
    return src == 0 or IsPlayerAceAllowed(src, Config.AdminAce)
end

local function persist(g)
    local data = {
        label = g.label, sub = g.sub, type = g.type, radius = g.radius, slots = g.slots, shared = g.shared,
        jobs = g.jobs, gangs = g.gangs, blip = g.blip,
        coords = { x = g.coords.x, y = g.coords.y, z = g.coords.z },
        spawns = {}, preview = g.preview and { x = g.preview.x, y = g.preview.y, z = g.preview.z, w = g.preview.w } or nil,
    }
    for i, s in ipairs(g.spawns) do data.spawns[i] = { x = s.x, y = s.y, z = s.z, w = s.w } end
    MySQL.update.await('INSERT INTO as_garage_locations (id, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)',
        { g.id, json.encode(data) })
end

local function refreshAll()
    LoadGarages()
    TriggerClientEvent('asg:refresh', -1)
end

lib.addCommand('asgarage', {
    help = 'Garage admin: create | spawn <id> | preview <id> | delete <id> | list | reload',
    params = {
        { name = 'action', type = 'string', help = 'create | spawn | preview | delete | list | reload' },
        { name = 'id', type = 'string', optional = true },
    },
    restricted = Config.AdminAce,
}, function(src, args)
    local action, id = args.action, args.id
    if action == 'create' then
        TriggerClientEvent('asg:admin:create', src)
    elseif action == 'spawn' or action == 'preview' then
        if not id or not Garages[id] then return Bridge.notify(src, 'Unknown garage id.', 'error') end
        TriggerClientEvent('asg:admin:capture', src, action, id)
    elseif action == 'delete' then
        local g = id and Garages[id]
        if not g then return Bridge.notify(src, 'Unknown garage id.', 'error') end
        if g.static then return Bridge.notify(src, 'This garage comes from config.lua. Remove it there.', 'error') end
        MySQL.update.await('DELETE FROM as_garage_locations WHERE id = ?', { id })
        refreshAll()
        Log('Garage deleted', ('%s deleted %s'):format(GetPlayerName(src), id))
        Bridge.notify(src, 'Garage deleted.', 'success')
    elseif action == 'list' then
        local lines = {}
        for gid, g in pairs(Garages) do
            lines[#lines + 1] = ('%s (%s) - %d spawns%s'):format(gid, g.type, #g.spawns, g.static and ' [config]' or '')
        end
        table.sort(lines)
        Bridge.notify(src, table.concat(lines, '\n'), 'inform')
    elseif action == 'reload' then
        refreshAll()
        Bridge.notify(src, 'Garages reloaded.', 'success')
    else
        Bridge.notify(src, 'Use: create | spawn | preview | delete | list | reload', 'error')
    end
end)

-- Client sends the dialog result plus its own position.
lib.callback.register('asg:admin:save', function(src, d, pos)
    if not isAdmin(src) or type(d) ~= 'table' or type(pos) ~= 'table' then return false end
    local id = tostring(d.id or ''):lower():gsub('[^%w_]', '')
    if id == '' or (Garages[id] and Garages[id].static) then return false, 'That id is taken or invalid.' end
    local kind = d.type
    if kind ~= 'public' and kind ~= 'job' and kind ~= 'gang' and kind ~= 'impound' then return false, 'Bad type.' end

    local g = {
        id = id, label = tostring(d.label or id):sub(1, 40), sub = tostring(d.sub or ''):sub(1, 60), type = kind,
        coords = vec3(pos.x, pos.y, pos.z), radius = 3.0, slots = math.min(math.max(math.floor(tonumber(d.slots) or 10), 1), 200),
        spawns = {}, shared = d.shared == true,
        blip = { sprite = kind == 'impound' and 68 or 357, color = kind == 'impound' and 1 or 3, scale = 0.7 },
    }
    local group = tostring(d.group or ''):gsub('%s', '')
    if kind == 'job' and group ~= '' then g.jobs = { [group] = 0 } g.shared = true end
    if kind == 'gang' and group ~= '' then g.gangs = { [group] = 0 } g.shared = true end
    Garages[id] = Normalise(g)
    persist(Garages[id])
    refreshAll()
    Log('Garage created', ('%s created %s (%s)'):format(GetPlayerName(src), id, kind))
    return true, 'Created. Now stand on a bay and run /asgarage spawn ' .. id
end)

lib.callback.register('asg:admin:point', function(src, action, id, pos)
    if not isAdmin(src) or not Garages[id] or Garages[id].static then return false, 'Edit config.lua garages in the file.' end
    local g = Garages[id]
    local p4 = vec4(pos.x, pos.y, pos.z, pos.w or 0.0)
    if action == 'spawn' then
        g.spawns[#g.spawns + 1] = p4
    else
        g.preview = p4
    end
    persist(g)
    refreshAll()
    return true
end)
