# Car Company Empire

A playable Godot 4.7 prototype of an open-world automotive business game.

## Play

Open the project in Godot 4.7 and run it, or launch from the project folder:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Choose a company name and brand color, enter the starter car, visit suppliers,
manufacture vehicles at the factory, and sell them at the dealership.

## Online multiplayer

Choose **Play Online** to enter the shared live world. Browser and desktop
players connect through the hosted WebSocket service, so friends can see one
another walking and driving without port forwarding. Each player currently
keeps independent business progression while company owners and their driven
cars are synchronized in real time.

Choose **Play Solo** when you do not want to join the shared world.

## Controls

- `WASD` — walk / drive
- Mouse — third-person camera
- `Shift` — sprint
- `Space` — jump / handbrake
- `E` — interact / enter / exit
- `Esc` — release or capture the mouse

The city, buildings, roads, cars, UI, dealerships, factory, suppliers, and test
track are assembled locally and require no network connection.

## Asset credits

- City Kit Commercial by Kenney — CC0 1.0
- Downtown City MegaKit by Quaternius — CC0 1.0

The original license files are included beside the imported assets under
`assets/city/`.
