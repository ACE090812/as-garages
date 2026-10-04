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

**The preview shows the wrong angle or nothing.** The garage needs a 3D preview point (`/asgarage` > Locations). Without one, no preview is shown.

**How do I add a language?** See "Translating" in [CONFIGURATION.md](CONFIGURATION.md).

**Light mode?** Players can toggle it from the sun/moon button in the UI. Set the default with `Config.Theme.mode`.
