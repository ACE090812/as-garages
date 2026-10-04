Bridge = {}

local fw, Core, ESX

local function detect()
    if Config.Framework ~= 'auto' then return Config.Framework end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
end

local function init()
    fw = detect()
    if fw == 'qb' then
        Core = exports['qb-core']:GetCoreObject()
    elseif fw == 'esx' then
        ESX = exports['es_extended']:getSharedObject()
    end
    return fw
end

-- Frameworks may start after us; wait for one.
function Bridge.waitReady()
    local waited = 0
    while not init() and waited < 15000 do
        Wait(500)
        waited = waited + 500
    end
    if not fw then
        print('^1[as-garages] No supported framework found (qbx_core, qb-core, es_extended).^0')
        return false
    end
    print(('^2[as-garages] Framework: %s^0'):format(fw))
    return true
end

function Bridge.framework() return fw end

local function qbPlayer(src)
    if fw == 'qbx' then return exports.qbx_core:GetPlayer(src) end
    return Core.Functions.GetPlayer(src)
end

---@return table? { id, name, job, grade, gang, gangGrade }
function Bridge.getPlayer(src)
    if fw == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        if not x then return end
        return { id = x.identifier, name = x.getName and x.getName() or GetPlayerName(src),
                 job = x.job.name, grade = x.job.grade }
    end
    local pl = qbPlayer(src)
    if not pl then return end
    local d = pl.PlayerData
    local ci = d.charinfo
    return {
        id = d.citizenid,
        name = ci and ((ci.firstname or '') .. ' ' .. (ci.lastname or '')) or GetPlayerName(src),
        job = d.job and d.job.name,
        grade = d.job and d.job.grade and d.job.grade.level or 0,
        gang = d.gang and d.gang.name,
        gangGrade = d.gang and d.gang.grade and d.gang.grade.level or 0,
    }
end

-- tbl is { name = minGrade }
function Bridge.hasGroup(name, grade, tbl)
    if not name or not tbl then return false end
    local min = tbl[name]
    return min ~= nil and (grade or 0) >= min
end

function Bridge.pay(src, amount, reason)
    if amount <= 0 then return true end
    if fw == 'esx' then
        local x = ESX.GetPlayerFromId(src)
        for _, acc in ipairs(Config.PayWith) do
            local a = acc == 'cash' and 'money' or acc
            local account = x.getAccount(a)
            if account and account.money >= amount then
                x.removeAccountMoney(a, amount, reason)
                return true
            end
        end
        return false
    end
    local pl = qbPlayer(src)
    for _, acc in ipairs(Config.PayWith) do
        if (pl.Functions.GetMoney(acc) or 0) >= amount then
            return pl.Functions.RemoveMoney(acc, amount, reason) ~= false
        end
    end
    return false
end

function Bridge.refund(src, amount, reason)
    if amount <= 0 then return end
    local acc = Config.PayWith[1] or 'bank'
    if fw == 'esx' then
        ESX.GetPlayerFromId(src).addAccountMoney(acc == 'cash' and 'money' or acc, amount, reason)
    else
        qbPlayer(src).Functions.AddMoney(acc, amount, reason)
    end
end

function Bridge.notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { description = msg, type = kind or 'inform' })
end

-- Vehicle rows from the framework's own table. The garage never edits anything but
-- the props column and the stored/state/garage compatibility columns.
local function decode(str)
    local ok, t = pcall(json.decode, str or '{}')
    return ok and type(t) == 'table' and t or {}
end

local function fromRow(r)
    if fw == 'esx' then
        local props = decode(r.vehicle)
        return { owner = r.owner, plate = NormPlate(r.plate), model = props.model, props = props }
    end
    return { owner = r.citizenid, plate = NormPlate(r.plate), model = r.vehicle, props = decode(r.mods) }
end

