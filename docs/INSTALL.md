# Installation

## Requirements

| Resource | Notes |
| --- | --- |
| [ox_lib](https://github.com/overextended/ox_lib) | Callbacks, notifications, dialogs, points, vehicle properties |
| [oxmysql](https://github.com/overextended/oxmysql) | Database access |
| `qbx_core`, `qb-core` or `es_extended` | Auto-detected. Force one with `Config.Framework` |

A recent ox_lib is needed (3.x or newer). Optional: a vehicle keys resource (see `Config.GiveKeys`) and a fuel resource that works with ox_lib vehicle properties (for example `ox_fuel`).

## Steps

1. Put the `as-garages` folder in your `resources` directory.
2. In `server.cfg`, start it after the framework, `ox_lib` and `oxmysql`:

   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure qbx_core     # or qb-core / es_extended
   ensure as-garages
   ```

3. Give your admins permission to use `/asgarage`:

   ```cfg
   add_ace group.admin asgarages.admin allow
   ```

   If you changed `Config.AdminAce`, use that name instead.
4. Start the server. The tables are created automatically (`sql/install.sql` is only there for reference). Check the console for `[as-garages] Framework: ...`.
5. Open the editor with `/asgarage` and place your garages (see [ADMIN.md](ADMIN.md)), or edit `Config.Garages` in `config.lua`.

## What it changes in your database

- It adds its own tables: `as_garage_vehicles`, `as_garage_locations`, `as_garage_access`, `as_garage_logs`.
- It never changes your framework's vehicle table structure. It does update the props column (`mods` / `vehicle`) when a vehicle is stored, the stored/state/garage columns so phones and MDTs stay in sync, and the owner column when a player sells a vehicle.
- Vehicles it has never seen are treated as parked in `Config.DefaultGarage` the first time their owner opens a garage.

## Upgrading

Replace the folder and restart. New columns and tables are added automatically on start.

## Troubleshooting

- **"No supported framework found"**: start your framework before `as-garages`, or set `Config.Framework`.
- **Garages don't show**: check you are the right job/gang for job/gang garages. Public garages show for everyone. Run `/asgarage` and confirm the garage has an interaction point.
- **No vehicles in the list**: the vehicle must exist in `player_vehicles` / `owned_vehicles` for the player's identifier.
- **Cars spawn without keys**: set `Config.GiveKeys` for your keys resource.
- **The UI does not appear**: make sure `web/` files are listed in `fxmanifest.lua` and check the F8 console.
