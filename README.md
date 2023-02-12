# THIS SCRIPT IS BROKEN AND WILL NOT WORK

If you've used this script to install GShade to games previously and you're looking to safely uninstall, please use the `delete` function of the script to remove all installations of GShade to games (ex., `./gshade_installer.sh delete 1` until there's nothing left to delete), and then delete the entire `$XDG_DATA_HOME/GShade` directory.  (Defaults to `$HOME/.local/share/GShade` if `$XDG_DATA_HOME` is not set.)

This will remove *all* traces of GShade (shaders and presets as well) from your computer *and* leave your game in a working state.

# If it's dead why isn't it archived?

Because I might make `reshade_installer.sh` instead but I'm not the best scripter so I'm looking for feedback to issues [over here](https://github.com/HereInPlainSight/gshade_installer/issues/27).

-----------------------
Original readme archived below.

-----------------------
-----------------------

# gshade_installer

This is a CLI [GShade](https://gposers.com/gshade/) installer for Linux.  It both downloads and updates GShade and can be used to install / update your GShade installs for individual games that will be run through WINE.

Please note that as of 06-21-22, this installer no longer interacts with WINE directly, as it seems to no longer be necessary.  The previous script can be found in the `legacy` branch.

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

Universally required:
* `awk`, `curl`, `find`, `hash`, `ln`, `perl`, `sed`, `unzip`, `rsync`

Additional requirements for Linux:
* `7z`<sup>1</sup>, `md5sum`

Additional requirements for Mac:
* `ditto`, `md5`

<sup>1</sup> As of 02-23-21, `7z` (generally provided by the `p7zip` package in most distros, `p7zip-full` on Ubuntu) is also required.  If you have a reliable source of the required 32-bit d3dcompiler that doesn't need it, I'm open to removing the requirement, but right now we're using the winetricks method.

### Installation

There's multiple ways to run the installer, this is just one method.
  1) Clone the repo:  `git clone https://github.com/HereInPlainSight/gshade_installer.git`
  2) Change directory into it:  `cd gshade_installer`
  3) Run the script:  `./gshade_installer.sh`

We install to the `$XDG_DATA_HOME/GShade/` directory, which defaults to `$HOME/.local/share/GShade/`.

### Updating

When updating GShade through the script (`./gshade_installer.sh update` or through the guided menu's `1` option), *all* existing installs are updated if an update is found.

#### ***If any of the following seems complicated -- just run `./gshade_installer.sh` and follow the guided prompts.***

If you're installing GShade for use with FFXIV, you can try the auto-installer by running `./gshade_installer.sh ffxiv`, which will search for a default-location Steam install (the default WINE prefix in Steam is `$HOME/.steam/steam/steamapps/compatdata/39210/pfx`, and the game itself is in `$HOME/.steam/steam/steamapps/common/FINAL FANTASY XIV Online/game/`), a Lutris install (by looking for a configuration file), the default XLCore location, or by checking a provided WINEPREFIX.

If you wanted to install GShade to a Steam install of FFXIV manually, you would use the following command:
```
WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/39210/pfx" ./gshade_installer.sh dx11 "$HOME/.steam/steam/steamapps/common/FINAL FANTASY XIV Online/game/ffxiv_dx11.exe"
```

If you're having any problems, you can check `./gshade_installer.sh debug`, which will print something similar to this:
![Debug example](https://i.imgur.com/C0nCWOo.png)
Green is good.  Red indicates an error with that component.  Yellow is informational, such as a 'hard install' without symlinks.  Neither good nor bad -- just something to be aware of when troubleshooting.

You can get just the games.db list by requesting it with `./gshade_installer.sh list`.  You can remove an item from the list with `./gshade_installer.sh remove <#>`, or delete the GShade installation from the game with `./gshade_installer.sh delete <#>`.

If you're having trouble and asking a friend for help, you can use `./gshade_installer.sh debug upload` and give your friend the URL.  They can use the URL with `curl <URL>` to see the exact output you would see if you ran the debug yourself.

## Troubleshooting

Q: Help, I'm using the default launcher but once I install GShade, the launcher stops launching!

A: Known issue -- with the 32-bit launcher.
   - Lutris: Open XIV's `Configure`, in the `Game Options` tab change the `Executable` from `ffxivboot.exe` to `ffxivboot64.exe`.
   - Steam: Open XIV's `properties` dialog and set your `Launch Options` to:
     - `echo "%command%" | sed 's/ffxivboot.exe/ffxivboot64.exe/' | sh`

Q: I'm on a Mac --

A: Anything Mac-related has been contributed by the good people at [XIV on Mac](https://www.xivmac.com/).  If your question is XIV-specific, you'll almost *certainly* want to contact them directly.

## Help

If you need further help, please check the [GPoser's discord](https://discord.gg/gposers) for the `gshade-troubleshooting` channel.

## Acknowledgments

* Thanks to Marot on the GPosers discord for -- absolutely everything they do.

## Contributors

If you are a code contributor, please feel free to add yourself to the list during your commit!  My memory is roughly sieve-shaped!

* [@JacoG-RH](https://github.com/JacoG-RH) - Non-standard Steam libraries.
* [@Maia-Everett](https://github.com/Maia-Everett) - Support for Wine Steam, locating game via wine registry, and `$HOME/.wine` checking.
* [@taylor85345](https://github.com/taylor85345) - XIVLauncher.Core auto-detection.
* [@FleetAdmiralButter](https://github.com/FleetAdmiralButter) - Non-AVX detection.
* [@marzent](https://github.com/marzent) - All the work to add Mac support.
* [@Zoeyrae](https://github.com/Zoeyrae) - XIV on Mac support to the auto installer.

