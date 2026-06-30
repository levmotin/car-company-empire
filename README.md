# Car Company Empire

A playable Godot 4.7 prototype of an open-world automotive business game.

## Play

Open the project in Godot 4.7 and run it, or launch from the project folder:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Create an account with a username, company name, password, and brand color.
Then enter the starter car, visit suppliers, manufacture vehicles at the
factory, and sell them at the dealership.

## Online accounts and multiplayer

The game is online-only. Select **Play**, then sign in or create an account.
Browser and desktop players connect through the hosted WebSocket service, so
friends share one world and see one another walking and driving. Usernames
appear above characters and in the online roster. The server assigns every
connected company a different factory in the 16-plot online company district;
players and their cars spawn at their own plot.

Account progress is stored in PostgreSQL and autosaved: money, reputation,
company level, research, parts inventory, manufactured cars, sales, objectives,
and world position. Closing the game removes the live character from the world
without deleting account progress.

## Controls

- `WASD` — walk / drive
- Mouse — third-person camera
- `Shift` — sprint
- `Space` — jump / handbrake
- `E` — interact / enter / exit
- `Esc` — release or capture the mouse

The city, buildings, roads, cars, UI, dealerships, factory, suppliers, and test
track are assembled by the Godot client after the online account connects.

## Asset credits

- City Kit Commercial by Kenney — CC0 1.0
- Downtown City MegaKit by Quaternius — CC0 1.0

The original license files are included beside the imported assets under
`assets/city/`.
