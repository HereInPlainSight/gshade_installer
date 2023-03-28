#!/usr/bin/env bash

###
# TODO:
# - Don't break anything.

##
# Housekeeping to respect user's configurations.
if [ -z "$XDG_CONFIG_HOME" ]; then XDG_CONFIG_HOME="$HOME/.config"; fi
if [ -z "$XDG_DATA_HOME" ]; then XDG_DATA_HOME="$HOME/.local/share"; fi
if [ -z "$CX_BOTTLE_PATH" ]; then CX_BOTTLE_PATH="$HOME/Library/Application Support/CrossOver/Bottles"; fi

ReShadeHome="$XDG_DATA_HOME/ReShade"
dbFile="$ReShadeHome/games.db"

##
# Yeah I think this'll make life easier.
gamesList=""
gapi=""
ARCH=""
forceUpdate=0

# Sigh.
wineLoc=""
wineBin="wine"

##
# Checking if running on Mac
IS_MAC=false
cxLoc="/Applications/CrossOver.app" #this should be identical on all macs
if [[ $OSTYPE == 'darwin'* ]]; then
  IS_MAC=true
  printf "Running on macOS\n"
fi

declare -a iniSettings=()

##
# Pattern matching used to avoid deleting 'Off.ini' and 'Custom' directories.
# Self: Does this break macs?
shopt -s extglob

##
#Syntax options:
#				$0					-- Guided tutorial.
#				$0 update [force|shaders|presets]	-- Install / Update to latest ReShade, or update shaders / presets.  Optionally force the ReShade update.
#				$0 list					-- List games, numbers provided are for use with remove / delete options.
#				$0 remove <#>				-- Remove <#> from database, leave ReShade in whatever shape it's currently in.
#				$0 delete <#>				-- Delete ReShade from <#> and remove from database.
#<WINEPREFIX=/path/to/prefix>	$0 ffxiv				-- Install to FFXIV in provided Wine Prefix or autodetect if no Wine Prefix.
#<WINEPREFIX=/path/to/prefix>	$0 <dx[?]|opengl> /path/to/game.exe	-- Install to custom location with designated graphical API version. 'dxgi' is valid here (and the recommended default).
#
#									Note: game.exe should be the GAME'S .exe file, NOT the game's launcher, if it has one!
#									WINEPREFIX is only required for opengl games!
#
# Undocumented features:
# 				$0 fetchCompilers			-- Fetch new compilers.  If this is needed, there's a good question on 'why and how.'
#				$0 status [upload]			-- Check the status of some important bits, optionally upload it to termbin since it's a curl-friendly site.
##
printHelp(){
  helpText="Syntax options:
				%s						-- Guided tutorial.
				%s update [force|shaders|presets]		-- Update to latest ReShade, shaders or presets.  Optionally forcefully update ReShade.
				%s list					-- List games, numbers provided are for use with remove / delete options.
				%s remove <#>				-- Remove <#> from database, leave ReShade in whatever shape it's currently in.
				%s delete <#>				-- Delete ReShade from <#> and remove from database.
<WINEPREFIX=/path/to/prefix>	%s ffxiv					-- Install to FFXIV in provided Wine Prefix or autodetect if no Wine Prefix.
<WINEPREFIX=/path/to/prefix>	%s [dx(?)|opengl] /path/to/game.exe		-- Install to custom location with designated graphical API version. 'dxgi' is valid here (and the recommended default).

									Note: game.exe should be the GAME'S .exe file, NOT the game's launcher, if it has one!\n
									WINEPREFIX is only required for opengl games!\n"
  printf "$helpText" "$0" "$0" "$0" "$0" "$0" "$0" "$0"
}

##
# Input functions.
yesNo(){
  while true; do
    read -p "$*" -n 1 -r yn
    case $yn in
      [Yy]* ) return 0; break;;
      [Nn]* ) return 1; break;;
      * ) printf "\tPlease answer yes or no.\n";;
    esac
  done
}

readNumber(){
  while true; do
  read -p "> " -r yn
    case $yn in
      ''|*[!0-9]*) printf "Unrecognized number: %s\n" "$yn";;
      *) return "$(echo "$yn" | tr -d '\r\n')";;
    esac
  done
}

##
# Function to output only the md5 checksum
getMD5(){
  if [ "$IS_MAC" = true ] ; then
    md5 -q "$1"
  else
    md5sum "$1" | awk '{ print $1 }'
  fi
}

##
# Workaround for platforms that don't ship with gnu readlink
readlinkf(){ perl -MCwd -e 'print Cwd::abs_path shift' "$1";}

##
# Turn a list of new-line separated strings into an array.
makeArray(){
  local -n sourceList="$1"
  oldIFS=$IFS
  IFS=$'\n'
  sourceList=($sourceList)
  IFS=$oldIFS
}

