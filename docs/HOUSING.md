# Housing scripts

as-garages does not ship an adapter for any specific housing resource. I could not verify any housing script's API from the development environment, and an adapter written from memory could silently break. Instead there is a small, safe **temporary garage API**. Your housing script (or a tiny bridge file) calls it from the **server**.

Temporary garages live in memory only, so register them when the property loads or is bought and remove them when it goes away.

## Register a garage for a property

```lua
-- Server side, in your housing script (or a bridge resource)
local ok, err = exports['as-garages']:AddTempGarage({
    id = 'property_' .. propertyId,            -- unique, e.g. property_12
    label = 'Beach House 1', sub = 'Del Perro',
    owner = ownerIdentifier,                   -- citizenid / identifier. Required
    ownerName = 'Alex Doe',
    members = { 'ABC123', 'DEF456' },          -- optional: identifiers who may also use it
    coords = { x = -1050.0, y = -1520.0, z = 5.0 },
    spawns = { { x = -1046.0, y = -1514.0, z = 5.0, w = 120.0 } },
    slots = 4, radius = 3.0,
    -- optional: preview = { x, y, z, w }, interior = { ... } (see INTERIORS.md), vehicleClasses = { 'cars' },
    --           blip = { sprite = 357, color = 3, scale = 0.7 }
})
```

When the owner changes or someone is added or removed:

```lua
exports['as-garages']:SetTempGarageMembers('property_12', { 'ABC123' })
exports['as-garages']:RemoveTempGarage('property_12')
```

Vehicles stored in a temporary garage keep their record under that id. Register the garage again with the same id on restart and the vehicles are still there.

## Permanent house garages

If you prefer garages that survive restarts without the housing script, create a **Private / house** garage in `/asgarage` and use `SetGarageOwner`, `GrantAccess` and `RevokeAccess` from your housing script when a property is bought, sold or shared.

## What other garage scripts do

Housing scripts usually include an integration file per garage script. If yours has one for a script you don't use, copy it and replace the calls with the exports above. If you write an adapter for a specific housing resource, a pull request is welcome.
