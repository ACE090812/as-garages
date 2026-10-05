# FAQ

**Which frameworks work?** QBCore, Qbox and ESX Legacy. The framework is detected automatically.

**Do I need to change my vehicle table?** No. as-garages keeps its own tables and only updates the framework's props, state and owner columns.

**Can I switch from qb-garages / esx_advancedgarage?** Yes. Existing vehicles show up the first time their owner opens a garage and are treated as parked in `Config.DefaultGarage`. Remove the old garage resource so two scripts don't fight over vehicle state.

**A vehicle is stuck "out".** Open `/asgarage`, go to Vehicles, search the plate and press **Return to garage**.

**Vehicles keep getting impounded for no reason.** Set `Config.WatchSpawned = false`, or `Config.StuckBehaviour = 'garage'`.

**How do players sell a vehicle?** Open the garage the vehicle is stored in, pick it, press **Sell**, choose a nearby player and a price (0 gifts it). The buyer gets a confirmation and has 30 seconds to accept.

**Can job vehicles be shared?** Yes: a job or gang garage with `shared = true` lets every member take out any vehicle stored there. Players can only store vehicles they own.

**Why can't I Transfer or Sell a vehicle?** It must be stored in the garage you are standing in, and you must own it.

**Does it support boats and aircraft?** Yes. Make a garage with bays on water or a helipad and limit it with `vehicleClasses`.

**The preview shows the wrong angle or nothing.** Set a 3D preview point (`/asgarage` > Locations). Without one, the preview car is shown on the garage's first bay.

**The UI has black boxes.** Some FiveM browser builds render blur effects as black. Version 0.3.1 removed all blur, so update to that or newer.

**"11 of 10 slots".** Vehicles the script has never seen are assumed to be parked in `Config.DefaultGarage`, even past its slot limit. Give that garage enough slots (the default is 40) or move vehicles with the admin Tools tab.

**How do I add a language?** See "Translating" in [CONFIGURATION.md](CONFIGURATION.md).

**Light mode?** Players can toggle it from the sun/moon button in the UI. Set the default with `Config.Theme.mode`.

**Can I use ox_target or qb-target instead of the E prompt?** Yes. Set `Config.Interaction.mode` to `'target'` or `'both'`. See [CONFIGURATION.md](CONFIGURATION.md).

**Can transfers take time?** Set `Config.TransferDelay` to a number of seconds. The default `0` is instant.

**What happens to vehicles left on the road?** After `Config.Abandoned.minutes` with nobody in or near them they are impounded or returned to their garage. Change `Config.Abandoned.action` or turn it off.

**Can players lend keys?** Yes, while the vehicle is out. Set the hooks in `Config.ShareKeys` for your keys resource.

**How do I connect a housing script?** See [HOUSING.md](HOUSING.md).

**How do I add an interior?** See [INTERIORS.md](INTERIORS.md).

**Does it work with a controller?** Keyboard navigation always works. Gamepad input works where the game's browser exposes it; it may not on every build.
