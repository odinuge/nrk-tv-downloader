#!/bin/bash
#
# NRK-TV-Dowloader
#
# The MIT License (MIT)
#
# Copyright (c) 2013 Odin Ugedal <odin@ugedal.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Contributors:
# Henrik Lilleengen <mail@ithenrik.com>
#

VERSION="0.5.0"
DEPS="sed awk printf curl"
DRY_RUN=false

# Check the shell
if [ -z "$BASH_VERSION" ]; then
	echo -e "This script needs bash"
	exit 1
fi

# Checking dependencies
for dep in $DEPS; do
    hash $dep > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "Error: Required program could not be found: $dep"
        exit 1
    fi
done

DOWNLOADER_BIN="curl"
DOWNLOADERS="ffmpeg avconv"

# Check for ffmpeg or avconv
for downloader in $DOWNLOADERS; do
    if hash $downloader 2>/dev/null; then
        DOWNLOADER_BIN=$downloader
    fi
done

# Check if fallback is used
if [[ $downloader == "curl" ]]; then
    echo "Ffmpeg or avconv not found, using fallback (curl)."
fi

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
	echo -e "\nUsage: \e[01;32m$0 COMMAND [PARAMETERS]...\e[00m"
	echo -e "\nCommands:"
	echo -e "\t [HLS_STREAM] [LOCAL_FILE]"
	echo -e "\t [PROGRAM_URL] <LOCAL_FILE>"
	echo -e "\t help"
	echo -e "\nFor updates see <https://github.com/odinuge/NRK-TV-Downloader>"
	exit 1
}

# Download a stream $1, to a local file $2
function download(){

	local STREAM=$1
	local LOCAL_FILE=$2


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
		STREAM=$(echo $STREAM | sed -e 's/z/i/g')
		STREAM=$(echo $STREAM | sed -e 's/manifest.f4m/master.m3u8/g')
	fi

	# See if the stream is the master playlist
	if [[ "$STREAM" == *master.m3u8 ]]; then
		STREAM=$(echo $STREAM | sed -e "s/master.m3u8/index_4_av.m3u8/g")

	fi

	if $DRY_RUN ; then
		echo "DOWNLOADING: $LOCAL_FILE, FROM: $STREAM, with $DOWNLOADER_BIN"
		return
	fi

	echo -e "\e[01;32mDownloading stream to \"$LOCAL_FILE\"\e[00m"

	t=$(timer)

	playlist=$(curl ${STREAM})

	for line in $playlist ; do
		if [[ "$line" == *http* ]]; then
			total=$((total+1))
		fi
	done

    if [[ "$DOWNLOADER_BIN" == "curl" ]]; then
        # Download each part into one file
        for line in $playlist ; do
            if [[ "$line" == *http* ]]; then
                current=$((current+1))
                echo -e "\e[01;32mDownloading part ${current} of ${total}\e[00m"
                curl $line >> $LOCAL_FILE
            fi
        done
        echo -e "\"$LOCAL_FILE\" downloaded..."
    else
        echo "Downloading via $DOWNLOADER_BIN"
        $DOWNLOADER_BIN -i $STREAM -c copy -bsf:a aac_adtstoasc $LOCAL_FILE
        printf 'Elapsed time: %s\n' $(timer $t)
    fi
}

# Download program from url $1, to a local file $2 (if provided)
function program(){
	local URL=$1
	local LOCAL_FILE=$2

	echo -e "\e[01;32mFetching stream url\e[00m"

	HTML=$(curl $URL)

	# See if program has more than one part
	STREAMS=$(echo $HTML | awk '
		/data-method="playStream"/ {
		    gsub( ".*data-argument=\"", "" );
       		gsub( "\".*", "" );
		    print;
	}
	' RS="[<>]")

	if [[ -z $STREAMS ]]; then
		# Only one part

		STREAMS=$(echo $HTML | awk '
    		/div id="playerelement"/ {
			gsub( ".*data-media=\"", "" );
  		     	gsub( "\".*", "" );
     	  		print;
    		}
		' RS="[<>]")

		# If stream is unable to be found,
		# make the user use "stream"
		if [ -z $STREAMS ]; then
			echo -e "Unable to find stream..."
			echo -e "If url is valid; check for updates at <https://github.com/odinuge/NRK-TV-Downloader>,"
			echo -e "or use:\e[01;32m $0 [HLS_STREAM] [LOCAL_FILE]\e[00m instead."
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
			FILE=$(echo $HTML | awk '
    			/meta name="title"/ {
				gsub( ".*content=\"", "" );
  	     			gsub( "\".*", "" );
       				print;
				}' RS="[<>]")
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
		if [[ $FILE != *.mp4 && $FILE != *.mkv ]]; then
			FILE="${FILE}.mp4"
		fi
		download $STREAM $FILE
	done

}

# Main part of script
case $1 in
	*akamaihd.net*)
		download $1 $2
	;;
	*tv.nrk.no*)
		program $1 $2
	;;
	*)
		usage
	;;
esac

# The End!
