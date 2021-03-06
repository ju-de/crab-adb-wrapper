#!/bin/bash

adb="$ANDROID_HOME/platform-tools/adb"

DEVICEIDS=($($adb devices 2> /dev/null | sed '1,1d' | sed '$d' | cut -f 1 | sort)) 
DEVICEINFO=()
SELECTEDIDS=()
SELECTEDINFO=()
FILTERS=("-d" "-e" "-a" "-ad" "-ae")
COMMANDS=("help" "l" "s" "t" "i" "u" "c")

selection=true # Toggles device selection
flag=$2 # Command flag
selectedCommand="" # Method to be executed on devices
adbCommand=$(echo $@ | cut -d " " -f2-) # ADB command flag
textInput=$3
apkFile=$3
packageName=""

# Checks to see if ANDROID_HOME has been set
checkAndroidHome() {
	$adb version >/dev/null 2>&1
	error=$?
	if [[ -z $ANDROID_HOME ]]; then
		echo "ANDROID_HOME variable is not found in the PATH."
		exit 1
	elif [[ $error == 127 ]]; then
		echo "ANDROID_HOME is found at $ANDROID_HOME, but adb command is not found."
		echo "Ensure the correct installation of Android SDK."
		exit 1
	fi
}

# Force stops the specified application and clears data
crabClearData() {
	# packageName=`aapt dump badging $1 | grep package: | cut -d "'" -f 2`
	echo "Clearing data for $packageName on" ${SELECTEDINFO[$2]}		
	status=`$adb -s ${SELECTEDIDS[$2]} shell pm clear $packageName`
	echo "Clearing data for $packageName on ${SELECTEDINFO[$2]}: $status"
	$adb -s ${SELECTEDIDS[$2]} shell am start -a android.intent.action.MAIN -n $packageName/$(aapt dump badging $1 | grep launchable | cut -d "'" -f 2) >> /dev/null 
}

# Shows the user how to use the script
crabHelp() {
	echo "Crab Version 1.0 using $($adb help 2>&1)"
	echo ''
	echo "***Custom Crab Features***
Selection Filters:
  -d 		      - physical devices
  -e 		      - emulators
  -a 		      - selects all
  -ad 		      - automatically selects all physical devices
  -ae 		      - automatically selects all emulators

Commands:
  adb help             - shows usage of the script      
  adb l                - lists connected devices
  adb s                - takes a screenshot on selected devices
  adb t <text input>   - types on selected devices
  adb i <file>         - pushes this package file to selected devices and installs it (overinstall)
  adb u <file>         - removes this app package from selected devices
  adb <adb command>    - executes command using original adb"
}

# Outputs connected devices
crabList() {
    for i in ${!DEVICEIDS[@]}; do
        printf "%3d%s) %s" $((i+1)) "${choices[i]:- }" 
        echo ${DEVICEINFO[i]} ${DEVICEIDS[i]}
    done
    [[ "$msg" ]] && echo $msg; :
}

# Installs the specified .apk file to selected devices (modified code from superInstall)
crabInstall() {
 	echo "Installing $1 to" ${SELECTEDINFO[$2]}
	status=`$adb -s ${SELECTEDIDS[$2]} install -r $1 | cut -f 1 | tr '\n' ' '` # -r for overinstall
	$adb -s ${SELECTEDIDS[$2]} shell am start -a android.intent.action.MAIN -n $packageName/$(aapt dump badging $1 | grep launchable | cut -d "'" -f 2) >> /dev/null
	echo " Installation of $1 to ${SELECTEDINFO[$2]}: $status" 
}

