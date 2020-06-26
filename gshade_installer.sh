#!/bin/bash

##
# Housekeeping to respect user's configurations.
if [ -z "$XDG_CONFIG_HOME" ]; then XDG_CONFIG_HOME="$HOME/.config"; fi
if [ -z "$XDG_DATA_HOME" ]; then XDG_DATA_HOME="$HOME/.local/share"; fi

GShadeHome="$XDG_DATA_HOME/GShade"
dbFile="$GShadeHome/games.db"

##
# Yeah I think this'll make life easier.
gameExe=""
gameLoc=""
gamesList=""
gapi=""
ARCH=""

declare -a iniSettings=()

##
# Because slashes and I mean, bash v4 came out when, again?
# Hi self, I don't mean to interrupt.  Didn't you get rid of why you needed this?
shopt -s extglob

##
#Syntax options:
#				$0					-- Guided tutorial.
#				$0 update				-- Install / Update to latest GShade.
#				$0 list					-- List games, numbers provided are for use with remove / delete options.
#				$0 lang <en|ja|ko|de|fr|it> [default|#]	-- Change the language of GShade's interface.  Defaults to the master copy if unspecified.
#				$0 remove <#>				-- Remove <#> from database, leave GShade in whatever shape it's currently in.
#				$0 delete <#>				-- Delete GShade from <#> and remove from database.
#<WINEPREFIX=/path/to/prefix>	$0 ffxiv				-- Install to FFXIV in provided Wine Prefix or autodetect if no Wine Prefix.
# WINEPREFIX=/path/to/prefix	$0 <dx[?]|opengl> /path/to/game.exe	-- Install to custom location with designated graphical API version. 'dxgi' is valid here if needed.
#
#									Note: game.exe should be the GAME'S .exe file, NOT the game's launcher, if it has one!
#
# Undocumented features:
# 				$0 fetchCompilers			-- Fetch new compilers.  If this is needed, there's a good question on 'why and how.'
#				$0 status [upload]			-- Check the status of some important bits, optionally upload it to termbin since it's a curl-friendly site.
#				$0 git|gitUpdate			-- Downloads / updates related git repos.  Check gitUpdate() for more info.
##
printHelp() {
  printf "Syntax options:\n\t\t\t\t$0\t\t\t\t\t\t-- Guided tutorial.\n\t\t\t\t$0 update\t\t\t\t\t-- Install / Update to latest GShade.\n\t\t\t\t$0 list\t\t\t\t\t-- List games, numbers provided are for use with remove / delete options.\n\t\t\t\t$0 lang <en|ja|ko|de|fr|it> [default|#]\t-- Change the language of GShade's interface.  Defaults to the master copy if unspecified.\n\t\t\t\t$0 remove <#>\t\t\t\t-- Remove <#> from database, leave GShade in whatever shape it's currently in.\n\t\t\t\t$0 delete <#>\t\t\t\t-- Delete GShade from <#> and remove from database.\n<WINEPREFIX=/path/to/prefix>\t$0 ffxiv\t\t\t\t\t-- Install to FFXIV in provided Wine Prefix or autodetect if no Wine Prefix.\n WINEPREFIX=/path/to/prefix\t$0 [dx(?)|opengl] /path/to/game.exe\t\t-- Install to custom location with designated graphical API version. 'dxgi' is valid here.\n\n\t\t\t\t\t\t\t\t\tNote: game.exe should be the GAME'S .exe file, NOT the game's launcher, if it has one!\n"
}

##
# Input functions.
yesNo() {
  while true; do
    read -p "$*" -n 1 -r yn
    case $yn in
      [Yy]* ) return 0; break;;
      [Nn]* ) return 1; break;;
      * ) printf "\tPlease answer yes or no.\n";;
    esac
  done
}

readNumber() {
  while true; do
  read -p "> " -r yn
    case $yn in
      ''|*[!0-9]*) printf "Unrecognized number: $2";;
      *) return $(echo $yn | tr -d '\r\n');;
    esac
  done
}

##
# Backup GShade's reshade-shaders (and git shaders if they exist), as well as each games' reshade-presets/ and GShade.ini.
# Backup directory per game is Backups/$year-$month-$day/$time/$game.exe/
# If more than one install has the same base game name (ex, both Lutris and Wine versions of XIV installed), subsequent directories will have a random string generated to keep them separate.
# gameInfo.txt will be created per-game directory to help sorting out original path and prefixes.  These files will contain FULL directory information, with no variable substitutions.
performBackup() {
  [ -z "$1" ] && timestamp=$(date +"%Y-%m-%d/%T") || timestamp="$1"
  mkdir -p "$GShadeHome/Backups/$timestamp" && pushd "$_" > /dev/null
  cp -r "$GShadeHome/reshade-shaders" "./"
  [ -d "$GShadeHome/git/GShade-Shaders" ] && mkdir git && cp -r "$GShadeHome/git/GShade-Shaders" "git/"
  listGames; [ ! $? ] && return 0;
  while IFS="=;" read -r gameName installDir prefixDir gitInstall; do
    backupDir="$GShadeHome/Backups/$timestamp/$gameName"
    [ ! -d "$backupDir" ] && mkdir "$backupDir" || backupDir=$(mktemp -d -t "$gameName-XXXXXXXXXX" --tmpdir=./)
    printf "Game:\t\t$gameName$([ ! -z "$gitInstall" ] && printf "\t -- GIT INSTALLATION")\nInstalled to:\t$installDir\nWINEPREFIX:\t$prefixDir\n" > "$backupDir/gameInfo.txt"
    cp "$installDir/GShade.ini" "$backupDir/"
    cp -r "$installDir/reshade-presets" "$backupDir/"
    cp -r "$GShadeHome/reshade-presets" "$installDir/"
  done < $dbFile
  popd > /dev/null
}

