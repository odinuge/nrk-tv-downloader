#!/bin/bash
#
# NRK-TV-Dowloader
#
#             DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#
#                    Version 2, December 2004
#
#
#
# Copyright (C) 2013 Odin Ugedal <odinuge[at]gmail[dot]com>
#
# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#   0. You just DO WHAT THE FUCK YOU WANT TO.
#

VERSION="0.4.7"
DEPS="sed awk printf curl"
DRY_RUN=false

# Check the shell
if [ -z "$BASH_VERSION" ]; then
	echo -e "This script needs bash"
	exit 1
fi

# Checking dependencies
for dep in $DEPS; do
    which $dep > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "Error: Required program could not be found: $dep"
        exit 1
    fi
done

# Function to measure time
function timer()
{
	if [[ $# -eq 0 ]]; then
		echo $(date '+%s')
	else
		local  stime=$1
		etime=$(date '+%s')

		if [[ -z "$stime" ]]; then
			stime=$etime;
		fi

	        dt=$((etime - stime))
	        ds=$((dt % 60))
	        dm=$(((dt / 60) % 60))
	        dh=$((dt / 3600))
	        printf '%d:%02d:%02d' $dh $dm $ds
	fi
}

# Print USAGE
function usage() {
	echo -e "NRK-TV-Downloader v$VERSION"
	echo -e "Odin Ugedal - odinuge[at]gmail[dot]com"
	echo -e "This script has nothing to do with NRK!"
	echo -e "It is only meant for private use, and can break at any time."
	echo -e "\nUsage: \e[01;32m$0 COMMAND [PARAMETERS]...\e[00m"
	echo -e "\nCommands:"
	echo -e "\t stream [HLS_STREAM] [LOCAL_FILE]"
	echo -e "\t program [PROGRAM_URL] <LOCAL_FILE>"
	echo -e "\t help"
	echo -e "\nFor updates see <https://github.com/odinuge/NRK-TV-Downloader>"
	exit 1
}

# Download a stream $1, to a local file $2
function download(){

	local STREAM=$1
	local LOCAL_FILE=$2

	if $DRY_RUN ; then
		echo "DOWNLOADING: $LOCAL_FILE, FROM: $STREAM"
		return
	fi


	if [ -z $STREAM ] ; then
		echo -e  "No stream provided"
		exit 1
	fi

	if [ -z $LOCAL_FILE ] ; then
		echo -e  "No local file provided"
		exit 1
	fi

	if [ -f $LOCAL_FILE ]; then
		echo -e "$LOCAL_FILE exists, overwrite? [Y/n]:"
		read ans

		if [ $ans = 'y' ]; then
			rm $LOCAL_FILE
		elif [ $ans = 'Y' ]; then
			rm $LOCAL_FILE
		else
			exit 1
		fi
	fi

	# Make sure it is HLS, not flash
	# if it is flash, change url to HLS
	if [[ $STREAM == *manifest.f4m ]]; then
		#Replacing char(s)
		STREAM=`echo $STREAM | sed -e 's/z/i/g'`
		STREAM=`echo $STREAM | sed -e 's/manifest.f4m/master.m3u8/g'`
	fi

	# See if the stream is the master playlist
	if [[ "$STREAM" == *master.m3u8 ]]; then
		STREAM=`echo $STREAM | sed -e "s/master.m3u8/index_4_av.m3u8/g"`

	fi

	echo -e "\e[01;32mDownloading stream to \"$LOCAL_FILE\"\e[00m"

	t=$(timer)

	playlist=`curl ${STREAM}`

	for line in $playlist ; do
		if [[ "$line" == *http* ]]; then
			total=$((total+1))
		fi
	done

	# Download each part into one file
	for line in $playlist ; do
		if [[ "$line" == *http* ]]; then
			current=$((current+1))
			echo -e "\e[01;32mDownloading part ${current} of ${total}\e[00m"
			curl $line >> $LOCAL_FILE
		fi
	done
	echo -e "\"$LOCAL_FILE\" downloaded..."
	printf 'Elapsed time: %s\n' $(timer $t)

}

# Download program from url $1, to a local file $2 (if provided)
function program(){
	local URL=$1
	local LOCAL_FILE=$2

	if [[ $URL != *tv.nrk.no* ]]; then
		echo -e  "Invalid url."
		exit 1
	fi

	echo -e "\e[01;32mFetching stream url\e[00m"

	HTML=`curl $URL`

	# See if program has more than one part
	STREAMS=`echo $HTML | awk '
    	/a href="#" class="p-link js-player"/ {
		gsub( ".*data-argument=\"", "" );
       		gsub( "\".*", "" );
		print;
	}
	' RS="[<>]"`

	if [[ -z $STREAMS ]]; then
		# Only one part

		STREAMS=`echo $HTML | awk '
    		/div id="playerelement"/ {
			gsub( ".*data-media=\"", "" );
  		     	gsub( "\".*", "" );
     	  		print;
    		}
		' RS="[<>]"`

		# If stream is unable to be found,
		# make the user use "stream"
		if [ -z $STREAMS ]; then
			echo -e "Unable to find stream..."
			echo -e "If url is valid; check for updates at <https://github.com/odinuge/NRK-TV-Downloader>,"
			echo -e "or use:\e[01;32m $0 stream [HLS_STREAM] [LOCAL_FILE]\e[00m instead."
			exit 1
		fi
		PARTS=false
	else
		# Several parts
		PARTS=true
	fi
	# Download the stream(s)
	for STREAM in $STREAMS ; do
		if [ -z $LOCAL_FILE ]; then
			FILE=`echo $HTML | awk '
    			/meta name="title"/ {
				gsub( ".*content=\"", "" );
  	     			gsub( "\".*", "" );
       				print;
    			}' RS="[<>]"`
		else
			FILE=$LOCAL_FILE
		fi

		if $PARTS ; then
			part=$((part+1))
			MORE="-Part_$part"
			FILE="${FILE// /_}$MORE"
		else
			FILE="${FILE// /_}"
		fi

		FILE="${FILE//&#230;/æ}"
		FILE="${FILE//&#216;/ø}"
		FILE="${FILE//&#229;/å}"
		FILE="${FILE//:/-}"
		if [[ $FILE != *.mp4 ]]; then
			FILE="${FILE}.mp4"
		fi
		download $STREAM $FILE
	done

}

COMMAND=$1
# Main part of script
case $COMMAND in
	stream)
		download $2 $3
	;;
	program)
		program $2 $3
	;;
	*)
		usage
	;;
esac

# The End!
