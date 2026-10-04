# Configuration

Everything lives in `config.lua`. Each option is commented there; this page explains the ones that need context.

## General

| Option | Default | What it does |
| --- | --- | --- |
| `Framework` | `'auto'` | `'auto'`, `'qbx'`, `'qb'` or `'esx'` |
| `Locale` | `'en'` | `en`, `es`, `fr`, `de`, `pt`, `it` |
| `DefaultGarage` | `'legion_square'` | Where vehicles the script has never seen are assumed to be parked |
| `DefaultImpound` | `'davis_impound'` | Impound lot used by `/impound` and lost vehicles |
| `PayWith` | `{ 'cash', 'bank' }` | Accounts tried in order for fees and sales |
| `WarpIntoVehicle` | `true` | Put the player in the driver seat after taking a vehicle out |

## Lost vehicles

A vehicle that is out and then disappears (deleted, server restart) is handled by `StuckBehaviour`:

- `'impound'` sends it to `DefaultImpound` with `StuckImpoundFee`.
- `'garage'` puts it back in the garage it left from.

`WatchSpawned` checks every 30 seconds that spawned vehicles still exist. Two misses in a row count as lost. Turn it off if your server culls empty vehicles and you see false impounds.

## Impound

| Option | What it does |
| --- | --- |
| `ImpoundJobs` | `{ job = minGrade }` who can use `/impound` and release vehicles for free |
| `MaxImpoundFee` | Highest fee an officer can set |
| `StoragePerDay`, `MaxStorageDays` | Daily storage added to the fee, capped at that many days |

## Players

| Option | What it does |
| --- | --- |
| `TransferFee` | Cost to move a vehicle to another of your garages |
| `MaxSalePrice` | Highest price for a player-to-player sale (0 = gift) |
| `MaxPrivateGarages` | Private garages one player can own |
| `MaxMembers` | People an owner can share a private garage with |

## UI

- `Theme = { mode = 'dark' | 'light', accent = '#A594FF' }`. Players can also flip light/dark in the UI, and their choice is remembered on their machine. The accent can be any hex colour; text colours are chosen automatically for contrast.
- `Sounds = true` plays the game's menu sounds. Set `false` to silence them.

## Logging

- `Webhook`: a Discord webhook URL. Leave empty to log only to the database.
- `LogDays`: how long database logs are kept (they are shown in the admin editor's Logs tab).

## Keys

`GiveKeys(vehicle, plate)` runs on the client after a vehicle spawns. The default handles `qbx_vehiclekeys` and `qb-vehiclekeys`. Replace it for any other keys resource.

## Defining garages in `config.lua`

```lua
{
    id = 'legion_square', label = 'Legion Square', sub = 'Public garage · Vinewood',
    type = 'public',                       -- public | job | gang | private | impound
    coords = vec3(215.8, -810.1, 30.7),    -- where the player presses E
    radius = 3.0, slots = 10,
    spawns = { vec4(222.1, -804.6, 30.0, 248.0) },   -- bays; blocked bays are skipped
    preview = vec4(...),                   -- optional: where the 3D preview car is shown
    jobs = { police = 0 },                 -- job garages: { job = minGrade }
    gangs = { families = 0 },              -- gang garages
    shared = true,                         -- job/gang: everyone in the group sees all stored vehicles
    price = 250000,                        -- private garages: price (no owner = for sale)
    vehicleClasses = { 'cars', 'bikes' },  -- optional filter: cars | bikes | boats | air
    blip = { sprite = 357, color = 3, scale = 0.7 },
}
```

Garages edited in the admin editor are saved to the database and override a `config.lua` entry with the same id. "Reset to config" in the editor removes the override.

The coordinates shipped in `config.lua` are rough starting points. Re-place them with `/asgarage`.

## Translating

Copy `locales/en.lua`, rename the table (`Locales.xx`), translate the values, and set `Config.Locale = 'xx'`. Missing keys fall back to English. The admin editor is English only.