##
# Does this really not exist?  Well, it does now, I guess.  Give it an array.
commonDir(){
  local -n sourceList="$1"
  leastCommonDir=${sourceList[0]}
  for i in ${!sourceList[@]}; do
    if [[ "${sourceList[$i]}" != "$leastCommonDir"* ]]; then
      count=${leastCommonDir//[^,'/']}
      for (( j=0; j<${#count}; j++ )); do
        leastCommonDir="$(echo "$leastCommonDir" | cut -f1-$((${#count}-$j)) -d/)"
        if [[ "${sourceList[$i]}*" == "$leastCommonDir"* ]]; then
          break;
        fi
      done
    fi
  done
  sourceList="$leastCommonDir"
}

##
# Y'all just lucky I don't name this 'findWineOrSomethingStronger'.
findWine(){
  # For, uhh, Macs.
  if [ $IS_MAC = true ] ; then
    if ( ! hash wine64 &>/dev/null ); then
      if [ -d "$cxLoc/Contents/SharedSupport/CrossOver/bin" ]; then
        wineLoc="$cxLoc/Contents/SharedSupport/CrossOver/bin"
        wineBin="wineloader64"
      else
        printf "Could not find a valid CrossOver install at: %s and wine is not installed\n", "$cxLoc"
        exit 1
      fi
    else
      wineBin="wine64"
    fi
  fi
  # For SteamDecks / flatpaks.
  if [[ "$IS_MAC" = "false" ]] && ( ! hash "$wineBin" &>/dev/null ); then
    if ( flatpak list --app 2> /dev/null | grep -i org.winehq.Wine &> /dev/null ); then
      wineBin="flatpak run org.winehq.Wine"
    else
      printf "No wine found at all -- not even flatpak!  Exiting!\n"
      exit 1
    fi
  fi
}

##
# Return 1 if not a valid WINEPREFIX, return 0 if it is.  Or, at least if it's close enough.
validPrefix(){
  if [ ! -f "$WINEPREFIX/system.reg" ]; then
    return 1;
  fi
  return 0;
}

##
# For the rare occasion this is still necessary.  At this time, this is an issue with openGL games ONLY, but the code is designed to be able to handle other APIs if the issue crops up elsewhere.
# Invocation: makeWineOverride <gapi>
makeWineOverride(){
  gapi="$1"
  if ( ! validPrefix ); then
    printf "Wine override required, but no valid WINEPREFIX found!  Exiting!"
    exit 1
  fi
  export WINEPREFIX
  if [ -n "$wineLoc" ] ; then wine="$wineLoc/$wineBin"; else wine="$wineBin"; fi
  # Somewhat ham-fisted, but this is the only time we use wine.  This will kill the script if it can't find wine.
  findWine
  if (! yesNo "*** Changing wine versions has the potential to break your wine prefix!  Please back up your wine prefix if you're going to proceed! ***\nHave you backed up your wine prefix and are you sure you wish to continue?  "); then
    printf "\nAborting!\n"
    exit 1
  fi
  $wine reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v "${gapi}" /d native,builtin /f > /dev/null 2>&1
}

##
# Backup ReShade's reshade/shaders, as well as each games' reshade/presets/ and ReShade.ini.
# Backup directory per game is Backups/$year-$month-$day/$time/$game.exe/
# If more than one install has the same base game name (ex, both Lutris and Wine versions of XIV installed), subsequent directories will have a random string generated to keep them separate.
# gameInfo.txt will be created per-game directory to help sorting out original path and prefixes.  These files will contain FULL directory information, with no variable substitutions.
performBackup(){
  [ -z "$1" ] && timestamp=$(date +"%Y-%m-%d/%T") || timestamp="$1"
  mkdir -p "$ReShadeHome/Backups/$timestamp" && pushd "$_" > /dev/null || exit
  cp -r "$ReShadeHome/dataDirs/shaders" "./"
  listGames; [ ! $? ] && return 0;
  printf "Performing backup..."
  while IFS="=;" read -r gameName installDir prefixDir; do
    backupDir="$ReShadeHome/Backups/$timestamp/$gameName"
    [ ! -d "$backupDir" ] && mkdir "$backupDir" || backupDir=$(mktemp -d -p "$gameName-XXXXXXXXXX" --tmpdir=./)
    printf "%b" "Game:\t\t$gameName\nInstalled to:\t$installDir\nWINEPREFIX:\t$prefixDir\n" > "$backupDir/gameInfo.txt"
    cp "$installDir/ReShade.ini" "$backupDir/"
    cp -r "$installDir/reshade/presets" "$backupDir/"
  done < "$dbFile"
  popd > /dev/null || exit
  printf "\e[2K\r                   \r"
}

fetchCompilers(){
  if [ ! -d "$ReShadeHome/d3dcompiler_47s" ]; then
    mkdir -p "$ReShadeHome/d3dcompiler_47s"
  fi
  pushd "$ReShadeHome/d3dcompiler_47s" > /dev/null || exit
  printf "\e[2K\rDownloading 64-bit compiler...  "
  ##
  # Sourced from Lutris.  I don't even remember how I found this was sitting there.
  curl -sO https://lutris.net/files/tools/dll/d3dcompiler_47.dll
  mv d3dcompiler_47.dll d3dcompiler_47.dll.64bit
  printf "Done!"
  # The following was originally sourced from The_Riesi @ https://www.reddit.com/r/linux_gaming/comments/b2hi3g/reshade_working_in_wine_43/, but the link is now dead.
  # Utilizing the same method winetricks uses.
  if [ "$IS_MAC" = true ] ; then
    printf "\e[2K\rNot downloading 32-bit compiler since running on Mac!"
    touch d3dcompiler_47.dll.32bit #placing stub
  else
    printf "\e[2K\rDownloading 32-bit compiler...  "
  ##  curl -sO http://dege.freeweb.hu/dgVoodoo2/D3DCompiler_47.zip && unzip -q D3DCompiler_47.zip && rm D3DCompiler_47.zip
    curl -sO https://download-installer.cdn.mozilla.net/pub/firefox/releases/62.0.3/win32/ach/Firefox%20Setup%2062.0.3.exe && if [ -d "7z" ]; then sevenZ="7z/bin/7z"; else sevenZ="7z"; fi; $sevenZ e -y "Firefox%20Setup%2062.0.3.exe" "core/d3dcompiler_47.dll" >> /dev/null && rm "Firefox%20Setup%2062.0.3.exe"
    mv d3dcompiler_47.dll d3dcompiler_47.dll.32bit
    printf "Done!"
  fi
  popd > /dev/null || exit
  printf "\e[2K\rd3dcompiler_47s downloaded\n"
}

##
# Check `$ReShadeHome/include.d` and `$ReShadeHome/blacklist.d` for (presently) '*.shader' and '*.preset' files.
# Format of files: github URLs, one per line.  #'s as the first character are comments and ignored.
# The blacklist is processed last and therefore always wins.
#
# Invocation: addIncludes "<shader|preset>" "<array to iterate>"
addIncludes(){
  extension="$1"
  local -n addList="$2"
  if [ -d "$ReShadeHome/include.d" ]; then
    pushd "$ReShadeHome/include.d" > /dev/null
    for i in *.$extension; do
      [ -f "$i" ] || break
      for j in "$i"; do
        addList+=($(awk '/^[^$|^#]/' "$j"))
      done
    done
    popd > /dev/null
  fi
  if [ -d "$ReShadeHome/blacklist.d" ]; then
    pushd "$ReShadeHome/blacklist.d" > /dev/null
    for i in *.$extension; do
      [ -f "$i" ] || break
      for j in "$i"; do
        deletions=($(awk '/^[^$|^#]/' "$j"))
        for k in ${deletions[@]}; do
          addList=("${addList[@]/$k}")
	done
      done
    done
    popd > /dev/null
  fi
}

##
# Update installs.  Presets or presets and reshade as requested.
# Invokation: updateInstalls <presets|all>
updateInstalls(){
  updating="$1"
  performBackup
  while IFS="=;" read -r gameName installDir prefixDir; do
    pushd "$installDir/reshade/presets/" > /dev/null || exit
    rm -rf !("Off.ini"|"Custom")
    popd > /dev/null || exit
    cp -rf "dataDirs/presets/" "$installDir/reshade/"
    ##
    # Hard install upgrade begin
    if [[ $updating == "all" ]] && [[ $(find "$installDir" -maxdepth 1 -lname "$ReShadeHome/*.dll" -print) == "" ]]; then
      gArch=""
      md5goal=""
      if printf "%s/%s" "$installDir" "$gameName" | grep -q "80386"; then
        gArch="32"; md5goal="$old32"
      elif printf "%s/%s" "$installDir" "$gameName" | grep -q "x86-64"; then
        gArch="64"; md5goal="$old64"
      fi
      gName=$(basename "$(find "$installDir" -maxdepth 1 \( -name "d3d*.dll" ! -name "d3dcompiler_47.dll" \))")
      if [ -f "$installDir/opengl32.dll" ]; then gName="opengl32.dll"; fi
      if [[ $gName != "" ]]; then
        if [[ "$(getMD5 "$installDir/${gName}")" == "$md5goal" ]]; then cp -f "ReShade${gArch}.dll" "$installDir/${gName}.dll"; fi
      fi
      if [ -f "$installDir/dxgi.dll" ] && [[ "$(getMD5 "$installDir/dxgi.dll")" == "$md5goal" ]]; then cp -f "ReShade${gArch}.dll" "$installDir/dxgi.dll"; fi
    fi
    # Hard install update end.
  done < "$dbFile"
}

##
# Expects to already be in the base git directory.
# Invocation: gitMaint "address" "author/repoName"
gitMaint(){
  gitRepo="$1"
  localName="$2"
  if [ ! -d "$localName" ]; then
    git clone "$gitRepo" "$localName" &> /dev/null
  else
    git pull "$localName" &> /dev/null
  fi
}

##
# Remove folders that don't have a '.git' somewhere after their base directory to allow for archives to not keep crashing into themselves or making a bunch of duplicates.
cleanSources(){
  if [[ "$(pwd)" != "$ReShadeHome"* ]]; then
    echo "Attempted a potentially dangerous command while not in the \$ReShadeHome directory.  You should report this."
    exit 1
  fi
  find "$(pwd)" -mindepth 1 -maxdepth 1 -type d $(printf "! -name %s " $(find . -type d -name '.git' -print | cut -c 3- | cut -f1 -d"/" | uniq)) -exec rm -r {} \;
}

##
# Invocation: runSources "array" "return array"
# Expects to be in git directory already.
runSources(){
  local -n sourceList="$1"
  local -n returnList="$2"
  for i in "${!sourceList[@]}"; do
    if [[ "${sourceList[i]: -4}" == ".zip" ]]; then
      filename="${sourceList[$i]##*/}"
      directoryName="${filename%.*}"
      counter=1
      if [ -d "$directoryName" ]; then
        while [ -d "$directoryName-$counter" ]; do
	  ((counter++))
	done
	directoryName="$directoryName-$counter"
      fi
      curl -sLo "$filename" ${sourceList[i]}
      unzip -qquo "$filename" -d "$directoryName"
      rm "$filename"
      returnList+=("$directoryName")
    else
      IFS='[/.]' read -ra addr <<< ${sourceList[$i]}
      ##
      # addr[0]     = <protocol>:
      #     [1]     = <empty> (From killing '//')
      #     [2]...  = domain data
      if [[ "${addr[2]}.${addr[3]}" == "github.com" ]]; then
        # Remove anything beyond the repo name.
        sourceList[$i]="${addr[0]}//github.com/${addr[4]}/${addr[5]}"
        gitMaint "${sourceList[$i]}" "${addr[4]}/${addr[5]}"
        returnList+=("${addr[4]}"/"${addr[5]}")
      elif [[ "${addr[3]}.${addr[4]}" == "github.io" ]]; then
        # Restructure 'github.io' addresses into their github repos.
        sourceList[$i]="${addr[0]}//github.com/${addr[2]}/${addr[5]}"
        gitMaint "$sourceList[$i]}" "${addr[2]}/${addr[5]}"
        returnList+=("${addr[2]}"/"${addr[5]}")
      else
        # Print out the address structure while debugging if something failed.
        for j in "${!addr[@]}"; do
          printf "$j:\t${addr[$j]}\n"
        done
        printf "\n"
      fi
    fi
  done
}

##
# Updates shader repos, sorts out shaders and textures.
shadersUpdate(){
  shaderSourceList=($(curl --silent "https://raw.githubusercontent.com/crosire/reshade-shaders/list/EffectPackages.ini" | grep "^RepositoryUrl=*" | awk -F= '{ print $2 }'))
  [ ! -d "$ReShadeHome/dataDirs/git/shaders" ] && mkdir -p "$ReShadeHome/dataDirs/git/shaders"
  [ ! -d "$ReShadeHome/dataDirs/shaders/Custom" ] && mkdir -p "$ReShadeHome/dataDirs/shaders/Custom"
  [ ! -d "$ReShadeHome/dataDirs/textures/Custom" ] && mkdir -p "$ReShadeHome/dataDirs/textures/Custom"
  printf "\e[2K\rUpdating shaders -- this could take some time!"
  pushd "$ReShadeHome/dataDirs/shaders/" > /dev/null || exit
  rm -rf !("Custom")
  popd > /dev/null || exit
  pushd "$ReShadeHome/dataDirs/textures/" > /dev/null || exit
  rm -rf !("Custom")
  popd > /dev/null || exit 
  pushd "$ReShadeHome/dataDirs/git/shaders" > /dev/null || exit
  cleanSources
  addIncludes "shader" shaderSourceList
  shaderList=()
  runSources shaderSourceList shaderList
  for localName in "${shaderList[@]}"; do
    tmp=(${localName//\// })
    author="${tmp[0]}"
    ##
    # Per https://github.com/crosire/reshade-shaders/pull/219#issuecomment-716211466 , this is how the ReShade installer finds shaders.
    shadersLoc="$(find "$localName" -depth -type d -name "Shaders" -print | sed 1q)"
    if [ "$shadersLoc" == "" ]; then shadersLoc="$(find "$localName" -type f -iname "*.fx" -printf %h -quit)"; fi
    texturesLoc="$(find "$localName" -type d -name "Textures" -print)"

    if [[ $shadersLoc != "" ]]; then mkdir -p "$ReShadeHome/dataDirs/shaders/$author/"; rsync -ar "$shadersLoc" "$ReShadeHome/dataDirs/shaders/$localName/"; fi
    if [[ $texturesLoc != "" ]]; then mkdir -p "$ReShadeHome/dataDirs/textures/$author/"; rsync -ar "$texturesLoc" "$ReShadeHome/dataDirs/textures/$localName/"; fi
  done
  popd > /dev/null || exit
}
 
##
# Download current presets.
# ReShade status: Requires data in 'include.d/*.preset' file(s).
presetsUpdate(){
  pushd "$ReShadeHome" > /dev/null || exit
  timestamp=$(date +"%Y-%m-%d/%T")
  if [ -f "version" ]; then performBackup "$timestamp"; fi
  printf "Updating presets...\n"
  pushd "$ReShadeHome/dataDirs/presets/" > /dev/null || exit
  rm -rf !("Off.ini"|"Custom")
  popd > /dev/null || exit
  presetSourceList=()
  if [ ! -d "$ReShadeHome/dataDirs/git/presets" ]; then mkdir -p "$ReShadeHome/dataDirs/git/presets"; fi
  pushd "$ReShadeHome/dataDirs/git/presets" > /dev/null || exit
  cleanSources
  addIncludes "preset" presetSourceList
  presetList=()
  runSources presetSourceList presetList
  for localName in "${presetList[@]}"; do
    tmp=(${localName//\// })
    author="${tmp[0]}"
    ##
    # There is no standard for how presets should be packaged.  So we find all ini files and rsync the common directory they all share.
    presetLoc="$(find "$localName" -type f -iname "*.ini" -printf "%h\n" | awk '!dups[$0]++')"
    makeArray presetLoc
    commonDir presetLoc
    if [[ $presetLoc != "" ]]; then mkdir "$ReShadeHome/dataDirs/presets/$author/"; rsync -ar "$presetLoc/" "$ReShadeHome/dataDirs/presets/$author/"; fi
  done
  popd > /dev/null || exit
  updateInstalls presets
  popd > /dev/null || exit
}

##
# Updater / initial installer.
# Certain things ONLY happen during initial installation ATM.  The $ReShadeHome directory is created, games.db is created, the d3dcompiler_47.dlls (32 and 64-bit) are both downloaded and put in their own directory.
update(){
  if [ ! -f "$ReShadeHome/version" ]; then
    if (yesNo "ReShade initial install not found, would you like to create it?  "); then printf "\nCreating...  "; else printf "\nAborting installation.\n"; exit 1; fi
    if [ "$IS_MAC" = true ] ; then
      prereqs=(awk find git ln md5 sed unzip curl perl rsync)
    else
      prereqs=(7z awk find git ln md5sum sed unzip curl perl rsync)
    fi
    mia=""
    for i in "${prereqs[@]}"; do
      if ( ! hash "$i" &>/dev/null ); then
        if [ -n "$mia" ]; then mia+=", $i"; else mia="$i"; fi
      fi
    done
    if [ "$mia" = "7z" ] && ( hash "ark" &>/dev/null ); then
      if ( yesNo "7z not found -- would you like to download a binary copy of the 7zip extractor?  This should ONLY be used if your package manager does not offer 7zip, such as the Steam Deck!  " ); then
        if [ ! -d "$ReShadeHome/d3dcompiler_47s/7z" ]; then
          mkdir -p "$ReShadeHome/d3dcompiler_47s/7z"
        fi
        pushd "$ReShadeHome/d3dcompiler_47s/7z" > /dev/null || exit
        printf "\nWorking..."
        zipVer="16.02"
        curl -so "p7zip_${zipVer}_x86_linux-bin.tar.bz2" -L "https://sourceforge.net/projects/p7zip/files/p7zip/${zipVer}/p7zip_${zipVer}_x86_linux_bin.tar.bz2/download"
        ark -b -a "p7zip_${zipVer}_x86_linux-bin.tar.bz2"
        mv "p7zip_${zipVer}/bin" "p7zip_${zipVer}/DOC" ./
        rm -r "p7zip_${zipVer}"*
        popd > /dev/null || exit
        printf "\r7z downloaded for script-only use!\n"
        mia=""
      else
        printf "\n7z is required for installation -- please install 7zip via your package manager if available.\n"
        exit 1
      fi
    elif [ -n "$mia" ]; then
      printf "The following necessary command(s) could not be found: %s\n", "$mia"
      exit 1
    fi
    mkdir -p "$ReShadeHome" && pushd "$_" > /dev/null && touch games.db && mkdir "include.d" && mkdir "blacklist.d" && mkdir -p "dataDirs/presets/Custom" && curl -sLo "dataDirs/presets/Off.ini" "https://raw.githubusercontent.com/HereInPlainSight/gshade_installer/reshade/Off.ini" && popd > /dev/null || exit
    fetchCompilers
  fi
  reshadeCurrent=$(curl --silent "https://api.github.com/repos/crosire/reshade/tags" | grep -m 1 '"name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed -e 's/v//g')
  if [ "$forceUpdate" -eq 0 ] && [[ -f "$ReShadeHome/version" ]] && [[ $(<"$ReShadeHome/version") == "$reshadeCurrent" ]] && [[ -f "$ReShadeHome/ReShade64.dll" ]]; then
    printf "Up to date.\n"
  else
    pushd "$ReShadeHome" > /dev/null || exit
    # Look at me
    # We're the default ReShade.ini file now
    if [[ ! -f "$ReShadeHome/ReShade.ini" ]]; then
      printf "\e[2K\rGrabbing a friendly ReShade.ini..."
      curl -sLO https://raw.githubusercontent.com/HereInPlainSight/gshade_installer/reshade/ReShade.ini
    fi
    if [[ -f "$ReShadeHome/ReShade.Latest.exe" ]]; then rm -rf "$ReShadeHome/ReShade.Latest.exe"; fi
    if [[ -f "$ReShadeHome/ReShade64.dll" ]]; then
      printf "\e[2K\rmd5sums in process..."
      old64="$(getMD5 ReShade64.dll)"
      old32="$(getMD5 ReShade32.dll)"
    fi
    shadersUpdate
    presetsUpdate
    printf "\e[2K\rDownloading latest ReShade...                     "
    curl -sLO https://reshade.me/downloads/ReShade_Setup_$reshadeCurrent\_Addon.exe && mv ReShade_Setup_$reshadeCurrent\_Addon.exe ReShade.Latest.exe
    unzip -qqo ReShade.Latest.exe &> /dev/null
    printf "%s\n" "$reshadeCurrent" > version
    updateInstalls all
    popd > /dev/null || exit
    printf "ReShade-%s installed.\n" "$reshadeCurrent"
  fi
}

##
# List games found in $dbFile ($ReShadeHome/games.db), formatted as:
# #) Game:		<exe file>
# 	Installed to:	<exe file's location>
# 	WINEPREFIX:	<Location of wine's prefix installed to, if recorded.>
listGames(){
  gamesList=""			# Always blank the list in case user is confirming removal after checking before.
  i=1				# Yeah, iterating for removal / deletion numbering options.
  if [ ! -s "$dbFile" ]; then
    return 1
  fi
  # First, check that all these paths actually exist, and remove ones that don't.
  while IFS="=;" read -r gameName installDir prefixDir; do
    if [ ! -d "$installDir" ]; then
      removeGame $i
      printf "Game installation \"%s\" not found, removed from list.\n" "$installDir"
    else
      # Subtlety: We only increment i if the line was NOT removed from games.db,
      # because removing the line shifts all subsequent lines one line up.
      ((++i))
    fi
  done < "$dbFile"
  i=1
  printf "Checking md5sums..."
  while IFS="=;" read -r gameName installDir prefixDir; do
    pushd "$installDir" > /dev/null || exit
    gapiln=$(find '.' -maxdepth 1 -name "*.dll" -lname "$ReShadeHome/ReShade*.dll" -exec basename {} ';')
    if [ -z "$gapiln" ]; then
      fileString="$(file "$gameName")"
      gmd5=""
      if printf "%s" "$fileString" | grep -q "80386"; then
        gmd5="$(getMD5 "$ReShadeHome/ReShade32.dll")"
      elif printf "%s" "$fileString" | grep -q "x86-64"; then
        gmd5="$(getMD5 "$ReShadeHome/ReShade64.dll")"
      fi
      # Check dxgi and opengl32 before we start hitting find up.
      if [ -f "dxgi.dll" ] && [ "$gmd5" == "$(getMD5 "dxgi.dll")" ]; then gapiln="dxgi.dll"; fi
      if [ -z "$gapi" ] && [ -f "opengl32.dll" ] && [ "$gmd5" == "$(getMD5 "opengl32.dll")" ]; then gapiln="opengl32.dll"; fi
      if [ -z "$gapi" ] && [ -f "$(basename "$(find '.' -maxdepth 1 \( -name "d3d*.dll" ! -name "d3dcompiler_47.dll" \))" 2>&1)" ] && [ "$gmd5" == "$(getMD5 "$(basename "$(find '.' -maxdepth 1 \( -name "d3d*.dll" ! -name "d3dcompiler_47.dll" \))")")" ]; then gapiln="$(basename "$(find '.' -maxdepth 1 \( -name "d3d*.dll" ! -name "d3dcompiler_47.dll" \))")"; fi
    fi
    popd > /dev/null || exit
    gamesList="$gamesList$i) Game:\t\t$([ -f "$installDir/$gameName" ] && printf "\e[32m" || printf "%b" "\e[31m")$gameName\e[0m\t\t$([ -L "$installDir/$gapiln" ] && printf "%b" "\e[32m[$gapiln -> $([ ! -f "$(readlinkf "$installDir/$gapiln")" ] && printf "%b" "\e[0m\e[31m")$(basename "$(readlinkf "$installDir/$gapiln")")\e[0m\e[32m]\e[0m" || ([ -f "$installDir/$gapiln" ] && printf "\e[33m[%s]\e[0m" "$gapiln" || printf "%b" "\e[31mReShade symlink not found!\e[0m"))\n\tInstalled to:\t$([ ! -d "$installDir" ] && printf "%b" "\e[31m")${installDir/#$HOME/"\$HOME"}\e[0m$([ -n "$prefixDir" ] && printf "%b" "\n\tWINEPREFIX:\t\e[0m${prefixDir/#$HOME/"\$HOME"}\e[0m")\n"
    ((++i))
  done < "$dbFile"
  printf "\e[2K\r"
  return 0
}

##
# Record game's location to a flat file database for backing up.  Check for EXACT duplicates.
recordGame(){
  i=1
  while IFS="=;" read -r gameName installDir prefixDir; do
    if [ "$gameName" == "$gameExe" ] && [ "$installDir" == "$gameLoc" ] && [ "$prefixDir" == "$WINEPREFIX" ]; then return 0; fi
    ((i++))
  done < "$dbFile"
  record="$gameExe=$gameLoc;$WINEPREFIX"
  printf "%s\n" "$record" >> "$dbFile"
  return 0
}

##
# Invokation: getGame #
# Pulls the relevant variables for a game based on line number from games.db.
getGame(){
  [ -z "$1" ] && return 1 || line="$1"
  oldIFS="$IFS"
  IFS='=;'
  set -- "$(awk -F '=;' 'NR=='"$line"' {print $1, $2, $3}' "$HOME/.local/share/ReShade/games.db")"
  IFS="$oldIFS"
  gameExe=$1 gameLoc=$2 WINEPREFIX=$3
}

##
# Invokation: forgetGame
# Just sets everything to default values that getGame sets.  More of a safety net than a necessity currently.
forgetGame(){
  gameExe="" gameLoc="" WINEPREFIX=""
}

##
# Clean soft links pointing to $ReShadeHome from the current directory, AND, if the game was opengl32, remove the override.
cleanSoftLinks(){
  oldGapi="$(basename "$(find '.' -maxdepth 1 -lname "$ReShadeHome/ReShade*.dll" -exec basename {} ';')" .dll)"
  # OpenGL32 still needs wine overrides.
  if [ "$oldGapi" == "opengl32" ]; then
    if ( validPrefix ); then
      export WINEPREFIX
      if [ -n "$wineLoc" ]; then wine="$wineLoc/$wineBin"; else wine="$wineBin"; fi
      $wine reg delete 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v "${oldGapi}" /f > /dev/null 2>&1
    fi
  fi
  find "$gameLoc" -maxdepth 1 -lname "$ReShadeHome/*" -delete > /dev/null 2>&1
}

##
# Invocation: removeGame #
# Removes line number # from $dbFile.
removeGame(){
  newFile="$(awk -v line="$1" 'NR!=line' "$dbFile")"
  printf "%s\n" "$newFile" > "$dbFile"
}

##
# Invocation: deleteGame #
# Delete all traces of ReShade from # in $dbFile and its associated installation directory and WINEPREFIX.  But make a backup first.
deleteGame(){
  performBackup
  tempWINEPREFIX="$WINEPREFIX"
  IFS="=;" read -r gameName gameLoc WINEPREFIX <<< "$(sed "${1}q;d" "$dbFile")"
  if [ ! -d "$gameLoc" ]; then
    printf "Installation directory not found -- nothing to delete.  Removal recommended instead.  Exiting.\n"
    exit 1
  fi
  pushd "$gameLoc" > /dev/null || exit
  rm -rf 'reshade' 'ReShade.ini'
  cleanSoftLinks
  popd > /dev/null || exit
  WINEPREFIX="$tempWINEPREFIX"
  removeGame "$1"
}

##
# WINEPREFIX, gameLoc, gapi, and ARCH (I use Gentoo BTW) must all have been configured elsewhere in the script.
# This is where the magic happens, or at least where the soft links happen and a few copies and the required dll overrides.
# This will also make an individual backup for an install's ./reshade/presets folder if it happens to exist, and ignore ReShade.ini if it's already there.
installGame(){
  # Get to the WINEPREFIX to make sure it's recorded as absolute and not relative.
  if [ "$WINEPREFIX" != "" ]; then
    pushd "$WINEPREFIX" > /dev/null || exit; WINEPREFIX="$(pwd)/"; popd > /dev/null || exit
  fi
#  WINEPREFIX="${WINEPREFIX//+(\/)//}"		# Legacy, but interesting to remember.
  pushd "$gameLoc" > /dev/null || exit
  # 32 bit installs are not supported (and really not recommended in any case) on macOS
  if [ "$IS_MAC" = true ] && [ "$ARCH" = 32 ] ; then
    printf "\nInstalling to 32-bit executables is not supported on macOS.  Exiting.\n"
    exit 1
  fi
  # Clean up an old install before the new soft links and reg edits (if necessary) are re-added.  Mostly to deal with changing gapi's.
  cleanSoftLinks
  if [ "$gapi" == "opengl32" ]; then makeWineOverride "$gapi"; fi
  ln -sfn "$ReShadeHome/d3dcompiler_47s/d3dcompiler_47.dll.${ARCH}bit" d3dcompiler_47.dll
  if [ $? != 0 ] || [ ! -L "d3dcompiler_47.dll" ]; then cp "$ReShadeHome/d3dcompiler_47s/d3dcompiler_47.dll.${ARCH}bit" d3dcompiler_47.dll; fi
  ln -sfn "${ReShadeHome}/ReShade${ARCH}.dll" "${gapi}".dll
  if [ $? != 0 ] || [ ! -L "${gapi}.dll" ]; then cp "${ReShadeHome}/ReShade${ARCH}.dll" "$gapi".dll; fi
  if [ ! -f "ReShade.ini" ]; then cp "$ReShadeHome/ReShade.ini" "ReShade.ini"; fi
  if [ ! -d "$gameLoc/reshade" ]; then mkdir "$gameLoc/reshade"; fi
  ln -sfn "$ReShadeHome/dataDirs/shaders" "reshade/shaders"
  if [ $? != 0 ] || [ ! -L "reshade/shaders" ]; then cp -a "$ReShadeHome/dataDirs/shaders" "reshade/shaders"; fi
  ln -sfn "$ReShadeHome/dataDirs/textures" "reshade/textures"
  if [ $? != 0 ] || [ ! -L "reshade/textures" ]; then cp -a "$ReShadeHome/dataDirs/textures" "reshade/textures"; fi
  if [ -d "$gameLoc/reshade/presets" ]; then
    timestamp=$(date +"%Y-%m-%d/%T")
    backupDir="$ReShadeHome/Backups/$timestamp/$gameExe/"
    mkdir -p "$backupDir"
    cp -a "reshade/presets" "$backupDir"
    printf "%b" "Game:\t\t$gameExe\nInstalled to:\t$gameLoc\nWINEPREFIX:\t$WINEPREFIX\n" > "$backupDir/gameInfo.txt"
  fi
  rsync -a "$ReShadeHome/dataDirs/presets/" "./reshade/presets/"
  if [ ! -d "$gameLoc/reshade/addons" ]; then
    mkdir -p "$gameLoc/reshade/addons"
  fi
  recordGame
  popd > /dev/null || exit
}

##
# Automatic install for FFXIV.  Offers to install any that it finds in the following order: WINEPREFIX, Lutris, Steam.
XIVinstall(){
  gameExe="ffxiv_dx11.exe"
  gapi=dxgi
  ARCH=64

  ##
  # This will be relevant if it exists.
  lutrisYaml=($(find "$XDG_CONFIG_HOME"/lutris/games/ -name 'final-fantasy-xiv*' -print 2>/dev/null))
  xlcoreini=($(find "$HOME"/.xlcore/ -name 'launcher.ini' -print 2>/dev/null))
	
  if [[ "$IS_MAC" = "true" ]] && [[ -d "/Applications/XIV on Mac.app" ]]; then
    WINEPREFIX="$HOME/Library/Application Support/XIV on Mac/wineprefix"
    gameLoc="$(defaults read dezent.XIV-on-Mac GamePath)/game/"
    gapi=d3d11;
    printf "\n $gameLoc"
    printf "\nXIV on Mac detected.\n"
    printf "\nInstalling...  ";
    installGame
    printf "Complete!\n"
    exit 0
  fi

  gameLoc="$WINEPREFIX/drive_c/Program Files (x86)/SquareEnix/FINAL FANTASY XIV - A Realm Reborn/game/"
  if [ -d "$gameLoc" ]; then
    printf "\nWine install found!\n\tAPI hook: dxgi\n\tPrefix location: %s\n\tGame location: %s\n" "$WINEPREFIX" "$gameLoc"
    if (yesNo "Install? "); then
      if ( ! yesNo "Install with dxgi?  You should ONLY say 'no' here if you're having issues with ReShade! " ); then gapi=d3d11; fi
      printf "\nInstalling...  ";
      installGame
      printf "Complete!\n"
    fi
  fi

  if [[ -n "$lutrisYaml" ]] && [ -f "$lutrisYaml" ]; then
    if [ ${#lutrisYaml[@]} -gt 1 ]; then printf "\nFound %s Lutris installs!" "${#lutrisYaml[@]}"; else printf "\nLutris install found!"; fi
    for i in ${lutrisYaml[@]}; do
      WINEPREFIX="$(awk -F': ' '/ prefix:/{print $2}' "$i")"
      gameLoc="$WINEPREFIX/drive_c/Program Files (x86)/SquareEnix/FINAL FANTASY XIV - A Realm Reborn/game/"
      if [ ! -d "$gameLoc" ]; then
        gameLoc=$(find -L "$WINEPREFIX/drive_c" -name 'ffxiv_dx11.exe' -exec dirname {} ';')
      fi
      printf "\n\tAPI hook: dxgi\n\tPrefix location: %s\n\tGame location: %s\n" "$WINEPREFIX" "$gameLoc"
      if (yesNo "Install? "); then
        printf "\nInstalling...  "
        installGame
        printf "Complete!\n"
      fi
    done
  fi

  # Locate install via XIVLauncher.Core
  if [[ -n "$xlcoreini" ]] && [ -f "$xlcoreini" ]; then
    printf "\nXLCore install found!"
    for i in "${xlcoreini[@]}"; do
      WINEPREFIX="$HOME/.xlcore/wineprefix/"
      gameLoc="$(awk -F'=' '/GamePath=/{print $2}' $xlcoreini)/game/"
      printf "\n\tAPI hook: dxgi\n\tPrefix location: %s\n\tGame location: %s\n" "$WINEPREFIX" "$gameLoc"
      if (yesNo "Install? "); then
        printf "\nInstalling...  "
        installGame
        printf "Complete!\n"
      fi
    done
  fi

  ## Non-standard Steam locations contributed by JacoG-RH
  if [ -f ~/.steam/steam/steamapps/libraryfolders.vdf ]; then
    steamDirs=($(cat ~/.steam/steam/steamapps/libraryfolders.vdf | grep "path" | awk '{ print $2  }' | sed s/\"//g))
  fi
  steamDirs=("${steamDirs[@]}" "$HOME/.steam/steam")
  for checkDir in "${steamDirs[@]}"; do
    if [ -d "${checkDir}/steamapps/compatdata/39210/pfx" ]; then ffxivDir="${checkDir}"; fi
  done

  if [ -d "${ffxivDir}/steamapps/common/FINAL FANTASY XIV Online/game/" ] && [ -d "${ffxivDir}/steamapps/compatdata/39210/pfx" ]; then
    WINEPREFIX="${ffxivDir}/steamapps/compatdata/39210/pfx"
    gameLoc="${ffxivDir}/steamapps/common/FINAL FANTASY XIV Online/game/"
    if [ -f "$WINEPREFIX/drive_c/users/steamuser/AppData/Roaming/XIVLauncher/launcherConfigV3.json" ]; then
      launchersDir="$(awk -F': ' '/  "GamePath":/{print $2}' "$WINEPREFIX/drive_c/users/steamuser/AppData/Roaming/XIVLauncher/launcherConfigV3.json" | sed -e 's:\\:/:g' -e 's://:/:g' -e 's:,*\r*$::' -e 's/"//g' -e 's/^C:/drive_c/g')"
      # In the efforts of de-obfuscation, XIVLauncher's json formatting looks like this after awking: "C:\\Program Files (x86)\\SquareEnix\\FINAL FANTASY XIV - A Realm Reborn",
      # `sed -e 's:\\:/:g' -e 's://:/:g' -e 's:,*\r*$::' -e 's/"//g' -e 's/^C:/drive_c/g'` is, in order:
      #   's:\\:/:g'        - switch slashes
      #   's://:/:g'        - combine double slashes
      #   's:,*\r*$::'      - remove trailing comma
      #   's/"//g'          - remove quotes
      #   's/^C:/drive_c/g' - replace 'C:' with 'drive_c'.
      if [ -d "$WINEPREFIX/$launchersDir/game" ]; then gameLoc="$WINEPREFIX/$launchersDir/game"; fi
    fi
    printf "\nSteam install found!\n\tAPI hook: dxgi\n\tPrefix location: %s\n\tGame location: %s\n" "$WINEPREFIX" "$gameLoc"
    if (yesNo "Install? "); then
      if ( ! yesNo "Install with dxgi?  You should ONLY say 'no' here if you're having issues with ReShade! " ); then gapi=d3d11; fi
      printf "\nInstalling...  "
      installGame
      printf "Complete!\n"
    fi
  fi
  printf "\nScan complete.\n"
}

##
# Walkthrough for custom game option selected from the general menu.  Gets input for $gapi, $WINEPREFIX, $gameExe, and $exeFile (which is really $fullPathToExeFile).
customGamePrompt(){
  if ( yesNo "Install with dxgi?  You should ONLY say 'no' here if you're having issues with ReShade! " ); then gapi=dxgi; else
    while true; do
      read -p "What graphics API is the game using? (opengl,dx9,dx10,dx11,dx12): " -r input
      case $input in
        opengl | gl) gapi=opengl32; break;;
        dx9  | 9  ) gapi=d3d9;  break;;
        dx10 | 10 ) gapi=d3d10; break;;
        dx11 | 11 ) gapi=d3d11; break;;
        dx12 | 12 ) gapi=d3d12; break;;
        dxgi | gi ) gapi=dxgi; break;;
        * ) printf "Invalid option.\n";;
      esac
    done
  fi
  if [ "$gapi" == "opengl32" ]; then
    while ! { [ -d "$WINEPREFIX" ] && ( validPrefix ); }; do
      read -p "Where is the WINEPREFIX located?  (The directory where your drive_c folder is located): " WINEPREFIX
      if [ ! -d "$WINEPREFIX" ]; then printf "%s: Directory does not exist.\n" "$WINEPREFIX";
      elif ( ! validPrefix ); then printf "%s: Not a valid prefix, please confirm this is a working prefix.\n" "$WINEPREFIX"; fi
    done
  fi
  while [ ! -f "$exeFile" ] || [ "${gameExe##*.}" != "exe" ]; do
    read -p "Where is the game's .exe file?  (Note: NOT the launcher for the game!): " exeFile
    gameExe="$(basename "$exeFile")" 2>&1 > /dev/null
    if [ ! -f "$exeFile" ]; then printf "%s: Not a file, please confirm the path and file name.\n" "$exeFile";
    elif [ "${gameExe##*.}" != "exe" ]; then printf "%s: Not a .exe file." "$gameExe"; fi
  done
}

##
# Determines $ARCH and $gameLoc from $exeFile.
customGame(){
  # Bank the dirname as an absolute path.
  pushd "$(dirname "$exeFile")" > /dev/null || exit; gameLoc="$(pwd)/"; popd > /dev/null || exit
  # Determine architecture.
  fileString="$(file "$exeFile")"
  if printf "%s" "$fileString" | grep -q "80386"; then
    ARCH="32"
  elif printf "%s" "$fileString" | grep -q "x86-64"; then
    ARCH="64"
  else
    printf "%s: Invalid exe file type.\n" "$exeFile"
    exit 1
  fi
  installGame
}

##
# Sometimes the menu should get repeated, sometimes not.  Easiest to call a function for it.
menu(){
  printf "Welcome to the ReShade CLI installer!  Please select an option:
	1) Update ReShade
	2) Install to a custom game
	X) Attempt auto-install for FF(X)IV
	F) (F)orce update ReShade (and shaders / presets)
	S) Update (S)haders
	P) Update (P)resets
	B) Create a (b)ackup of existing ReShade game installations
	L) (L)ist games ReShade is installed to
	R) (R)emove game from installed games list
	D) (D)elete ReShade from game and remove from list
	0) Redownload compilers
	Q) (Q)uit
"
}

##
# Guided setup with menus.
stepByStep(){
  [[ ! -d "$ReShadeHome" ]] && update
  menu
  while true; do
    read -p "> " -n 1 -r yn
    case $yn in
      [1]* ) printf "\n"; update;;
      [2]* ) printf "\n"; customGamePrompt; customGame; break;;
      [Xx]* ) XIVinstall; break;;
      [Ff]* ) printf "\n"; forceUpdate=1; update;;
      [Ss]* ) shadersUpdate; printf "Done!\n"; break;;
      [Pp]* ) presetsUpdate; printf "Done!\n"; break;;
      [Bb]* ) performBackup; printf "Done!\n"; break;;
      [Ll]* ) listGames; if [ $? ]; then printf "%b" "\n$gamesList"; else printf "\nNo games yet installed to.\n"; fi;;
      [Rr]* ) listGames  # Remove from list & untrack.
        if [ $? ]; then
          printf "%b" "\n$gamesList"
          readNumber; selection=$?
          removeGame $selection
        else
          printf "\nNo games yet installed to remove.\n"
        fi
        menu;;
      [Dd]* ) listGames  # Delete from game / list
        if [ $? ]; then
          printf "%b" "\n$gamesList"
          readNumber; selection=$?
          deleteGame $selection
        else
          printf "\nNo games yet installed to remove.\n"
        fi
        menu;;
      [0]* ) printf "\n"; fetchCompilers; menu;;
      [Ii]* ) printf "\n"; debugInfo upload; exit 0;;
      [Qq]* ) printf "\nBye!\n"; break;;
      * ) printf "\tInvalid option.\n";;
    esac
  done
}

