# Vehicle keys

as-garages talks to your keys resource in three places:

1. **Taking a vehicle out or retrieving it from the impound** gives the player keys.
2. **Storing** can require the keys (`requireKeysToStore`) and can take them away again (`removeOnStore`, automatic for as-vehiclekeys).
3. **Lending keys** to a nearby player (while the vehicle is out) gives them keys, and takes them back after `Config.ShareKeys.minutes`.

All of it goes through `Config.Keys` in `config.lua`.

## Built-in support

| `Config.Keys.resource` | How it works |
| --- | --- |
| `'auto'` (default) | Uses the first of `as-vehiclekeys`, `qbx_vehiclekeys`, `qb-vehiclekeys`, `Renewed-Vehiclekeys` that is running |
| `'as-vehiclekeys'` | Item-based keys. Uses its server exports `GiveKey`, `TakeKey` and `HasKey`. The key is handed back when a vehicle is taken out and taken again when it is stored (`removeOnStore` is automatic). Lent keys really expire. The doors are unlocked after a vehicle spawns |
| `'qbx_vehiclekeys'` | Server exports `GiveKeys`, `RemoveKeys`, `HasKeys` |
| `'qb-vehiclekeys'` | Triggers `vehiclekeys:client:SetOwner`. It cannot take keys back or check them, so lending keys can't expire and `requireKeysToStore` has no effect |
| `'Renewed-Vehiclekeys'` | Client exports `addKey` / `removeKey` |
| `'ox_inventory'` | Keys are inventory items (`Config.Keys.item`, default `vehiclekey`) with the plate in their metadata. Give, remove and check use ox_inventory |
| `'custom'` | Your own script, see below |
| `'none'` | Does nothing |

The export names for the built-in resources come from their public documentation as I understand it. If one doesn't work, check the resource's current docs and use `'custom'`.

## Using your own keys script

Set `resource = 'custom'` and fill in the functions your script offers. Leave the rest empty.

```lua
Config.Keys = {
    resource = 'custom',
    requireKeysToStore = false,
    removeOnStore = false,
    custom = {
        -- SERVER side
        give = function(src, plate, entity) exports.my_keys:GiveKey(src, plate) end,
        remove = function(src, plate, entity) exports.my_keys:RemoveKey(src, plate) end,
        has = function(src, plate, entity) return exports.my_keys:HasKey(src, plate) end,

        -- CLIENT side, if your script's exports only work on the client
        -- (these run on the player's own client)
        clientGive = function(plate, vehicle) exports.my_keys:AddKey(plate) end,
        clientRemove = function(plate, vehicle) exports.my_keys:RemoveKey(plate) end,
    },
}
```

- `src` is the player, `plate` is the plate text (trimmed, upper case) and `entity` is the vehicle entity on the server (it can be `nil` right after a spawn).
- If your script keys vehicles by plate, you only need `give`, and `remove` if you want expiry or `removeOnStore`.
- If keys are given by an event instead of an export, trigger it from `give` (for a server event, `TriggerEvent`; for a client event, `TriggerClientEvent('your:event', src, plate)`).
- `has` is optional. If it is missing, `requireKeysToStore` has no effect.

`Config.GiveKeys(vehicle, plate)` still exists as a small client hook that runs after every spawn, for example to unlock the doors.

## Lending keys

`Config.ShareKeys = { enabled = true, minutes = 30 }`. The vehicle has to be out in the world. After the time is up, `remove` runs for the player who was lent the keys. With a script that can't remove keys, the borrower keeps them.

## as-vehiclekeys notes

- Don't call `GiveKey` / `TakeKey` from anywhere else for garage events. as-garages does it for you, so you would get double calls.
- A vehicle that someone only hotwired or lockpicked has "session access" and no key item. With `requireKeysToStore = true` that player can't store it. Leave it `false` if you want hotwired cars storable.
- The key is given a moment after the vehicle spawns, so there can be a split second where a keyless engine is off.
