# Changelog

## 0.3.1

- Fix black boxes in the UI on FiveM browser builds that render `backdrop-filter` as solid black. All blur was removed and panels are slightly more opaque.
- The 3D preview falls back to the garage's first bay when no preview point is set.
- Vehicle keys: keys are given when a vehicle is taken out or retrieved, with built-in support for qbx_vehiclekeys, qb-vehiclekeys, Renewed-Vehiclekeys and ox_inventory item keys, plus a `custom` slot for any other script. Optional "keys required to store" and "remove keys on store". Lending keys uses the same setup. See `docs/KEYS.md`.
- The HUD and radar are hidden while a garage screen is open (`Config.HideHud`), with a hook for custom HUDs and a `as-garages:client:hudToggled` event.
- The default Legion Square garage now has 40 slots, so a server with many existing vehicles doesn't show "11 of 10".

## 0.3.0

- Walk-in garage interiors with a parked-car showroom (any MLO or IPL), in their own routing bucket.
- Target-eye interaction (`ox_target`, `qb-target`, or the `[E]` prompt, or both) with per-kind icons and labels.
- Preview camera modes (front, side, rear, cabin, engine bay, wheel), an optional turntable and headlights.
- Plates are drawn in the vehicle's real plate style. Folders for organising vehicles. Per-vehicle history.
- Lend keys to a nearby player for a set time. Repair stored vehicles from the garage screen. Fuel resource hooks.
- Garage upgrades (extra slots) for private garages.
- Optional delayed transfers (`Config.TransferDelay`, instant by default).
- Abandoned vehicles are impounded or returned to their garage (configurable).
- Admin: stats dashboard, bulk tools, duplicate plate scanner, orphan cleanup, garage export and import.
- Temporary garage API for housing scripts, more exports (`GetGarages`, `ImpoundVehicle`, `SetVehicleCondition`, ...) and server events. See `docs/API.md`.
- Keyboard navigation and best-effort gamepad support in the UI.

## 0.2.0

- Transfer a vehicle between your garages (`Config.TransferFee`), rename it with a nickname, and sell or gift it to a nearby player with a buyer confirmation.
- 3D preview now shows the vehicle's real colours and mods.
- Private / house garages: for-sale garages, an owner, a member list, and exports for housing scripts.
- In-game admin editor (`/asgarage`): garage list and form, in-world placement of points, vehicle browser with force-return, and a log viewer.
- Garages can limit accepted vehicle classes (cars, bikes, boats, air).
- Light and dark themes with a configurable accent colour, menu sounds and animations.
- New languages: French, German, Portuguese, Italian (plus English and Spanish).
- Documentation in `docs/`.
- Security: players can only store vehicles they own, even in shared garages.

## 0.1.0

- First release: public, job and gang garages, impound, framework bridge, persistence, NUI, admin commands.