##
# *Eyetwitch.*
# All output here respects swapping user's home directory info with $HOME.
#
# Installation location:  $ReShadeHome
# Installation version:   Contents of $ReShadeHome/version
# d3dcompiler_47 32-bit:  md5sum on d3dcompiler_47s/d3dcompiler_47.dll.32bit
# d3dcompiler_47 64-bit:  md5sum on d3dcompiler_47s/d3dcompiler_47.dll.64bit
# Wine version:           Wine version if installed, and if it's not installed, well, here's the problem.
# games.db:
#   listGames()'s output.
debugInfo(){
  if [ ! -d "$ReShadeHome" ]; then
    output=$(printf "%b" "\e[31mReShade installation not found in folder '${ReShadeHome/#$HOME/"\$HOME"}'.\e[0m\nIf your \$XDG_DATA_HOME environment variable has recently changed, you must migrate files manually from the old location.  Exiting.\n")
    exit 1
  fi
  pushd "$ReShadeHome" > /dev/null || exit
  printf "Checking md5sums..."
  md3d32=$(getMD5 "d3dcompiler_47s/d3dcompiler_47.dll.32bit")
  ##
  # Alert if legacy md5sum.  This is my own fault and may just get changed back to the new md5sum at some point.
  if [ "$md3d32" == "eee83660394f290e3ea5faac41c23a70" ]; then
    PS=0
    ##
    # This md5sum was never used in reshade_installer.sh, but it's an easy way to re-enable checking in the future if we change the 32bit compiler.
#  elif [ "$md3d32" == "c971cde5194dd761456214dd5365bdc7" ]; then
#    PS=2
  else
    PS=1
  fi
  if [ "$(getMD5 d3dcompiler_47s/d3dcompiler_47.dll.64bit)" == "b0ae3aa9dd1ebd60bdf51cb94834cd04" ]; then true; else false; fi
  N64=$?
  output=$(printf "%b" "\e[2K\rInstallation location:\t${ReShadeHome/#$HOME/"\$HOME"}/
Installation version:\t$(cat "$ReShadeHome"/version)
$([ "$IS_MAC" = true ] && printf "%b" "Environment:\t\t\e[33mMac OS detected" || printf "d3dcompiler_47 32-bit:\t$([ "$PS" -eq 0 ] && printf "\e[32mOK" || printf "%b" "\e[31mmd5sum failure")$([ "$PS" -eq 2 ] && printf "%50s" " \e[33mLegacy file -- please run 'fetchCompilers'!") "%15s"\e[0m "ReShade32.dll:" $([ -f "$ReShadeHome"/ReShade32.dll ] && printf "\e[32mExists" || printf "%b" "\e[31mMIA")")\e[0m
d3dcompiler_47 64-bit:	$([ "$N64" -eq 0 ] && printf "\e[32mOK" || printf "%b" "\e[31mmd5sum failure")                \e[0m "ReShade64.dll:" $([ -f "$ReShadeHome"/ReShade64.dll ] && printf "\e[32mExists" || printf "\e[31mMIA")\e[0m")
  listGames; [ $? ] && output+=$(printf "\ngames.db:\n%b" "${gamesList/#$HOME/"\$HOME"}") || output+=$(printf "\ngames.db:\tEmpty or does not currently exist.")
  popd > /dev/null || exit
  if [ "$1" != "upload" ]; then
    printf "%s\n" "$output"
  else
    uploadLoc=$(printf "%s\n" "$output" | (exec 3<>/dev/tcp/termbin.com/9999; cat >&3; cat <&3; exec 3<&-))
    printf "%s\n" "$uploadLoc"
  fi
  exit 0
}

##
# First order of business!  Check to see if the initial ReShade install is complete, and if not, update.
if [ ! -d "$ReShadeHome" ]; then
  update
fi

##
# Command line options:
case $1 in
  update)
    case $2 in
      shaders)
        shadersUpdate
	exit 0;;
      presets)
        presetsUpdate
        exit 0;;
      force)
        forceUpdate=1;;
    esac
    update
  exit 0;;
  fetchCompilers)
    fetchCompilers
  exit 0;;
  ffxiv | FFXIV)
    if [ ! -d "$ReShadeHome" ]; then update; fi
    XIVinstall
    exit 0;;
  --help|-h|/h|help)
    printHelp
    exit 0;;
  opengl | gl) gapi=opengl32;;
  dx9    |  9) gapi=d3d9;;
  dx10   | 10) gapi=d3d10;;
  dx11   | 11) gapi=d3d11;;
  dx12   | 12) gapi=d3d12;;
  dxgi   | gi) gapi=dxgi;;
  dx*) printf "Unrecognized graphics API version: %s\n" "$1"
    exit 1;;
  backup)
    performBackup;
    exit 0;;
  list | show)
    listGames; [ $? ] && printf "%b" "$gamesList" || printf "No games yet installed to.\n"
    exit 0;;
  remove | rm)
  case $2 in
    ''|*[!0-9]*) printf "Unrecognized number: %s" "$2"; exit 1;;
    *) removeGame "$2"; exit 0;;
  esac
  exit 0;;
  delete | del)
  case $2 in
    ''|*[!0-9]*) printf "Unrecognized number: %s" "$2"; exit 1;;
    *) deleteGame "$2"; exit 0;;
  esac
  exit 0;;
  debug | status)
  debugInfo "$2"
  exit 0;;
  "")
  stepByStep
  exit 0;;
  *)
  printf "Unrecognized command: %s\nPlease use '%s --help' for syntax.\n" "$1" "$0"
  exit 1;;
esac

##
# Below is code for configuring a manual install from the command line that started with setting $gapi, and the only option that doesn't have an exit code associated with a non-error outcome.
exeFile=$2

if [ -z "$exeFile" ]; then printf "No .exe file found, exiting.\n"; exit 1; fi
if [ ! -f "$exeFile" ]; then printf "%s: Invalid file.\n" "$exeFile"; exit 1; fi
gameExe="$(basename "$exeFile")"
if [ "${gameExe##*.}" != "exe" ]; then printf "%s: Not a .exe file.\n" "$gameExe"; exit 1; fi

customGame
