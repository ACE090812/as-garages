# Exports and integration

All exports are server side: `exports['as-garages']:Name(...)`.

## Private / house garages

Use these from a housing script when a property is bought or shared.

```lua
-- Set (or clear, with nil) the owner of a private garage. Clears its member list.
exports['as-garages']:SetGarageOwner('my_house_garage', identifier, 'Display Name')

-- Let someone else use it
exports['as-garages']:GrantAccess('my_house_garage', identifier, 'Display Name')
exports['as-garages']:RevokeAccess('my_house_garage', identifier)
```

`identifier` is the framework identifier: `citizenid` on QBCore/Qbox, `identifier` on ESX. All three return `true` on success and `false` if the garage doesn't exist or isn't private.

## Creating garages from code

```lua
local ok, message = exports['as-garages']:CreateGarage({
    id = 'beach_house_1', label = 'Beach House 1', sub = 'Del Perro', type = 'private',
    slots = 4, price = 150000, blipOn = true,
    coords = { x = -1050.0, y = -1520.0, z = 5.0 },
    spawns = { { x = -1046.0, y = -1514.0, z = 5.0, w = 120.0 } },
})
```

It runs the same validation as the admin editor and saves the garage to the database.

## Vehicle state

```lua
local info = exports['as-garages']:GetVehicleState('ABC123')
-- nil, or { garage = 'legion_square', state = 'stored' | 'out' | 'impounded' }
```

Handy for phones, MDTs and dealership scripts.

## Keys

`Config.GiveKeys(vehicle, plate)` runs on the client when a vehicle is taken out. Replace it to integrate any keys resource.

## Database notes for other scripts

- The vehicle's mods are kept in the framework table (`mods` on QBCore/Qbox, `vehicle` on ESX) and are updated every time it is stored.
- `state`/`garage` (QBCore/Qbox) and `stored` (ESX) are kept in sync.
- Ownership changes from a sale are written to `citizenid` (+ `license`) or `owner`.