function Bridge.getVehicle(plate)
    local r
    if fw == 'esx' then
        r = MySQL.single.await('SELECT owner, plate, vehicle FROM owned_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
    else
        r = MySQL.single.await('SELECT citizenid, plate, vehicle, mods FROM player_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
    end
    return r and fromRow(r) or nil
end

function Bridge.getOwned(id)
    local rows
    if fw == 'esx' then
        rows = MySQL.query.await('SELECT owner, plate, vehicle FROM owned_vehicles WHERE owner = ?', { id })
    else
        rows = MySQL.query.await('SELECT citizenid, plate, vehicle, mods FROM player_vehicles WHERE citizenid = ?', { id })
    end
    local out = {}
    for i, r in ipairs(rows or {}) do out[i] = fromRow(r) end
    return out
end

function Bridge.saveProps(plate, props)
    if fw == 'esx' then
        MySQL.update.await('UPDATE owned_vehicles SET vehicle = ? WHERE TRIM(plate) = ?', { json.encode(props), plate })
    else
        MySQL.update.await('UPDATE player_vehicles SET mods = ? WHERE TRIM(plate) = ?', { json.encode(props), plate })
    end
end

-- Keeps other resources that read the native columns (phones, MDTs) roughly in sync.
function Bridge.setNative(plate, stored, garage)
    if fw == 'esx' then
        MySQL.update('UPDATE owned_vehicles SET stored = ? WHERE TRIM(plate) = ?', { stored and 1 or 0, plate })
    else
        MySQL.update('UPDATE player_vehicles SET state = ?, garage = ? WHERE TRIM(plate) = ?',
            { stored and 1 or 0, garage, plate })
    end
end

-- Pay a player money (used for sale proceeds and refunds).
function Bridge.give(src, amount, reason)
    Bridge.refund(src, amount, reason)
end

-- Hand a vehicle to a new owner in the framework's own table.
function Bridge.setOwner(plate, newOwnerId, newOwnerSrc)
    if fw == 'esx' then
        MySQL.update.await('UPDATE owned_vehicles SET owner = ? WHERE TRIM(plate) = ?', { newOwnerId, plate })
    else
        local license = GetPlayerIdentifierByType(newOwnerSrc, 'license')
        MySQL.update.await('UPDATE player_vehicles SET citizenid = ?, license = ? WHERE TRIM(plate) = ?',
            { newOwnerId, license, plate })
    end
end

-- Maintenance helpers for the admin tools --------------------------------------------------

-- Plates that appear more than once in the framework's vehicle table (compared trimmed, upper-case).
function Bridge.findDuplicatePlates()
    local rows
    if fw == 'esx' then
        rows = MySQL.query.await([[SELECT UPPER(TRIM(plate)) AS p, COUNT(*) AS c, GROUP_CONCAT(owner SEPARATOR ', ') AS owners
            FROM owned_vehicles GROUP BY p HAVING c > 1 LIMIT 100]])
    else
        rows = MySQL.query.await([[SELECT UPPER(TRIM(plate)) AS p, COUNT(*) AS c, GROUP_CONCAT(citizenid SEPARATOR ', ') AS owners
            FROM player_vehicles GROUP BY p HAVING c > 1 LIMIT 100]])
    end
    local out = {}
    for i, r in ipairs(rows or {}) do out[i] = { plate = r.p, count = r.c, owners = r.owners } end
    return out
end

-- Removes garage records whose vehicle no longer exists in the framework table. Returns how many.
function Bridge.cleanOrphans()
    if fw == 'esx' then
        return MySQL.update.await([[DELETE v FROM as_garage_vehicles v LEFT JOIN owned_vehicles o ON UPPER(TRIM(o.plate)) = v.plate
            WHERE o.plate IS NULL]])
    end
    return MySQL.update.await([[DELETE v FROM as_garage_vehicles v LEFT JOIN player_vehicles o ON UPPER(TRIM(o.plate)) = v.plate
        WHERE o.plate IS NULL]])
end
