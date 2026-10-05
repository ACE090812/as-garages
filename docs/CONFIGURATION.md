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

## Interaction (prompt, target, both)

`Config.Interaction.mode`:

- `'prompt'` shows the `[E]` text prompt (default).
- `'target'` uses your target eye on foot. Storing a vehicle still uses the `[E]` prompt while you sit in it, because target eyes don't work from inside a vehicle.
- `'both'` offers either.

`Config.Interaction.target` picks `'auto'`, `'ox_target'` or `'qb-target'`. `options` sets the icon and label per kind (garage, impound, buy, interior). If the target resource isn't running, the script falls back to the prompt.

## Delivery, abandoned vehicles, repairs, keys

- `TransferDelay`: seconds a transferred vehicle takes to arrive. `0` (default) is instant. Vehicles in transit can't be taken out or sold until they arrive.
- `Abandoned`: a vehicle with nobody in it and no player within `radius` for `minutes` is impounded (`action = 'impound'`, with `fee`) or returned to its garage (`action = 'garage'`).
- `Repair`: `pricePerPercent` for each missing percent of engine plus body health. Repairs happen from the garage screen for stored vehicles.
- `ShareKeys`: lend keys for `minutes` through `Config.Keys` (see [KEYS.md](KEYS.md)). The vehicle must be out.
- `Upgrades`: price, slots per purchase and the maximum extra slots for private garages.
- `Fuel`: `get` and `set` hooks. Defaults cover `ox_fuel`, `LegacyFuel`, `cdn-fuel` and `ps-fuel`.
- `Preview`: turntable and headlights defaults for the 3D preview. Players can toggle both in the UI.
- `HistoryDays`: how long per-vehicle history is kept.

## UI

- `Theme = { mode = 'dark' | 'light', accent = '#A594FF' }`. Players can also flip light/dark in the UI, and their choice is remembered on their machine. The accent can be any hex colour; text colours are chosen automatically for contrast.
- `Sounds = true` plays the game's menu sounds. Set `false` to silence them.
- `HideHud`: hides the radar and HUD while a garage screen is open and restores it afterwards (`enabled = true` by default). The default game HUD is handled automatically. For a custom HUD resource, fill in `hook(hidden)` with that HUD's own export or event.
- Keyboard: arrow keys browse, Enter takes the main action, `1`-`6` switch preview camera, `F` favourites. A gamepad works where the game's browser exposes it (D-pad, A, B, bumpers).

## Logging

- `Webhook`: a Discord webhook URL. Leave empty to log only to the database.
- `LogDays`: how long database logs are kept (they are shown in the admin editor's Logs tab).

## Keys

`Config.Keys` connects your keys resource (qbx_vehiclekeys, qb-vehiclekeys, Renewed-Vehiclekeys, ox_inventory item keys, or your own script). See [KEYS.md](KEYS.md).

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
    interior = { ... },                    -- optional walk-in interior, see INTERIORS.md
    blip = { sprite = 357, color = 3, scale = 0.7 },
}
```

Garages edited in the admin editor are saved to the database and override a `config.lua` entry with the same id. "Reset to config" in the editor removes the override.

The coordinates shipped in `config.lua` are rough starting points. Re-place them with `/asgarage`.

## Translating

Copy `locales/en.lua`, rename the table (`Locales.xx`), translate the values, and set `Config.Locale = 'xx'`. Missing keys fall back to English. The admin editor is English only.
