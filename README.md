# as-garages

Modern garages and impound for FiveM. Works on **QBCore**, **Qbox** and **ESX** (auto-detected).

> Status: v0.1.0, first working build. It has been syntax-checked but **not yet tested on a live server**. Expect to tune coordinates and fix small things on first run.

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- One of `qbx_core`, `qb-core`, `es_extended`

## Install

1. Drop the `as-garages` folder in your resources and `ensure as-garages` after your framework, `ox_lib` and `oxmysql`.
2. Tables are created on first start (`sql/install.sql` is there for reference). Your framework's vehicle table (`player_vehicles` / `owned_vehicles`) is never altered except for its props and stored/state columns, which are kept in sync so phones and MDTs keep working.
3. Give admins the permission: `add_ace group.admin asgarages.admin allow`
4. Edit `config.lua`, then place your real garages in game (below).

## Features

- Public, job and gang garages, plus impound lots. Job and gang garages can be shared by the whole group.
- Vehicle persistence: fuel, engine and body health, mileage and all mods (via `ox_lib` vehicle properties).
- Glass-style UI with 3D vehicle preview (drag to rotate), search, favourites and live status (stored, out, impounded, in another garage).
- Impound: officers use `/impound` (reason, fee, minimum hold, who can release it). Owners pay the fee plus daily storage. Officers release for free.
- Vehicles that are lost (deleted, or still out after a restart) go to the impound or back to their garage, your choice (`Config.StuckBehaviour`).
- In-game admin tools, no restarts needed.
- Discord webhook logging, English and Spanish locales.

### Security

- Every action is checked on the server: ownership, job or gang, distance to the garage and slot limits.
- A vehicle's row is flipped atomically before anything spawns, so the same plate can't be taken out twice. If the spawn fails, the state and any fee are rolled back.
- The client never decides what is stored or charged; props are sanitised and mileage is clamped.

## Admin commands

Stand where you want the garage, then:

| Command | What it does |
| --- | --- |
| `/asgarage create` | Dialog for id, label, type, slots, job/gang. Uses your position as the interaction point |
| `/asgarage spawn <id>` | Add a bay at your position (or your vehicle's, with its heading). Repeat for more bays |
| `/asgarage preview <id>` | Set where the 3D preview vehicle is shown |
| `/asgarage delete <id>` | Remove a garage made in game |
| `/asgarage list` / `reload` | List or reload garages |

Garages in `config.lua` can't be edited in game. The coordinates shipped there are rough starting points, so re-place them or replace them.

## Known limits (v0.1)

- Transfer, Rename and Sell buttons are in the UI but disabled.
- The 3D preview shows the stock model, not the player's colours and mods.
- Admin editing is via commands and dialogs, not the full editor screen from the mockups.
- Vehicles with no record are assumed to be parked in `Config.DefaultGarage`.
- Keys: set `Config.GiveKeys` for your keys resource (qb/qbx vehiclekeys handled by default).
