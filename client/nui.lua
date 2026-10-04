Open = false
local Cur       -- { garage, data }
local OfficerVeh
local PropsCache = {}
local previewToken = 0

-- Game UI sounds. Set Config.Sounds = false to silence them.
local SOUNDS = {
    select = { 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    confirm = { 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    back = { 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
    error = { 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET' },
}
function Sfx(kind)
    local s = Config.Sounds and SOUNDS[kind]
    if s then PlaySoundFrontend(-1, s[1], s[2], true) end
end

function Strings()
    local t = {}
    for k, v in pairs(Locales.en) do t[k] = v end
    for k, v in pairs(Locales[Config.Locale] or {}) do t[k] = v end
    return t
end

function OpenNui(view, data)
    Open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', view = view, data = data, t = Strings(), theme = Config.Theme, sounds = Config.Sounds,
                     preview = { spin = Config.Preview.spin, lights = Config.Preview.lights } })
    Sfx('confirm')
end

function CloseNui()
    if not Open then return end
    Open = false
    Cur, OfficerVeh = nil, nil
    PropsCache = {}
    previewToken = previewToken + 1
    Preview.stop()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function describe(v)
    local hash = type(v.model) == 'number' and v.model or joaat(v.model or '')
    local label = VehLabel(v.model)
    local class = Config.Classes[GetVehicleClassFromName(hash)] or ''
    local nick = v.nick and v.nick ~= '' and v.nick or nil
    v.label = label
    v.name = nick or label
    v.cls = nick and (label .. (class ~= '' and ' · ' .. class or '')) or class
end

local function enrich(list)
    for _, v in ipairs(list) do describe(v) end
end

function OpenGarage(g)
    local data = lib.callback.await('asg:getGarage', false, g.id)
    if not data then return Notify('no_access') end
    if data.forSale then return BuyGarage(g) end
    enrich(data.vehicles)
    data.inInterior = IsInInterior()
    Cur = { garage = g, data = data }
    OpenNui(g.type == 'impound' and 'impound' or 'garage', data)
end

function OpenOfficer(veh)
    local plate = (GetVehicleNumberPlateText(veh) or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local lot, best = Config.DefaultImpound, nil
    local me = GetEntityCoords(cache.ped)
    for id, g in pairs(Garages) do
        if g.type == 'impound' then
            local d = #(me - g.coords)
            if not best or d < best then lot, best = id, d end
        end
    end
    OfficerVeh = { entity = veh, lot = lot }
    OpenNui('officer', { plate = plate, name = VehLabel(GetEntityModel(veh)), lot = lot })
end

local function findVehicle(plate)
    if not Cur then return end
    for i, v in ipairs(Cur.data.vehicles) do
        if v.plate == plate then return v, i end
    end
end

local function reply(cb, ok, key, extra)
    if not ok then
        Sfx('error')
        if key then Notify(key, extra) end
    end
    cb({ ok = ok })
end

local function nearbyPlayers()
    local out = {}
    for _, p in ipairs(lib.getNearbyPlayers(GetEntityCoords(cache.ped), 10.0, false)) do
        local id = GetPlayerServerId(p.id)
        out[#out + 1] = { id = id, label = 'ID ' .. id }
    end
    return out
end

-- Pick a free bay outside. Inside a walk-in interior streaming can hide outside vehicles, so
-- fall back to the first bay.
local function pickBay(g)
    local bay = FindBay(g)
    if not bay and IsInInterior() then bay = 1 end
    return bay
end

RegisterNUICallback('close', function(_, cb)
    Sfx('back')
    CloseNui()
    cb({})
end)

RegisterNUICallback('sfx', function(body, cb)
    Sfx(body.kind)
    cb({})
end)

RegisterNUICallback('takeOut', function(body, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local bay = pickBay(g)
    if not bay then Notify('blocked') return reply(cb, false) end
    local ok, res = lib.callback.await('asg:takeOut', false, g.id, body.plate, bay)
    if not ok then return reply(cb, false, res) end
    local label = VehLabel(res.model)
    CloseNui()
    cb({ ok = true })
    if IsInInterior() then ExitInterior() end
    if SpawnVehicle(res) then Notify('taken_out', label) end
end)

RegisterNUICallback('retrieve', function(body, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local bay = FindBay(g)
    if not bay then Notify('blocked') return reply(cb, false) end
    local ok, res, fee = lib.callback.await('asg:retrieve', false, g.id, body.plate, bay)
    if not ok then return reply(cb, false, res, fee) end
    local label = VehLabel(res.model)
    CloseNui()
    cb({ ok = true })
    if SpawnVehicle(res) then Notify('retrieved', label) end
end)

RegisterNUICallback('fav', function(body, cb)
    cb({ ok = lib.callback.await('asg:fav', false, body.plate) })
end)

RegisterNUICallback('locate', function(body, cb)
    local pos = lib.callback.await('asg:locate', false, body.plate)
    local v = findVehicle(body.plate)
    if not pos then Notify('vehicle_not_found') return reply(cb, false) end
    SetNewWaypoint(pos.x, pos.y)
    Notify('waypoint_set', v and v.name or body.plate)
    cb({ ok = true })
end)

-- 3D preview, with the vehicle's real mods once the server has handed them over.
RegisterNUICallback('preview', function(body, cb)
    cb({})
    local v = findVehicle(body.plate)
    if not v or not Cur then return end

    if IsInInterior() then
        local e = ShowroomVehicle(body.plate)
        if e then Preview.focus(e) end
        return
    end

    previewToken = previewToken + 1
    local token, g = previewToken, Cur.garage
    local props = PropsCache[body.plate]
    if props == nil then
        Preview.show(g, v.model) -- instant stock model while the mods load
        props = lib.callback.await('asg:props', false, g.id, body.plate) or false
        PropsCache[body.plate] = props
    end
    if token == previewToken and Cur and Cur.garage.id == g.id then
        Preview.show(g, v.model, props or nil)
    end
end)

RegisterNUICallback('rotate', function(body, cb)
    Preview.rotate(body.dx)
    cb({})
end)

RegisterNUICallback('camera', function(body, cb)
    Preview.setMode(body.mode)
    cb({})
end)

RegisterNUICallback('previewOpt', function(body, cb)
    Preview.setOption(body.key, body.value)
    cb({})
end)

RegisterNUICallback('rename', function(body, cb)
    local ok, nick = lib.callback.await('asg:rename', false, body.plate, body.name)
    if not ok then return reply(cb, false, nick) end
    local v = findVehicle(body.plate)
    if v then
        v.nick = nick ~= '' and nick or nil
        describe(v)
    end
    Notify('renamed', nick ~= '' and nick or (v and v.label or body.plate))
    cb({ ok = true, name = v and v.name, cls = v and v.cls, nick = v and v.nick })
end)

RegisterNUICallback('folder', function(body, cb)
    local ok, folder = lib.callback.await('asg:folder', false, body.plate, body.name)
    if not ok then return reply(cb, false, folder) end
    local v = findVehicle(body.plate)
    if v then v.folder = folder ~= '' and folder or nil end
    cb({ ok = true, folder = folder ~= '' and folder or nil })
end)

RegisterNUICallback('history', function(body, cb)
    cb(lib.callback.await('asg:history', false, body.plate) or {})
end)

RegisterNUICallback('targets', function(_, cb)
    local out = {}
    for id, g in pairs(Garages) do
        if Cur and id ~= Cur.garage.id and g.type ~= 'impound' and not g.forSale then
            out[#out + 1] = { id = id, label = g.label, fee = Config.TransferFee, delay = Config.TransferDelay }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    cb(out)
end)

RegisterNUICallback('transfer', function(body, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local ok, label, arrive = lib.callback.await('asg:transfer', false, body.plate, g.id, body.to)
    if not ok then return reply(cb, false, label, arrive) end
    local v = findVehicle(body.plate)
    if v then
        if arrive and arrive > 0 then v.status, v.arrive = 'transit', arrive else v.status = 'away' end
        v.at = label
    end
    Notify(arrive and arrive > 0 and 'transfer_started' or 'transfer_ok', v and v.name or body.plate, label)
    cb({ ok = true, at = label, arrive = arrive })
end)

RegisterNUICallback('nearby', function(_, cb)
    cb(nearbyPlayers())
end)

RegisterNUICallback('sell', function(body, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local ok, plate, price = lib.callback.await('asg:sell', false, g.id, body.plate, body.buyer, body.price)
    if not ok then return reply(cb, false, plate) end
    local v, i = findVehicle(body.plate)
    local name = v and v.name or body.plate
    if i then table.remove(Cur.data.vehicles, i) end
    Sfx('confirm')
    Notify('sold_to', name, price)
    cb({ ok = true })
end)

RegisterNUICallback('shareKeys', function(body, cb)
    local ok, name = lib.callback.await('asg:shareKeys', false, body.plate, body.buyer)
    if not ok then return reply(cb, false, name) end
    Sfx('confirm')
    Notify('keys_shared', name, Config.ShareKeys.minutes)
    cb({ ok = true })
end)

RegisterNUICallback('repair', function(body, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local ok, cost, extra = lib.callback.await('asg:repair', false, g.id, body.plate)
    if not ok then return reply(cb, false, cost, extra) end
    local v = findVehicle(body.plate)
    if v then v.eng, v.body, v.repair = 100, 100, 0 end
    Sfx('confirm')
    Notify('repaired', cost)
    cb({ ok = true })
end)

RegisterNUICallback('upgrade', function(_, cb)
    local g = Cur and Cur.garage
    if not g then return cb({}) end
    local ok, total, extra = lib.callback.await('asg:upgrade', false, g.id)
    if not ok then return reply(cb, false, total, extra) end
    local data = Cur.data
    data.garage.slots = total
    if data.upgrade then
        data.upgrade.extra = data.upgrade.extra + data.upgrade.per
        if data.upgrade.extra >= data.upgrade.max then data.upgrade = nil end
    end
    Sfx('confirm')
    Notify('upgraded', total)
    cb({ ok = true, slots = total, upgrade = data.upgrade })
end)

-- Private garage owner: manage who can use it, with ox_lib menus.
local function accessMenu(gid)
    local members = lib.callback.await('asg:members', false, gid) or {}
    local options = {{
        title = L('add_member'), icon = 'user-plus',
        onSelect = function()
            local near = nearbyPlayers()
            if #near == 0 then Notify('nobody_near') return accessMenu(gid) end
            local opts = {}
            for i, p in ipairs(near) do opts[i] = { value = p.id, label = p.label } end
            local input = lib.inputDialog(L('add_member'), { { type = 'select', label = L('add_member_input'), options = opts, required = true } })
            if input then
                local ok, res = lib.callback.await('asg:addMember', false, gid, input[1])
                if ok then Notify('member_added', res) else Notify(res) end
            end
            accessMenu(gid)
        end,
    }}
    for _, m in ipairs(members) do
        options[#options + 1] = {
            title = L('remove_member', m.name or m.identifier), icon = 'user-minus',
            onSelect = function()
                lib.callback.await('asg:removeMember', false, gid, m.identifier)
                Notify('member_removed')
                accessMenu(gid)
            end,
        }
    end
    if #members == 0 then options[#options + 1] = { title = L('no_members'), disabled = true } end
    lib.registerContext({ id = 'asg_access', title = L('access_title'), options = options })
    lib.showContext('asg_access')
end

RegisterNUICallback('access', function(_, cb)
    local g = Cur and Cur.garage
    cb({})
    if not g then return end
    CloseNui()
    accessMenu(g.id)
end)

RegisterNUICallback('impound', function(body, cb)
    if not OfficerVeh or not DoesEntityExist(OfficerVeh.entity) then CloseNui() return cb({}) end
    local veh, lot = OfficerVeh.entity, OfficerVeh.lot
    local props = lib.getVehicleProperties(veh)
    local ok, key, plate = lib.callback.await('asg:impound', false, NetworkGetNetworkIdFromEntity(veh), {
        reason = body.reason, fee = body.fee, hold = body.hold, ownerRelease = body.ownerRelease, lot = lot,
    }, props)
    CloseNui()
    cb({ ok = ok })
    Notify(key or 'unavailable', plate or VehLabel(props.model))
end)