git=1 # Git always fails unless explicitly requested.  Hiding it so most the git stuff is all in the same place.
##
# Unsupported yadda yadda.  $0 git | $0 gitUpdate.  All uses of git in a prefix will be reflected in output.
gitUpdate() {
  [ -z "$1" ] && timestamp=$(date +"%Y-%m-%d/%T") || timestamp="$1"
  [ ! -d "$GShadeHome/git" ] && mkdir -p "$GShadeHome/git"
  backupDir="$GShadeHome/Backups/$timestamp/"
  pushd $GShadeHome/git > /dev/null
  if [ ! -d "$GShadeHome/git/GShade-Shaders" ] || [ ! -d "$GShadeHome/git/GShade-Presets" ]; then
    git clone "https://github.com/Mortalitas/GShade-Presets.git"
    git clone "https://github.com/Mortalitas/GShade-Shaders.git"
  else
    git -C "GShade-Presets" fetch
    git -C "GShade-Shaders" fetch
    if [ $(git -C "GShade-Presets" rev-parse HEAD) != $(git -C "GShade-Presets" rev-parse @{u}) ]; then
      git -C "GShade-Presets" reset --hard -q
      git -C "GShade-Presets" pull -q
      backups=0; [ -d $backupDir ] && backups=1
      while IFS="=;" read -r gameName installDir prefixDir gitInstall; do
        if [ -z "$gitInstall" ]; then gitInstall=1; fi
        if ( $gitInstall -eq 0 ); then
          if ( $backups -eq 0 ); then
            gameBackupDir="$backupDir/$gameName"
            [ ! -d "$gameBackupDir" ] && mkdir "$gameBackupDir" || gameBackupDir=$(mktemp -d -t "$gameName-XXXXXXXXXX" --tmpdir=./)
            printf "Game:\t\t$gameName\t -- GIT INSTALLATION\nInstalled to:\t$installDir\nWINEPREFIX:\t$prefixDir\n" > "$backupDir/gameInfo.txt"
            cp "$installDir/GShade.ini" "$gameBackupDir/"
            rsync -a "$installDir/reshade-presets/" "$gameBackupDir/"
	  fi
	  rsync -a "GShade-Presets/" "$installDir/reshade-presets/"
        fi
      done < $dbFile
    fi
    if [ $(git -C "GShade-Shaders" rev-parse HEAD) != $(git -C "GShade-Shaders" rev-parse @{u}) ]; then
      [ ! -d "$backupDir/git" ] && mkdir -p "$backupDir/git" && cp -r "GShade-Shaders" "$backupDir/git/"
      git -C "GShade-Shaders" reset --hard -q
      git -C "GShade-Shaders" pull -q
    fi
  fi
  popd > /dev/null
}

fetchCompilers() {
    if [ ! -d "$GShadeHome/d3dcompiler_47s" ]; then
      mkdir -p "$GShadeHome/d3dcompiler_47s"
    fi
    pushd "$GShadeHome/d3dcompiler_47s" > /dev/null
    printf "\e[2K\rDownloading 64-bit compiler...  "
    wget -q https://lutris.net/files/tools/dll/d3dcompiler_47.dll
    mv d3dcompiler_47.dll d3dcompiler_47.dll.64bit
    printf "Done!"
    # This following was sourced from The_Riesi @ https://www.reddit.com/r/linux_gaming/comments/b2hi3g/reshade_working_in_wine_43/
    printf "\e[2K\rDownloading 32-bit compiler...  "
    wget -q http://dege.freeweb.hu/dgVoodoo2/D3DCompiler_47.zip && unzip -q D3DCompiler_47.zip && rm D3DCompiler_47.zip
    mv d3dcompiler_47.dll d3dcompiler_47.dll.32bit
    printf "Done!"
    popd > /dev/null
    printf "\e[2K\rd3dcompiler_47s downloaded\n"
}

updateLanguage() {
  gs_lang=$1
  case $gs_lang in
    ja | 1) gs_lang=1;;
    ko | 2) gs_lang=2;;
    de | 3) gs_lang=3;;
    fr | 4) gs_lang=4;;
    it | 5) gs_lang=5;;
    en | 0 | * ) gs_lang=0;;
  esac
  printf "$gs_lang"
}

