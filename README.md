# gshade_installer

This is a CLI [GShade](https://gposers.com/gshade/) installer for Linux.  It both downloads and updates GShade and can be used to install / update your GShade installs for individual games that will be run through WINE.

## Getting Started

Once you've got the script and it's executable, you can simply run it.  There is a basic menu.

If you would prefer to run the commands directly, the help menu should give you the basics (`./gshade_installer.sh --help`):
```
Syntax options:
                                ./gshade_installer.sh                                           -- Guided tutorial
                                ./gshade_installer.sh update [force|presets]                    -- Install / Update to latest GShade.  Optionally force the full update or just presets.
                                ./gshade_installer.sh list                                      -- List games, numbers provided are for use with remove / delete options.
                                ./gshade_installer.sh lang <en|ja|ko|de|fr|it> [default|#]      -- Change the language of GShade's interface.  Defaults to the master copy if unspecified.
                                ./gshade_installer.sh remove <#>                                -- Remove <#> from database, leave GShade in whatever shape it's currently in.
                                ./gshade_installer.sh delete <#>                                -- Delete GShade from <#> and remove from database.
<WINEPREFIX=/path/to/prefix>    ./gshade_installer.sh ffxiv                                     -- Install to FFXIV in provided Wine Prefix or autodetect if no Wine Prefix
 WINEPREFIX=/path/to/prefix     ./gshade_installer.sh [dx(?)|opengl] /path/to/game.exe          -- Install to custom location with designated graphical API version. 'dxgi' is valid here if needed.

                                                                        Note: game.exe should be the GAME'S .exe file, NOT the game's launcher, if it has one!
```
You can clone the repo and run the script from within it.  Instructions to do so are below the prerequisites.

### Prerequisites

To my knowledge this should work in virtually any Linux install that has access to bash and basic utilities.  `wget`, `ln`, `find`, `awk`, `sed`, `unzip`.  You need a local copy of WINE installed -- the version itself doesn't matter, but if you'll be using your local copy of WINE to ***play*** the game, you'll need 4.2 or above to get shaders to work.

### Installation

There's multiple ways to run the installer, this is just one method.
  1) Clone the repo:  `git clone https://github.com/HereInPlainSight/gshade_installer.git`
  2) Change directory into it:  `cd gshade_installer`
  3) Run the script:  `./gshade_installer.sh`

We install to the `$XDG_DATA_HOME/GShade/` directory, which defaults to `$HOME/.local/share/GShade/`.

#### ***If any of the following seems complicated -- just run `./gshade_installer.sh` and follow the guided prompts.***

If you're installing GShade for use with FFXIV, you can try the auto-installer by running `./gshade_installer.sh ffxiv`, which will search for a default-location Steam install (the default WINE prefix in Steam is `$HOME/.steam/steam/steamapps/compatdata/39210/pfx`, and the game itself is in `$HOME/.steam/steam/steamapps/common/FINAL FANTASY XIV Online/game/`), a Lutris install (by looking for a configuration file), or by checking a provided WINEPREFIX.

If you wanted to install GShade to a Steam install of FFXIV manually, you would use the following command:
```
WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/39210/pfx" ./gshade_installer.sh dx11 "$HOME/.steam/steam/steamapps/common/FINAL FANTASY XIV Online/game/ffxiv_dx11.exe"
```

If you're having any problems, you can check `./gshade_installer.sh debug`, which will print something similar to this:
![Debug example](https://i.imgur.com/C0nCWOo.png)
Green is good.  Red indicates an error with that component.  Yellow is informational, such as a 'hard install' without symlinks.  Neither good nor bad -- just something to be aware of when troubleshooting.

You can get just the games.db list by requesting it with `./gshade_installer.sh list`.  You can remove an item from the list with `./gshade_installer.sh remove <#>`, or delete the GShade installation from the game with `./gshade_installer.sh delete <#>`.

If you're having trouble and asking a friend for help, you can use `./gshade_installer.sh debug upload` and give your friend the URL.  They can use the URL with `curl <URL>` to see the exact output you would see if you ran the debug yourself.

## Help

If you need help, please check the [GPoser's discord](https://discord.gg/gposers) for the `gshade-troubleshooting` channel.

## Acknowledgments

* Thanks to Marot on the GPosers discord for -- absolutely everything they do.

