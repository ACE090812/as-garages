Config = {}

-- 'auto' detects qbx_core, qb-core or es_extended. Force with 'qbx', 'qb' or 'esx'.
Config.Framework = 'auto'
Config.Locale = 'en'
Config.Debug = false

-- Vehicles that are owned but have never been in a garage (new dealership buys,
-- or vehicles from before this script was installed) start here.
Config.DefaultGarage = 'legion_square'
Config.DefaultImpound = 'davis_impound'

-- Accounts tried in order when paying impound fees.
Config.PayWith = { 'cash', 'bank' }

-- A vehicle that is out and then lost (deleted, server restart) goes to:
--   'impound' -> the default impound lot, with Config.StuckImpoundFee
--   'garage'  -> back into the garage it left from
Config.StuckBehaviour = 'impound'
Config.StuckImpoundFee = 250
-- Check every 30s that spawned vehicles still exist. Two misses in a row = lost.
Config.WatchSpawned = true

-- Impound
Config.ImpoundJobs = { police = 0, sheriff = 0 } -- job = minimum grade
Config.MaxImpoundFee = 50000
Config.StoragePerDay = 50
Config.MaxStorageDays = 7

Config.WarpIntoVehicle = true

-- Moving a vehicle between your garages
Config.TransferFee = 100
-- Player-to-player sales (set the price to 0 to gift a vehicle)
Config.MaxSalePrice = 10000000

-- Private / house garages
Config.MaxPrivateGarages = 2   -- per player
Config.MaxMembers = 5          -- people an owner can share a private garage with

-- Logs shown in the admin editor are kept this many days
Config.LogDays = 30

-- UI. mode: 'dark' | 'light' (players can also toggle it in the UI). accent: any hex colour.
Config.Theme = { mode = 'dark', accent = '#A594FF' }
-- Game sounds for UI clicks
Config.Sounds = true

-- Ace permission for /asgarage (add_ace group.admin asgarages.admin allow)
Config.AdminAce = 'asgarages.admin'

-- Discord webhook for logs (take out, store, impound, retrieve, admin). '' = off.
Config.Webhook = ''

-- Hook for your keys resource. Runs on the client after a vehicle spawns.
Config.GiveKeys = function(vehicle, plate)
    if GetResourceState('qbx_vehiclekeys') == 'started' then
        exports.qbx_vehiclekeys:GiveKeys(vehicle)
    elseif GetResourceState('qb-vehiclekeys') == 'started' then
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    end
end

Config.Classes = {
    [0] = 'Compact', [1] = 'Sedan', [2] = 'SUV', [3] = 'Coupe', [4] = 'Muscle', [5] = 'Sports classic',
    [6] = 'Sports', [7] = 'Super', [8] = 'Motorcycle', [9] = 'Off-road', [10] = 'Industrial',
    [11] = 'Utility', [12] = 'Van', [13] = 'Cycle', [14] = 'Boat', [15] = 'Helicopter', [16] = 'Plane',
    [17] = 'Service', [18] = 'Emergency', [19] = 'Military', [20] = 'Commercial', [21] = 'Train',
}

--[[
    Garages. Types:
      public   anyone, shows the player's own vehicles
      job      needs a job in `jobs` (name = min grade). `shared = true` lists every vehicle stored here
      gang     needs a gang in `gangs`. Same `shared` rule
      impound  lot for impounded vehicles

    spawns   list of vec4 bays. A bay is skipped if a vehicle is on it.
    preview  optional vec4 where the 3D preview vehicle is shown (camera is placed automatically)

    NOTE: the coordinates below are starting points. Stand where you want a garage and use
    /asgarage create, /asgarage spawn <id>, /asgarage preview <id> to place them in game.
]]
Config.Garages = {
    {
        id = 'legion_square', label = 'Legion Square', sub = 'Public garage · Vinewood',
        type = 'public', coords = vec3(215.8, -810.1, 30.7), radius = 3.0, slots = 10,
        spawns = { vec4(222.1, -804.6, 30.0, 248.0), vec4(224.9, -801.3, 30.0, 248.0) },
        blip = { sprite = 357, color = 3, scale = 0.7 },
    },
    {
        id = 'mission_row_pd', label = 'Mission Row PD', sub = 'Police garage',
        type = 'job', jobs = { police = 0 }, shared = true,
        coords = vec3(452.6, -1018.2, 28.5), radius = 3.0, slots = 20,
        spawns = { vec4(446.3, -1025.6, 28.6, 5.0), vec4(442.9, -1025.9, 28.7, 5.0) },
        blip = { sprite = 357, color = 38, scale = 0.7 },
    },
    {
        id = 'davis_impound', label = 'Davis Impound', sub = 'Impound lot',
        type = 'impound', coords = vec3(409.0, -1623.0, 29.3), radius = 3.0, slots = 40,
        spawns = { vec4(401.0, -1631.5, 29.3, 228.0), vec4(397.5, -1627.5, 29.3, 228.0) },
        blip = { sprite = 68, color = 1, scale = 0.7 },
    },
}
