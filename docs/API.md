# API: exports and events

All exports are **server side**: `exports['as-garages']:Name(...)`. Events are local server events you can listen to with `AddEventHandler`.

## Exports

| Export | Returns | What it does |
| --- | --- | --- |
| `GetGarages()` | list | All garages (plain tables: id, label, type, coords, spawns, slots, ...) |
| `GetGarage(id)` | table / nil | One garage |
| `GetVehicleState(plate)` | `{ garage, state }` / nil | `state` is `stored`, `out`, `impounded` or `in_transit` |
| `SetVehicleCondition(plate, { engine, body, fuel })` | bool | For mechanic and tuning scripts. Values are percent (0-100). Updates the stored vehicle's props and the garage card |
| `ImpoundVehicle(plate, opts)` | bool | Impound by plate from code. `opts = { reason, fee, holdMinutes, ownerRelease, by, lot }`. Removes the vehicle from the world if it is out |
| `CreateGarage(data)` | ok, message | Same validation as the admin editor. Saved to the database |
| `SetGarageOwner(garageId, identifier, name)` | bool | Private garages. Pass `nil` to put it back on sale. Clears members |
| `GrantAccess(garageId, identifier, name)` | bool | Add a member to a private garage |
| `RevokeAccess(garageId, identifier)` | bool | Remove a member |
| `AddTempGarage(data)` | ok, message | Register a temporary private garage (housing scripts). See [HOUSING.md](HOUSING.md) |
| `RemoveTempGarage(id)` | bool | Remove a temporary garage |
| `SetTempGarageMembers(id, identifiers)` | bool | Replace a temporary garage's member list |

`identifier` is the framework identifier: `citizenid` on QBCore/Qbox, `identifier` on ESX.

## Server events

Listen with:

```lua
AddEventHandler('as-garages:server:vehicleStored', function(src, plate, garageId)
    print(('%s stored %s in %s'):format(GetPlayerName(src), plate, garageId))
end)
```

| Event | Arguments |
| --- | --- |
| `as-garages:server:vehicleTakenOut` | `src, plate, garageId` |
| `as-garages:server:vehicleStored` | `src, plate, garageId` |
| `as-garages:server:vehicleImpounded` | `src (nil from code), plate, lotId, fee` |
| `as-garages:server:vehicleRetrieved` | `src, plate, lotId, feePaid` |
| `as-garages:server:vehicleTransferred` | `src, plate, fromGarageId, toGarageId` |
| `as-garages:server:vehicleSold` | `sellerSrc, buyerSrc, plate, price` |
| `as-garages:server:vehicleRepaired` | `src, plate, cost` |
| `as-garages:server:vehicleAbandoned` | `plate, action` (`impound` or `garage`) |
| `as-garages:server:garageBought` | `src, garageId, price` |

## Client hooks (in `config.lua`)

| Hook | Where | Purpose |
| --- | --- | --- |
| `Config.Keys` | server (+ client for client-only scripts) | Connect your keys resource. See [KEYS.md](KEYS.md) |
| `Config.GiveKeys(vehicle, plate)` | client | Optional extra code after a vehicle spawns |
| `Config.Fuel.get / set(vehicle, level)` | client | Read and write fuel |
| `Config.Repair.onRepair(src, plate)` | server | Optional, runs after a paid repair |

## Client event and state

| Name | Purpose |
| --- | --- |
| `as-garages:client:hudToggled` (`hidden`) | Fired when a garage screen opens (`true`) or closes (`false`). Listen to it in your HUD to hide and show it. |
| `LocalPlayer.state['asg:uiOpen']` | `true` while a garage screen is open. |

## Database

Public tables: `as_garage_vehicles` (state of each vehicle), `as_garage_locations` (garages saved in game), `as_garage_access` (private garage members), `as_garage_logs` (activity) and `as_garage_history` (per-vehicle history). Read them freely. Prefer the exports for writing.
