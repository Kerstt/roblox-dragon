# roblox-dragon

Roblox games and experiments.

| Folder | What it is |
| --- | --- |
| [dragon-tycoon](dragon-tycoon/README.md) | Dragon Tycoon: a dragon-sanctuary tycoon with hatching, stations, riding and flight, sky-arena duels, co-op raids, a Robux shop and a guided tutorial |

## Working on Dragon Tycoon with Roblox Studio

The **code** lives here; the **world** (terrain, buildings, dragon and egg models)
lives in the Roblox place and is saved in its version history on Roblox.
[Rojo](https://rojo.space) keeps Studio's scripts and these files in step.

### One-time setup

1. **Git** and access to this repository (ask the owner to add you under
   Settings > Collaborators).
2. Clone it:
   ```
   git clone https://github.com/Kerstt/roblox-dragon.git
   ```
3. **Rojo 7.7.1:** download `rojo-7.7.1-windows-x86_64.zip` from
   [Rojo's releases](https://github.com/rojo-rbx/rojo/releases/tag/v7.7.1) and put
   `rojo.exe` in a `.tools` folder inside the repo (it is ignored by Git).
4. **Rojo plugin in Studio:** install "Rojo" from the Creator Store (Toolbox >
   Plugins) or run `.tools\rojo.exe plugin install`. Its version should be 7.7.
5. In Studio, open the Rojo plugin's **Settings** and turn on **Two-Way Sync**.
   This is what writes your Studio script edits into the files here.
6. **Python 3** (only for `export-from-place.cmd`).

### Every time you work

1. Open the game in Studio (Creator Hub > the game > Edit in Studio).
2. Double-click **`sync.cmd`** and leave its window open.
3. In Studio: **Plugins > Rojo > Connect**. Rojo lists any differences before it
   applies them. Check that list: on connect, the files here win.
4. Edit scripts in Studio (or in VS Code; both directions sync).
5. When you're done, double-click **`push.cmd`**, type what you changed, press Enter.
   It commits, pulls your teammates' changes, and pushes to GitHub.

### When something didn't sync

Two-Way Sync covers edits to existing scripts. If you added, renamed or deleted
scripts in Studio, or forgot to run `sync.cmd`:

1. In Studio: **File > Save to File As**, type **Roblox XML Place Files (*.rbxlx)**.
2. Drag that file onto **`export-from-place.cmd`** (or double-click it to use
   `OneDrive\Documents\DragonTycoon.rbxlx`). Every script is copied into
   `dragon-tycoon/src`. It never deletes: remove files for deleted scripts yourself.
3. Run **`push.cmd`**.

### Rules for a team

* **Only one person runs `sync.cmd` against the shared place at a time.** Two
  syncs overwrite each other's scripts.
* Pull before you start (`git pull`, or just run `push.cmd`, which pulls), and
  connect Rojo only after pulling, so you don't send old files into Studio.
* For bigger changes, use a branch and a pull request instead of pushing to `main`.
* World, model and terrain edits are done in Studio with Team Create and are not
  in Git.
