# Admin guide

Needs the ace permission `asgarages.admin` (see [INSTALL.md](INSTALL.md)). Open the editor with `/asgarage`. Every action is re-checked on the server.

## Garages tab

The left list shows every garage. A tag says if it comes from `config.lua` or has been edited in game.

- **+ New garage**: fill in an id (letters, numbers, `_`), a name and a type, then place the interaction point and at least one spawn point, and press **Save changes**.
- **Types**: Public (everyone), Job and Gang (enter names like `police, sheriff:2` where `:2` is the minimum grade), Private / house (for sale until someone buys it) and Impound lot.
- **Accepted vehicle classes**: cars, bikes, boats, air. Leave all off to accept everything. This is checked when a vehicle is stored.
- **Everyone in the group sees all stored vehicles**: for job and gang garages, any member can take out any vehicle stored there. Players can still only store vehicles they own.
- **Locations**: use **Place** and the editor hides while you walk or drive to the spot. Press **E** to confirm or **Backspace** to cancel. Sit in a vehicle to capture its heading, which is best for spawn bays. **Go** teleports you to a point.
- **3D preview point**: where the showroom copy of a vehicle appears while a player browses. The camera is placed automatically. Garages without one simply don't show a preview.
- **Delete / Reset to config**: asks for a second click. A garage that only exists in `config.lua` can't be deleted here, remove it from the file.

## Private and house garages

Create a garage with type **Private / house** and a price. It shows a green blip and a "Buy garage" prompt until someone buys it. The owner can add and remove members (nearby players) from the garage screen with **Manage access**.

In the editor you can **Clear owner** to put it back on sale. For housing scripts, use the exports in [EXPORTS.md](EXPORTS.md) to set the owner and members when a property is bought.

## Vehicles tab

Search by plate or owner id. It shows the owner, state (stored, out, impounded) and garage. **Return to garage** puts the vehicle in the chosen garage and removes it from the world if it is out. Useful for stuck or lost vehicles.

## Logs tab

Every take out, store, impound, retrieve, transfer, sale and admin action is recorded and kept for `Config.LogDays`. Filter by action, plate or text.

## Tips

- Standing next to a bay in a vehicle and pressing E in placement mode is the quickest way to set up bays.
- Boats and aircraft garages need bays on water or on a helipad. Use `vehicleClasses` so a car can't be stored in a dock.
- After changing a job, players get their garages refreshed automatically.