##
# This is all explicit for settings to save and mostly exists to be extendable for future situations like Language being added.
# Can be passed an argument to specify a file or it will work the default file.
saveSettings() {
  [ -z "$1" ] && iniFile="$GShadeHome/GShade.ini" || iniFile="$1"
  iniSettings+=("Language")
  doesItExist="$(awk -F'=' '/Language/{print $2}' "$iniFile")"
  if [[ $doesItExist != "" ]]; then
    iniSettings+=($doesItExist)
  else
    iniSettings+="$(updateLanguage ${LANG:0:2})\r"
  fi
#  for i in "PerformanceMode"
#    do
#      iniSettings+=("$i")
#      iniSettings+=("$(awk -F'=' '/'"$i"'/{print $2}' "$iniFile")")
#  done
}

restoreSettings() {
  [ -z "$1" ] && iniFile="$GShadeHome/GShade.ini" || iniFile="$1"
  confFile=$(printf "$(<$iniFile)")
  for (( i=0; i<${#iniSettings[@]}; i+=2 ))
    do
      confFile="$(printf "$confFile" | sed "/^${iniSettings[i]}/s/=.*$/=${iniSettings[i+1]}/")"
  done
  printf "$confFile\n" > "$iniFile"
}

##
# For modifying an existing .ini file.
# Invocation: modifySettings <iniFile> <key> <value> [section]
# Return values: 2 = $key not found in file, $section specified but not found.
#		 1 = $key not found in file, $section not specified.
#		 0 = success.
# This assumes the iniFile was already confirmed to exist.  If the key is missing, this function will fail unless it's been told which [section] in the file it belongs to.  If the [section] does not exist, the function will fail.
modifySettings() {
  iniFile="$1"
  key="$2"
  value="$3"
  [ -z "$4" ] && section="" || section="$4"
  if [[ "$(awk -F'=' '/'"$key"'/{print $2}' "$iniFile")" == "" ]]; then
    if [[ $section != "" ]]; then
      line="$(awk -F'=' '/'\\["$section"\\]'/{print NR}' "$iniFile")"
      if [[ $line != "" ]]; then
        sed -i "${line}a $key=$value" "$iniFile"
      else
        return 2
      fi
    else
      return 1
    fi
  else
    sed -i "/^${key}/s/=.*$/=$value/" "$iniFile"
    return 0
  fi
}

##
# Updater / initial installer.
# Certain things ONLY happen during initial installation ATM.  The $GShadeHome directory is created, GShade Converter.exe is downloaded, games.db is created, the d3dcompiler_47.dlls (32 and 64-bit) are both downloaded and put in their own directory.
update() {
  if [ ! -d "$GShadeHome" ]; then
    if (yesNo "GShade initial install not found, would you like to create it?  "); then printf "\nCreating...  "; else printf "\nAborting installation.\n"; exit 1; fi
    mkdir -p "$GShadeHome/reshade-presets/" && pushd "$GShadeHome" > /dev/null && touch games.db && wget -q https://mortalitas.github.io/ffxiv/GShade/GShade%20Converter.exe && popd > /dev/null
    fetchCompilers
    if ( ! command -v wine >/dev/null 2>&1 -eq 0 ); then printf "\e[31mWine not found in path -- please install wine!\e[0m\n"; fi
    if ( ! command -v md5sum >/dev/null 2>&1 -eq 0 ); then printf "\e[31mmd5sum not found in path -- please install md5sum!\e[0m\n"; fi
  fi
  gshadeCurrent=$(wget -O- -q https://mortalitas.github.io/ffxiv/GShade/Update.txt)
  if [[ -f "$GShadeHome/version" ]] && [[ $(<"$GShadeHome/version") == $gshadeCurrent ]]; then
    printf "Up to date.\n"
  else
    pushd "$GShadeHome" > /dev/null
    ##
    # Do preset releases always match GShade updates or should this always update?  Hm.
    wget -q https://github.com/Mortalitas/GShade-Presets/archive/master.zip
    unzip -qquo master.zip && rm -r master.zip reshade-presets && mv "GShade-Presets-master" "reshade-presets"
    timestamp=$(date +"%Y-%m-%d/%T")
    if [ -f "version" ]; then performBackup $timestamp; [ -d "$GShade/git" ] && gitUpdate $timestamp; fi
    printf "Saving GShade.ini settings..."
    saveSettings
    rm -rf "GShade.Latest.zip" "reshade-shaders"
    wget https://github.com/Mortalitas/GShade/releases/latest/download/GShade.Latest.zip
    unzip -qquo GShade.Latest.zip
    printf "\e[2K\rRestoring any applicable GShade.ini settings...  "
    restoreSettings
    printf "Completed!\n"
    old64="$(md5sum GShade64.dll | awk '{ print $1 }')"
    old32="$(md5sum GShade32.dll | awk '{ print $1 }')"
    mv d3d11.dll GShade64.dll
    mv d3d9.dll GShade32.dll
    printf "$gshadeCurrent\n" > version
    ##
    # Have to update reshade-presets in games' directories and update any hard-installs.
    while IFS="=;" read -r gameName installDir prefixDir gitInstall; do
      if [ -z "$gitInstall" ]; then gitInstall=1; fi
      if [ "$gitInstall" -eq 1 ]; then
        cp -rf "reshade-presets/*" "$installDir/reshade-presets/"
      fi
      # Hard install upgrade begin.
      if [[ $(find "$installDir" -maxdepth 1 -lname "$GShadeHome/" -print) == "" ]]; then
        gArch=""
	md5goal=""
        if printf "$installDir/$gameName" | grep -q "80386"; then
          gArch="32"; md5goal="$old32"
        elif printf "$installDir/$gameName" | grep -q "x86-64"; then
          gArch="64"; md5goal="$old64"
        fi
        gName=$(basename $(find "$installDir" -maxdepth 1 \( -name "d3d*.dll" ! -name "d3dcompiler_47.dll" \)))
        if [ -f "$installDir/opengl32.dll" ]; then gName="opengl32.dll"; fi
        if [[ $gName != "" ]]; then
          if [[ "$(md5sum "$installDir/${gName}" | awk '{ print $1 }')" == "$md5goal" ]]; then cp -f "GShade${gArch}.dll" "$installDir/${gName}.dll"; fi
        fi
	if [ -f "$installDir/dxgi.dll" ] && [[ "$(md5sum "$installDir/dxgi.dll" | awk '{ print $1}')" == "$md5goal" ]]; then cp -f "GShade${gArch}.dll" "$installDir/dxgi.dll"; fi
      fi
      # Hard install update end.
    done < $dbFile
    popd > /dev/null
    printf "GShade-$gshadeCurrent installed.\n"
  fi
}

##
# List games found in $dbFile ($GShadeHome/games.db), formatted as:
# #) Game:		<exe file>	[[ 'GIT INSTALLATION' if appropriate. ]]
# 	Installed to:	<exe file's location>
# 	WINEPREFIX:	<Location of wine's prefix installed to.>
listGames() {
  gamesList=""			# Always blank the list in case user is confirming removal after checking before.
  i=0				# Yeah, iterating for removal / deletion numbering options.
  if [ ! -s $dbFile ]; then
    return 1
  fi
  while IFS="=;" read -r gameName installDir prefixDir gitInstall; do
    pushd "$installDir" > /dev/null
    gapiln=$(find -maxdepth 1 -name "*.dll" -lname "$GShadeHome/GShade*.dll" -exec basename {} ';')
    if [ -z $gapiln ]; then
      fileString="$(file "$gameName")"
      gmd5=""
      if printf "$fileString" | grep -q "80386"; then
        gmd5="$(md5sum "$GShadeHome/GShade32.dll" | awk '{ print $1 }')"
      elif printf "$fileString" | grep -q "x86-64"; then
        gmd5="$(md5sum "$GShadeHome/GShade64.dll" | awk '{ print $1 }')"
      fi
      # Check dxgi and opengl32 before we start hitting find up.
      if [ -f "dxgi.dll" ] && [ "$gmd5" == "$(md5sum "dxgi.dll" | awk '{ print $1 }')" ]; then gapiln="dxgi.dll"; fi
      if [ -z "$gapi" ] && [ -f "opengl32.dll" ] && [ "$gmd5" == "$(md5sum "opengl32.dll" | awk '{ print $1 }')" ]; then gapiln="opengl32.dll"; fi
      if [ -z "$gapi" ] && [ -f "$(basename $(find -maxdepth 1 \( -name "d3d*.dll" ! -name "d3dcompiler_47.dll" \)) 2>&1)" ] && [ "$gmd5" == "$(md5sum "$(basename $(find -maxdepth 1 \( -name "d3d*.dll" ! -name "d3dcompiler_47.dll" \)))" | awk '{ print $1 }')" ]; then gapiln="$(basename $(find -maxdepth 1 \( -name "d3d*.dll" ! -name "d3dcompiler_47.dll" \)))"; fi
    fi
    popd > /dev/null
    gamesList="$gamesList$((++i))) Game:\t\t$([ -f "$installDir/$gameName" ] && printf "\e[32m" || printf "\e[31m")$gameName\e[0m\t\t$([ -L "$installDir/$gapiln" ] && printf "\e[32m[$gapiln -> $([ ! -f $(readlink -f "$installDir/$gapiln") ] && printf "\e[0m\e[31m")$(basename "$(readlink -f "$installDir/$gapiln")")\e[0m\e[32m]\e[0m" || ([ -f "$installDir/$gapiln" ] && printf "\e[33m[$gapiln]\e[0m" || printf "\e[31mGShade symlink not found!\e[0m")) $([ ! -z "$gitInstall" ] && printf "\t\t\e[33m-- GIT INSTALLATION\e[0m")\n\tInstalled to:\t$([ ! -d "$installDir" ] && printf "\e[31m")${installDir/#$HOME/"\$HOME"}\e[0m\n\tWINEPREFIX:\t$([ ! -d "$prefixDir" ] && printf "\e[31m")${prefixDir/#$HOME/"\$HOME"}\e[0m\n"
  done < $dbFile
  return 0 
}

##
# Record game's location to a flat file database for backing up.  Check for EXACT duplicates, OR for git installations being flipped on or off as git.
recordGame() {
  i=1
  while IFS="=;" read -r gameName installDir prefixDir gitInstall; do
    if [ -z "$gitInstall" ]; then gitInstall=1; fi
    if [ "$gameName" == "$gameExe" ] && [ "$installDir" == "$gameLoc" ] && [ "$prefixDir" == "$WINEPREFIX" ] && [ "$gitInstall" != "$git" ]; then removeGame $i; fi
    if [ "$gameName" == "$gameExe" ] && [ "$installDir" == "$gameLoc" ] && [ "$prefixDir" == "$WINEPREFIX" ] && [ "$gitInstall" == "$git" ]; then return 0; fi
    ((i++))
  done < $dbFile
  record="$gameExe=$gameLoc;$WINEPREFIX;$([ $git == 0 ] && printf "0")"
  printf "$record\n" >> $dbFile
  return 0
}

##
# Invokation: getGame #
# Pulls the relevant variables for a game based on line number from games.db.
getGame() {
  [ -z "$1" ] && return 1 || line="$1"
  OldIFS="$IFS"
  IFS='=;'
  set -- `awk -F '=;' 'NR=='"$line"' {print $1, $2, $3, $4}' "$HOME/.local/share/GShade/games.db"`
  IFS="$OldIFS"
  gameExe=$1 gameLoc=$2 WINEPREFIX=$3 git=$4
}

##
# Invokation: forgetGame
# Just sets everything to default values that getGame sets.  More of a safety net than a necessity currently.
forgetGame() {
  gameExe="" gameLoc="" WINEPREFIX="" git=1
}

##
# Clean Wine and soft links pointing to $GShadeHome from the WINEPREFIX and current directory.
cleanWineLinks() {
  if ( validPrefix ); then
    export WINEPREFIX
    wine reg delete 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v d3dcompiler_47 /f > /dev/null 2>&1
    oldGapi=$(basename $(find -maxdepth 1 -lname "$GShadeHome/GShade*.dll" -exec basename {} ';') .dll)
    wine reg delete 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v ${oldGapi} /f > /dev/null 2>&1
  fi
  find -maxdepth 1 -lname "$GShadeHome/*" -delete
}

##
# Invocation: removeGame #
# Removes line number # from $dbFile.
removeGame() {
  newFile=$(awk -v line=$1 'NR!=line' $dbFile)
  printf "$newFile\n" > $dbFile
}

##
# Invocation: deleteGame #
# Delete all traces of GShade from # in $dbFile and its associated installation directory and WINEPREFIX.  But make a backup first.
deleteGame() {
  performBackup
  tempWINEPREFIX="$WINEPREFIX"
  IFS="=;" read -r gameName installDir WINEPREFIX gitInstall <<< $(sed "${1}q;d" $dbFile)
  if [ ! -d "$installDir" ]; then
    printf "Installation directory not found -- nothing to delete.  Removal recommended instead.  Exiting.\n"
    exit 1
  fi
  pushd "$installDir" > /dev/null
  rm -rf 'reshade-presets' 'GShade.ini'
  cleanWineLinks
  popd > /dev/null
  WINEPREFIX="$tempWINEPREFIX"
  removeGame $1
}

##
# WINEPREFIX, gameLoc, gapi, and ARCH (I use Gentoo BTW) must all have been configured elsewhere in the script.
# This is where the magic happens, or at least where the soft links happen and a few copies and the required dll overrides.
# This will also make an individual backup for an install's reshade-presets folder if it happens to exist, and ignore GShade.ini if it's already there.
installGame() {
  # Get to the WINEPREFIX to make sure it's recorded as absolute and not relative.
  pushd $WINEPREFIX > /dev/null; WINEPREFIX="$(pwd)/"; popd > /dev/null
#  WINEPREFIX="${WINEPREFIX//+(\/)//}"		# Legacy, but interesting to remember.
  pushd "$gameLoc" > /dev/null
  # Clean up an old install before the new soft links and reg edits are re-added.  Mostly to deal with changing gapi's.
  cleanWineLinks
  ln -sfn "$GShadeHome/d3dcompiler_47s/d3dcompiler_47.dll.${ARCH}bit" d3dcompiler_47.dll
  if [ $? != 0 ] || [ ! -L "d3dcompiler_47.dll" ]; then cp "$GShadeHome/d3dcompiler_47s/d3dcompiler_47.dll.${ARCH}bit" d3dcompiler_47.dll; fi
  ln -sfn "$GShadeHome/GShade${ARCH}.dll" ${gapi}.dll
  if [ $? != 0 ] || [ ! -L "${gapi}.dll" ]; then cp "$GShadeHome/GShade${ARCH}.dll" $gapi.dll; fi
  export WINEPREFIX
  wine reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v d3dcompiler_47 /d native /f >/dev/null 2>&1
  wine reg add 'HKEY_CURRENT_USER\Software\Wine\DllOverrides' /v ${gapi} /d native,builtin /f >/dev/null 2>&1
  if [ ! -f "GShade.ini" ]; then cp "$GShadeHome/$([ $git == 0 ] && printf "git/GShade-Shaders/")GShade.ini" "GShade.ini"; fi
  ln -sfn "$GShadeHome/$([ $git == 0 ] && printf "git/GShade-Shaders" || printf "reshade-shaders")" "reshade-shaders"
  if [ $? != 0 ] || [ ! -L "reshade-shaders" ]; then cp -a "$GShadeHome/$([ $git == 0 ] && printf "git/GShade-Shaders" || printf "reshade-shaders")" "reshade-shaders"; fi
  ln -sfn "$GShadeHome/$([ $git == 0 ] && printf "git/GShade-Shaders/")notification.wav" "notification.wav"
  if [ $? != 0 ] || [ ! -L "notification.wav" ]; then cp -a "$GShadeHome/notification.wav" "notification.wav"; fi
  if [ -d "$gameLoc/reshade-presets" ]; then
    timestamp=$(date +"%Y-%m-%d/%T")
    backupDir="$GShadeHome/Backups/$timestamp/$gameExe/"
    mkdir -p "$backupDir"
    cp -a "reshade-presets" "$backupDir"
    printf "Game:\t\t$gameExe$([ ! -z "$git" ] && printf "\t -- GIT INSTALLATION")\nInstalled to:\t$gameLoc\nWINEPREFIX:\t$WINEPREFIX\n" > "$backupDir/gameInfo.txt"
  fi
  rsync -a "$GShadeHome/$([ $git == 0 ] && printf "git/GShade-Presets/" || printf "reshade-presets")" "./$([ $git == 0 ] && printf "reshade-presets/")"
  ln -sfn "$GShadeHome/GShade Converter.exe" "GShade Converter.exe"
  if [ $? != 0 ] || [ ! -L "GShade Converter.exe" ]; then cp -a "$GShadeHome/GShade Converter.exe" "GShade Converter.exe"; fi
  recordGame
  popd > /dev/null
}

##
# Return 1 if not a valid WINEPREFIX, return 0 if it is.  Or, at least if it's close enough.
validPrefix() {
  if [ ! -f "$WINEPREFIX/system.reg" ]; then
    return 1;
  fi
  return 0;
}

##
# Automatic install for FFXIV.  Offers to install any that it finds in the following order: WINEPREFIX, Steam, Lutris.
XIVinstall() {
  gameExe="ffxiv_dx11.exe"
  gapi=d3d11
  ARCH=64

  ##
  # This will be relevant if it exists.
  lutrisYaml=$(find $XDG_CONFIG_HOME/lutris/games/ -name 'final-fantasy-xiv*' 2>/dev/null)

  if [ -n "$WINEPREFIX" ] && ( validPrefix ); then
    gameLoc="$WINEPREFIX/drive_c/Program Files (x86)/SquareEnix/FINAL FANTASY XIV - A Realm Reborn/game/"
      if [ ! -d "$gameLoc" ]; then
      printf "\nThe WINEPREFIX was found, but the game was not.  Exiting.\n"
      exit 1
    fi
    printf "\nWine install found!\n\tPrefix location: $WINEPREFIX\n\tGame location: $gameLoc\n"
    if (yesNo "Install? "); then
      printf "\nInstalling...  ";
      installGame
      printf "Complete!\n"
    fi
  fi
  if [[ -n "$lutrisYaml" ]] && [ -f "$lutrisYaml" ]; then
    WINEPREFIX="$(awk -F': ' '/prefix/{print $2}' ${lutrisYaml})"
    gameLoc="$WINEPREFIX/drive_c/Program Files (x86)/SquareEnix/FINAL FANTASY XIV - A Realm Reborn/game/"
    printf "\nLutris install found!\n\tPrefix location: $WINEPREFIX\n\tGame location: $gameLoc\n"
    if (yesNo "Install? "); then
      printf "\nInstalling...  "
      installGame
      printf "Complete!\n"
    fi
  fi
  if [ -d "$HOME/.steam/steam/steamapps/common/FINAL FANTASY XIV Online/game/" ] && [ -d "$HOME/.steam/steam/steamapps/compatdata/39210/pfx" ]; then
    WINEPREFIX="$HOME/.steam/steam/steamapps/compatdata/39210/pfx"
    gameLoc="$HOME/.steam/steam/steamapps/common/FINAL FANTASY XIV Online/game/"
    printf "\nSteam install found!\n\tPrefix location: $WINEPREFIX\n\tGame location: $gameLoc\n"
    if (yesNo "Install? "); then
        if ( ! yesNo "Use $gapi instead of dxgi?  If you are having issues with GShade when using other overlays (Steam or Discord, for instance), you may wish to try dxgi mode instead." ); then gapi=dxgi; fi
      printf "\nInstalling...  "
      installGame
      printf "Complete!\n"
    fi
  fi
  printf "\nScan complete.\n"
}

##
# Walkthrough for custom game option selected from the general menu.  Gets input for $gapi, $WINEPREFIX, $gameExe, and $exeFile (which is really $fullPathToExeFile).
customGamePrompt() {
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
  while ! { [ -d "$WINEPREFIX" ] && ( validPrefix ); }; do
    read -p "Where is the WINEPREFIX located?  (The directory where your drive_c folder is located): " WINEPREFIX
    if [ ! -d "$WINEPREFIX" ]; then printf "$WINEPREFIX: Directory does not exist.\n";
    elif ( ! validPrefix ); then printf "$WINEPREFIX: Not a valid prefix, please confirm this is a working prefix.\n"; fi
  done
#  gameExe="$(basename $exeFile)" 2>&1 > /dev/null
  while [ ! -f "$exeFile" ] && [ "${gameExe##*.}" != "exe" ]; do
    read -p "Where is the game's .exe file?  (Note: NOT the launcher for the game!): " exeFile
    gameExe="$(basename "$exeFile")" 2>&1 > /dev/null
    if [ ! -f "$exeFile" ]; then printf "$exeFile: Not a file, please confirm the path and file name.\n";
    elif [ "${gameExe##*.}" != "exe" ]; then printf "$gameExe: Not a .exe file."; fi
  done
  if ( [ $gapi != "dxgi" ] && ! yesNo "Use $gapi instead of dxgi?  If you are having issues with GShade when using other overlays (Steam or Discord, for instance), you may wish to try dxgi mode instead. (y/n) " ) then printf "\n"; gapi="dxgi"; else printf "\n"; fi
}

# Determines $ARCH and $gameLoc from $exeFile.
customGame() {
  # Bank the dirname as an absolute path.
  pushd "$(dirname "$exeFile")" > /dev/null; gameLoc="$(pwd)/"; popd > /dev/null
  # Determine architecture.
  fileString="$(file "$exeFile")"
  if printf "$fileString" | grep -q "80386"; then
    ARCH="32"
  elif printf "$fileString" | grep -q "x86-64"; then
    ARCH="64"
  else
    printf "$exeFile: Invalid exe file type.\n"
    exit 1
  fi
  installGame
}

##
# Sometimes the menu should get repeated, sometimes not.  Easiest to call a function for it.
menu() {
  printf "Welcome to GShade!  Please select an option:\n\t1) Check for an update to GShade\n\t2) Install to a custom game\n\tF) Attempt auto-install for FFXIV\n\tB) Create a backup of existing GShade game installations\n\tS) Show games GShade is installed to\n\tL) Change GShade's language\n\tR) Remove game from installed games list\n\tD) Delete GShade from game and remove from list\n\t0) Redownload compilers\n\tQ) Quit\n"
}

##
# Guided setup with menus.
stepByStep() {
  [[ ! -d "$GShadeHome" ]] && update
  menu
  while true; do
    read -p "> " -n 1 -r yn
    case $yn in
      [1]* ) printf "\n"; update;;
      [2]* ) printf "\n"; customGamePrompt; customGame; break;;
      [Ff]* ) XIVinstall; break;;
      [Bb]* ) performBackup; break;;
      [Ss]* ) listGames; if [ $? ]; then printf "\n$gamesList"; else printf "\nNo games yet installed to.\n"; fi;;
      [Rr]* ) listGames  # Remove from list & untrack.
        if [ $? ]; then
          printf "\n$gamesList"
          readNumber; selection=$?
          removeGame $selection
        else
          printf "\nNo games yet installed to remove.\n"
	fi
	menu;;
      [Dd]* ) listGames  # Delete from game / list
        if [ $? ]; then
          printf "\n$gamesList"
          readNumber; selection=$?
          deleteGame $selection
	else
	  printf "\nNo games yet installed to remove.\n"
        fi
	menu;;
      [Ll]* ) listGames  # Change GShade's language in game.
        if [ $? ]; then
	  printf "\n0) Default GShade.ini (for future installations)\n$gamesList"
	  readNumber; selection=$?
	  if [ $selection -eq 0 ]; then
	    gameLoc="$GShadeHome"
	  else
  	    getGame $selection
	  fi
	  if [ ! -f "$gameLoc/GShade.ini" ]; then
	    printf "\nNo GShade.ini found.  Please confirm GShade is working within this install.\n"
	  else
	    read -p "Please choose a language (en, ja, ko, de, fr, it): " -n 2 -r langIn
	    lang="$(echo "$langIn" | tr '[:upper:]' '[:lower:]')"
            case $lang in
	      en | ja | ko | de | fr | it) modifySettings "$gameLoc/GShade.ini" "Language" "$(updateLanguage $lang)" "GENERAL"
	        printf "\nUpdated!\n"
	    	;;
	      *) printf "Unknown language.  Please retry.";;
	    esac
	  fi
        else
	  printf "\nUpdating default GShade.ini -- this will affect all future installs.\n"
	  read -p "Please choose a language (en, ja, ko, de, fr, it): " -n 2 -r langIn
	    lang="$(echo "$langIn" | tr '[:upper:]' '[:lower:]')"
            case $lang in
	      en | ja | ko | de | fr | it) modifySettings "$GShadeHome/GShade.ini" "Language" "$(updateLanguage $lang)" "GENERAL"
	        printf "\nUpdated!\n"
	    	;;
	      *) printf "Unknown language.  Please retry.";;
	    esac
	fi
      forgetGame
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
# Installation location:  $GShadeHome
# Installation version:   Contents of $GShadeHome/version
# d3dcompiler_47 32-bit:  md5sum on d3dcompiler_47s/d3dcompiler_47.dll.32bit
# d3dcompiler_47 64-bit:  md5sum on d3dcompiler_47s/d3dcompiler_47.dll.64bit
# Wine version:           Wine version if installed, and if it's not installed, well, here's the problem.
# games.db:
#   listGames()'s output.
debugInfo(){
  if [ ! -d "$GShadeHome" ]; then
    output=$(printf "\e[31mGShade installation not found in folder '${GShadeHome/#$HOME/"\$HOME"}'.\e[0m\nIf your \$XDG_DATA_HOME environment variable has recently changed, you must migrate files manually from the old location.  Exiting.\n")
    exit 1
  fi
  pushd "$GShadeHome" > /dev/null
  md5sum --status --ignore-missing -c <<<"c971cde5194dd761456214dd5365bdc7 d3dcompiler_47s/d3dcompiler_47.dll.32bit"
  PS=$?
  md5sum --status --ignore-missing -c <<<"b0ae3aa9dd1ebd60bdf51cb94834cd04 d3dcompiler_47s/d3dcompiler_47.dll.64bit"
  N64=$?
  output=$(printf "Installation location:\t${GShadeHome/#$HOME/"\$HOME"}/\nInstallation version:\t$(cat $GShadeHome/version)\nd3dcompiler_47 32-bit:\t$([ $PS -eq 0 ] && printf "\e[32mOK" || printf "\e[31mmd5sum failure")\e[0m\nd3dcompiler_47 64-bit:\t$([ $N64 -eq 0 ] && printf "\e[32mOK" || printf "\e[31mmd5sum failure")\e[0m\nWine version:\t\t$($( command -v wine >/dev/null 2>&1 -eq 0 ) && printf "\e[32m$(wine --version)\e[0m" || printf "\e[31mNot installed\e0m")")
  listGames; [ $? ] && output+=$(printf "\ngames.db:\n${gamesList/#$HOME/"\$HOME"}") || output+=$(printf "\ngames.db:\tEmpty or does not currently exist.")
  popd > /dev/null
  if [ "$1" != "upload" ]; then
    printf "$output\n"
  else
    uploadLoc=$(printf "$output" | (exec 3<>/dev/tcp/termbin.com/9999; cat >&3; cat <&3; exec 3<&-))
    printf "$uploadLoc\n"
  fi
  exit 0
}

##
# Command line options:
case $1 in
  update)
  update
  exit 0;;
  fetchCompilers)
  fetchCompilers
  exit 0;;
  ffxiv | FFXIV)
  if [ ! -d "$GShadeHome" ]; then update; fi
  XIVinstall
  exit 0;;
  --help|-h|/h|help)
  printHelp
  exit 0;;
  opengl | gl) gapi=opengl32;;
  dx9  |  9) gapi=d3d9;;
  dx10 | 10) gapi=d3d10;;
  dx11 | 11) gapi=d3d11;;
  dx12 | 12) gapi=d3d12;;
  dxgi | gi) gapi=dxgi;;
  dx*) printf "Unrecognized graphics API version: $1\n"
  exit 1;;
  backup)
  performBackup;
  exit 0;;
  list | show)
  listGames; [ $? ] && printf "$gamesList" || printf "No games yet installed to.\n"
  exit 0;;
  remove | rm)
  case $2 in
    ''|*[!0-9]*) printf "Unrecognized number: $2"; exit 1;;
    *) removeGame $2; exit 0;;
  esac
  exit 0;;
  delete | del)
  case $2 in
    ''|*[!0-9]*) printf "Unrecognized number: $2"; exit 1;;
    *) deleteGame $2; exit 0;;
  esac
  exit 0;;
  lang | language)
  lang="$(echo "$2" | tr '[:upper:]' '[:lower:]')"
  case $lang in
    en | ja | ko | de | fr | it) numberLang=$(updateLanguage "$lang");;
    *) printf "Unknown language, '$2'.  Please retry."; exit 1;;
  esac
  case $3 in
    default | 0) gameLoc="$GShadeHome";;
    ''|*[!0-9]*) printf "Unrecognized installation candidate: $3"; exit 1;;
    *) getGame "$3"
  esac
  modifySettings "$gameLoc/GShade.ini" "Language" "$numberLang" "GENERAL"
  exit 0;;
  git | gitUpdate)
  gitUpdate
  exit 0;;
  debug | status)
  debugInfo $2 
  exit 0;;
  "")
  stepByStep
  exit 0;;
  *)
  printf "Unrecognized command: $1\nPlease use '$0 --help' for syntax.\n"
  exit 1;;
esac

##
# Below is code for configuring a manual install from the command line that started with setting $gapi, and the only option that doesn't have an exit code associated with a non-error outcome.
exeFile=$2

if [ -z "$WINEPREFIX" ]; then printf "Missing required WINEPREFIX, exiting.\n"; exit 1; fi
if ( ! validPrefix ); then printf "Not a valid WINEPREFIX, exiting.\n"; exit 1; fi
if [ -z "$exeFile" ]; then printf "No .exe file found, exiting.\n"; exit 1; fi
if [ ! -f "$exeFile" ]; then printf "$exeFile: Invalid file.\n"; exit 1; fi
gameExe="$(basename "$exeFile")"
if [ "${gameExe##*.}" != "exe" ]; then printf "$gameExe: Not a .exe file.\n"; exit 1; fi

# If there's an extra argument AND it's 'git' AND the git directories already exist... fine.  You get git.
if [ ! -z $3 ] && [ $3 == "git" ] && [ -d "$GShadeHome/git/GShade-Shaders" ] && [ -d "$GShadeHome/git/GShade-Presets" ]; then git=0; fi

customGame