# Prompts user to select a device if multiple are connected
crabSelect() {
	if [[ $selection == true ]]; then
		if [[ ${#DEVICEIDS[@]} == 1 ]]; then
				echo 'Selected the only detected device:' ${DEVICEINFO[0]} ${DEVICEIDS[0]}
				SELECTEDIDS=${DEVICEIDS[0]}
				SELECTEDINFO=${DEVICEINFO[0]}
		else
			# Modified code from http://serverfault.com/questions/144939/multi-select-menu-in-bash-script
			echo "Multiple devices connected. Please select from the list:"
			echo "  0 ) All devices"
			prompt="Input an option to select (Input again to deselect; hit ENTER key when done): "
			while crabList && read -rp "$prompt" num && [[ "$num" ]]; do
				echo "  0 ) All devices"
			    if [[ $num == 0 ]]; then 
			    	while [[ $num < ${#DEVICEIDS[@]} ]]; do
			    		choices[num]="+"
			    		num=$((num+1))
			    	done
			    	msg="All devices were selected"
			    else
				    [[ "$num" != *[![:digit:]]* ]] &&
				    (( num >= 0 && num <= ${#DEVICEIDS[@]} )) ||
				    { msg="Invalid option: $num"; continue; }
				    ((num--)); msg="${DEVICEINFO[num]} ${DEVICEIDS[num]} was ${choices[num]:+de}selected"
				    [[ "${choices[num]}" ]] && choices[num]="" || choices[num]="+"
			    fi
			done
			echo "You selected:"; msg=" nothing"
			for i in ${!DEVICEIDS[@]}; do 
			    [[ "${choices[i]}" ]] && { 
				    echo ${DEVICEINFO[i]} ${DEVICEIDS[i]}; 
				    msg=""; 
				    SELECTEDIDS+=(${DEVICEIDS[i]});
				    SELECTEDINFO+=("${DEVICEINFO[i]}");
				}
			done
			echo "$msg"
			if [[ ${#SELECTEDIDS[@]} < 1 ]]; then
				exit 1
			fi
		fi
	fi
}

# Takes a screenshot on selected devices (modified code from superadb)
crabScreenshot() {
	timestamp=$(date +"%I-%M-%S")
	echo 'Taking screenshot on' ${SELECTEDINFO[$1]}
	# Credit to http://www.growingwiththeweb.com/2014/01/handy-adb-commands-for-android.html for screenshot copying directly to the current directory
	$adb -s ${SELECTEDIDS[$1]} shell screencap -p | perl -pe 's/\x0D\x0A/\x0A/g' >> "${SELECTEDINFO[$1]}"-$timestamp-"screenshot.png"
	echo 'Successfully took screenshot on' ${SELECTEDINFO[$1]} '@' $timestamp
}

# Inputs text on selected devices (modified code from superadb)
crabType() {
	if [[  -z "$textInput"  ]]; then
			echo 'Text input stream is empty.'
			echo ''
			echo 'Enter text like this:'
			echo '     adb t "Enter text here"'
			echo 'If quotes are not used, then only the first word will be typed.'
			exit 1
	else
		echo 'Entering text on' ${SELECTEDINFO[$1]}
		parsedText=${textInput// /%s} # Replaces all spaces with %s
		$adb -s ${SELECTEDIDS[$1]} shell input text $parsedText
		echo 'Successfully entered text on' ${SELECTEDINFO[$1]}
	fi
}

# Uninstalled the specified .apk file from selected devices (modified code from superInstall)
crabUninstall() {
	# packageName=`aapt dump badging $1 | grep package: | cut -d "'" -f 2`
	echo "Uninstalling $packageName from ${SELECTEDINFO[$2]}if it exists:"
	status=`$adb -s ${SELECTEDIDS[$2]} uninstall $packageName | cut -f 1 -d " "`
	echo "Uninstallation of $packageName from ${SELECTEDINFO[$2]}: $status"
}

# Executes command on selected devices
executeCommand() {
	if [[ ${#SELECTEDIDS[@]} > 1 ]]; then
		for i in ${!SELECTEDIDS[@]}; do { # Executes command in the background
			$selectedCommand $i # i is passed in as an argument
		} &	
		done; wait
	else
		$selectedCommand # Executes command normally
	fi
}

# Adds device info to a global array (modified code from superInstall)
getDeviceInfo() {
	if [[ ${#DEVICEIDS[@]} == 0 ]]; then 
		echo 'No devices detected!' 
		echo 'Troubleshooting tips if device is plugged in:'
		echo ' - USB Debugging should be enabled on the device.'
		echo ' - Execute in terminal "adb kill-server"'
		echo ' - Execute in terminal "adb start-server"'
		exit 1
	else
		echo 'Number of devices found:' ${#DEVICEIDS[@]}
		for i in ${!DEVICEIDS[@]}; do
			DEVICEINFO+=("$(echo "$($adb -s ${DEVICEIDS[i]} shell "getprop ro.product.manufacturer && getprop ro.product.model && getprop ro.build.version.release" | tr -d '\r')" | tr '\n' ' ')")
		done
	fi			
}

# Gets all emulators
getEmulators() {
	DEVICEIDS=($($adb devices | sed '1,1d' | sed '$d' | cut -f 1 | sort | grep '^emu')) 
	getDeviceInfo
}

# Gets all physical devices
getRealDevices() {
	DEVICEIDS=($($adb devices | sed '1,1d' | sed '$d' | cut -f 1 | sort | grep -v '^emu')) 
	getDeviceInfo
}

runAdb() {
	$adb -s ${SELECTEDIDS[i]} $adbCommand 2> /dev/null
	if [[ $(echo $?) == 1 ]]; then
		crabHelp
		exit 1
	fi
}

# Checks if a file is a valid .apk file (modified code from superInstall)
setApkFile() {
	if ! test -e "$1"; then 
		echo "Please specify an existing .apk file."
		exit 1
	elif [[ ${1: -3} == "apk" ]]; then
		packageName=`aapt dump badging $1 | grep package: | cut -d "'" -f 2`
		# :
	else
		echo "The application file is not an .apk file; Please specify a valid application file."
		exit 1
	fi
}

# Main Procedure
#================

checkAndroidHome

if [[ $1 == ${COMMANDS[0]} || $1 == "" ]]; then # help
	crabHelp
	exit 0
elif [[ $1 == ${FILTERS[0]} ]]; then # -d
	getRealDevices
elif [[ $1 == ${FILTERS[1]} ]]; then # -e
	getEmulators
elif [[ $1 == ${FILTERS[2]} ]]; then # -a
	getDeviceInfo
	SELECTEDIDS=("${DEVICEIDS[@]}")
	SELECTEDINFO=("${DEVICEINFO[@]}")
	selection=false
elif [[ $1 == ${FILTERS[3]} ]]; then # -ad
	getRealDevices
	SELECTEDIDS=("${DEVICEIDS[@]}")
	SELECTEDINFO=("${DEVICEINFO[@]}")
	selection=false
elif [[ $1 == ${FILTERS[4]} ]]; then # -ae
	getEmulators
	SELECTEDIDS=("${DEVICEIDS[@]}")
	SELECTEDINFO=("${DEVICEINFO[@]}")
	selection=false
else
	getDeviceInfo
	flag=$1
	textInput=$2
	apkFile=$2
	adbCommand=$@
fi

# Command selection
if [[ $flag == ${COMMANDS[0]} || $flag == "" ]]; then # help
	crabHelp
	exit 0
elif [[ $flag == ${COMMANDS[1]} ]]; then # l
	crabList
	exit 0
elif [[ $flag == ${COMMANDS[2]} ]]; then # s
	selectedCommand="crabScreenshot"
elif [[ $flag == ${COMMANDS[3]} ]]; then # t
	selectedCommand="crabType"
elif [[ $flag == ${COMMANDS[4]} ]]; then # i
	setApkFile $apkFile
	selectedCommand="crabInstall $apkFile"
elif [[ $flag == ${COMMANDS[5]} ]]; then # u
	setApkFile $apkFile
	selectedCommand="crabUninstall $apkFile"
elif [[ $flag == ${COMMANDS[6]} ]]; then # c
	setApkFile $apkFile
	selectedCommand="crabClearData $apkFile"
else
	selectedCommand="runAdb" # If not a crab command, execute as adb command 
fi

crabSelect
executeCommand