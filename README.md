# Car Company Empire

A playable Godot 4.7 prototype of an open-world automotive business game.

## Play

Open the project in Godot 4.7 and run it, or launch from the project folder:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Sign in or sign up with Google. Username-and-password accounts are not
supported. Then enter the starter car, visit suppliers, manufacture vehicles at
the factory, and sell them at the dealership.

## Online accounts and multiplayer

The game is online-only. Select **Play**, then continue with Google.
Browser and desktop players connect through the hosted WebSocket service, so
friends share one world and see one another walking and driving. Usernames
appear above characters and in the online roster. The server assigns every
connected company a different factory in the 12-plot Empire industrial district;
players and their cars spawn at their own plot.

Account progress is stored in PostgreSQL and autosaved: money, reputation,
company level, research, parts inventory, manufactured cars, sales, objectives,
and world position. Closing the game removes the live character from the world
without deleting account progress.

Google accounts use Google's permanent account ID rather than a username as
their identity, so different players may use the same display name without
sharing an account. To enable Google sign-in on Render, create a Web application
OAuth client and register this exact redirect URI:

```text
https://car-company-empire-online.onrender.com/auth/google/callback
```

Set the resulting `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` on the
`car-company-empire-online` Render service. Never commit the client secret.

The `google_only_accounts_v1` database migration deletes every account that
existed before the Google-only release. It is recorded in `app_migrations`, so
the purge runs only once.

## Controls

- `WASD` — walk / drive
- Mouse — third-person camera
- `Shift` — sprint
- `Space` — jump / handbrake
- `E` — interact / enter / exit
- `Esc` — release or capture the mouse

The city, buildings, roads, cars, UI, dealerships, factory, suppliers,
drive-through restaurant, and test track are assembled by the Godot client
after the online account connects. Drive to the restaurant speaker, press `E`
to order, then follow the marked lane and collect the meal at the pickup window.

## Asset credits

- City Kit Commercial by Kenney — CC0 1.0
- Downtown City MegaKit by Quaternius — CC0 1.0
- "Race track/Karting Track based on South Garda" by
  [Mauro3D](https://sketchfab.com/maurogsw) —
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
  [Original model](https://sketchfab.com/3d-models/race-trackkarting-track-based-on-south-garda-32c21042ba144ce9bd2822a88d5b54ec).

The original license files are included beside the imported assets under
`assets/city/` and `assets/tracks/`.
