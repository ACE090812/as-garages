# Walk-in interiors

A garage can have an interior. When a player interacts with it, the screen fades, they are moved inside, and their stored vehicles are shown parked in a showroom. They browse with the same garage screen (the preview camera focuses the real parked car), take a vehicle out, and drive away from the outside bays.

as-garages does not include any interior. Use any MLO, IPL or shell you already have.

## Setup in the admin editor

1. `/asgarage`, open the garage, and turn on **Walk-in interior** (right column).
2. Stand where the player should appear inside and press **Place** for the **Entry point**. This is also where the "Browse vehicles" prompt is.
3. Place the **Exit point** (the door).
4. Place a **Showroom bay** for each parked vehicle (sit in a vehicle to capture its heading). The first bays show favourites, then the most recently stored vehicles.
5. If the interior needs an IPL, enter its name. Entity sets can be added in `config.lua`.
6. Save.

## In `config.lua`

```lua
{
    id = 'my_garage', label = 'My Garage', type = 'public', coords = vec3(...), slots = 6,
    spawns = { vec4(...) },
    interior = {
        enter = vec4(x, y, z, heading),         -- where the player appears (and the browse prompt)
        exit = vec3(x, y, z),                   -- leave prompt
        bays = { vec4(...), vec4(...) },        -- showroom spots
        ipl = 'some_ipl_name',                  -- optional
        entitySets = { 'set_name' },            -- optional interior entity sets
    },
}
```

## Notes

- Each player is placed in their own routing bucket while inside, so other players and traffic don't appear. They are returned to bucket 0 on exit or disconnect.
- Taking a vehicle out from inside uses the first free outside bay. If the outside area is not streamed in, the first bay is used, so keep the outside bays clear.
- Interiors work with the target or prompt interaction mode (`Config.Interaction`).
- Walk-in interiors are optional per garage. Garages without one behave as before.
