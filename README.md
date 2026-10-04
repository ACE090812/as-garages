# as-garages

Modern garages and impound for FiveM. Works on **QBCore**, **Qbox** and **ESX** (auto-detected).

> Status: v0.2.0. The code has been syntax-checked but **not yet tested on a live server**. Expect to tune coordinates and fix small things on first run.

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- One of `qbx_core`, `qb-core`, `es_extended`

## Quick start

1. Drop `as-garages` in your resources and `ensure` it after your framework, `ox_lib` and `oxmysql`.
2. `add_ace group.admin asgarages.admin allow`
3. Start the server. Tables are created automatically.
4. Run `/asgarage` in game to place your garages.

Full guides: [Install](docs/INSTALL.md) · [Configuration](docs/CONFIGURATION.md) · [Admin](docs/ADMIN.md) · [Exports](docs/EXPORTS.md) · [FAQ](docs/FAQ.md) · [Changelog](CHANGELOG.md)

## Features

- **Garage types:** public, job, gang, private / house (buy, share with members) and impound lots. Optional class filter (cars, bikes, boats, air).
- **Vehicle persistence:** fuel, engine and body health, mileage and all mods, via `ox_lib` vehicle properties.
- **Modern UI:** glass-style panels, 3D preview with the vehicle's real mods (drag to rotate), search, favourites, live status, light and dark themes with your own accent colour, menu sounds and animations.
- **Player tools:** transfer between your garages, rename with a nickname, and sell or gift to a nearby player with a buyer confirmation.
- **Impound:** `/impound` for officers (reason, fee, minimum hold, who can release). Owners pay the fee plus daily storage, officers release for free. Lost vehicles go to the impound or back to their garage.
- **Admin editor (`/asgarage`):** create and edit garages, place points in the world, browse and force-return vehicles, read the logs.
- **Integration:** server exports for housing scripts, `GetVehicleState` for phones and MDTs, a keys hook, Discord webhook logging.
- **Languages:** English, Spanish, French, German, Portuguese, Italian.

### Security

- Every action is checked on the server: ownership, job or gang, distance to the garage and slot limits. Players can only store vehicles they own.
- A vehicle's row is flipped atomically before anything spawns, so the same plate can't be taken out twice. If the spawn fails, the state and any fee are rolled back.
- Sales and transfers lock the plate, re-check everything after the buyer accepts, and refund on failure.
- The client never decides what is stored or charged. Props are sanitised and mileage is clamped.

## Known limits

- Private garages are bought, not rented.
- The admin editor is English only.
- Housing scripts are not integrated out of the box. Use the [exports](docs/EXPORTS.md).
- Vehicles with no record are assumed to be parked in `Config.DefaultGarage`.
- The coordinates in `config.lua` are rough starting points. Re-place them with `/asgarage`.
