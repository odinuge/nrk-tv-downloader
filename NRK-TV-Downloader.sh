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

VERSION="0.9.0"
DEPS="sed awk printf curl cut grep rev"
DRY_RUN=false

# Check the shell
if [ -z "$BASH_VERSION" ]; then
    echo -e "This script needs bash"
    exit 1
fi

# Curl flags (for making it silent)
CURL_="-s"

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
function usage()
{
    echo -e "NRK-TV-Downloader v$VERSION"
    echo -e "\nUsage: \e[01;32m$0 <OPTION>... [PROGRAM_URL(s)]...\e[00m"
    echo -e "\nOptions:"
    echo -e "\t -a download all episodes, in all seasons."
    echo -e "\t -s download all episodes in season"
    echo -e "\t -v print version"
    echo -e "\t -h print this\n"
    echo -e "\nFor updates see <https://github.com/odinuge/NRK-TV-Downloader>"
}

# Get the filesize of a file
function getfilesize()
{
    local FILE=$1
    du -h $FILE | awk '{print $1}'
}

# Download a stream $1, to a local file $2
function download()
{

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
        echo -n " - $LOCAL_FILE exists, overwrite? [y/N]: "
        read -n 1 ans
        echo
        if [ -z $ans ]; then
            return
        elif [ $ans = 'y' ]; then
            rm $LOCAL_FILE
        elif [ $ans = 'Y' ]; then
            rm $LOCAL_FILE
        else
            return
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

    t=$(timer)

    playlist=$(curl $CURL_ ${STREAM})

    for line in $playlist ; do
        if [[ "$line" == *http* ]]; then
            total=$((total+1))
        fi
    done

    if [[ "$DOWNLOADER_BIN" == "curl" ]]; then
        # Download each part into one file
        # Bad!!
        for line in $playlist ; do
            if [[ "$line" == *http* ]]; then
                current=$((current+1))
                echo -e "\e[01;32mDownloading part ${current} of ${total}\e[00m"
                curl $CURL_ $line >> $LOCAL_FILE
            fi
        done
        echo -e "\"$LOCAL_FILE\" downloaded..."
    else
        # Get the length
        TMP="/tmp/${LOCAL_FILE}.output"
        LENGTH_S=$(ffprobe -v quiet -show_format "$STREAM" | grep duration | cut -c 10-|awk '{print int($1)}')
        LENGTH_STAMP=$(echo $LENGTH_S | awk '{printf("%02d:%02d:%02d",($1/60/60%24),($1/60%60),($1%60))}')
        $DOWNLOADER_BIN -i $STREAM -c copy -loglevel 0 -stats -bsf:a aac_adtstoasc $LOCAL_FILE \
            -y -loglevel 0 -stats 2>"$TMP"&
        PID_=$!
        while sleep 1;
        do
            line=$(cat "$TMP" | tr '\r' '\n' | tail -1)
            curr_stamp=$(echo $line| awk -F "=" '{print $6}' | rev | cut -c 12- | rev)
            curr_s=$(echo $curr_stamp | tr ":" " " | awk '{sec = $1*60*60+$2*60+$3;print sec}')
            echo -n -e " - Status: $curr_stamp of $LENGTH_STAMP -"\
                "$((($curr_s*100)/$LENGTH_S))%," \
                "$(getfilesize $LOCAL_FILE)  \r"
            kill -0 $PID_ 2>/dev/null || break;
        done
        echo -n -e " - Status: $LENGTH_STAMP of $LENGTH_STAMP - " \
            "100%, " \
            "$(getfilesize $LOCAL_FILE)"
        echo -e "\n - Download complete"
        rm "$TMP"
        printf ' - Elapsed time: %s\n\n' $(timer $t)
    fi
}
# Get json value from V7
function parseJSON()
{
    local JSON=$1
    local TAG=$2
    REG='"TAG":.*?[^\\]",'
    echo $JSON | grep -Po ${REG/TAG/$TAG} | cut -c $((${#TAG}+5))- | rev | cut -c 3- | rev

}

# Get an attribute from a html tag
function getHTMLAttr()
{
    local HTML=$1
    local LINE_HINT=$2
    local ATTR=$3
    local FNC='
    /HINT/ {
    gsub( ".*ATTR=\"", "" );
    gsub( "\".*", "" );
    print;
}'
FNC=${FNC/HINT/$LINE_HINT}
FNC=${FNC/ATTR/$ATTR}
echo $HTML | awk "${FNC}"  RS="[<>]"

}

# Get the content of a meta tag
function getHTMLMeta()
{
    local HTML=$1
    local NAME=$2
    getHTMLAttr "$HTML" "meta name=\"$NAME\"" "content"
}

# Get the content inside a HTML-Tag
function getHTMLContent()
{
    local HTML=$1
    local HINT=$2
    FNC='/HINT/{gsub(".*>","");$1=$1;print}'
    echo $HTML | awk ${FNC/HINT/$HINT} RS="<"
}
# Download all the episodes!
function program_all()
{
    local URL=$1
    local SEASON=$2
    HTML=$(curl $CURL_ $URL)
    Program_ID=$(getHTMLAttr "$HTML" "programid")
    SEASONS=$(getHTMLAttr "$HTML" "data-season" "data-season")
    if $SEASON ; then
        SEASONS=$(echo $SEASONS | awk '{ print $1 }')
    fi

    SERIES_NAME=$(getHTMLMeta "$HTML" "seriesid")
    for season in $SEASONS ; do
        URL="http://tv.nrk.no/program/Episodes/$SERIES_NAME/$season/placeholder"
        if [ $season = "extra" ]; then
            URL="http://tv.nrk.no/extramaterial/$SERIES_NAME"
        fi
        S_HTML=$(curl $CURL_ $URL)
        EPISODES=$(getHTMLAttr "$S_HTML" "data-episode" "data-episode")
        SEASON_NAME=$(getHTMLContent "$S_HTML" "h1")
        echo "Downloading $SEASON_NAME"

        # loop through all the episodes
        for episode in $EPISODES ; do
            program "http://tv.nrk.no/serie/$SERIES_NAME/$episode"
        done

    done
}

# Download program from url $1, to a local file $2 (if provided)
function program()
{
    local URL=$1
    local LOCAL_FILE=$2

    # TODO Check if it is downloadable, and why...
    HTML=$(curl $CURL_ -L $URL)

    # See if program has more than one part
    STREAMS=$(getHTMLAttr "$HTML" "data-method=\"playStream\"" "data-argument")

    Program_ID=$(getHTMLMeta "$HTML" "programid")

    V7=$(curl $CURL_ "http://v7.psapi.nrk.no/mediaelement/${Program_ID}")
    TITLE=$(parseJSON "$V7" "fullTitle")

    echo "Downloading \"$TITLE\" "

    if [[ -z $STREAMS ]]; then
        # Only one part
        STREAMS=$(getHTMLAttr "$HTML" "div id=\"playerelement\"" "data-media")
        # If stream is unable to be found,
        # make the user use "stream"
        if [[ ! $STREAMS == *"akamaihd.net"* ]]; then
            echo -e " - Unable to download this program...\n"
            return
        fi
        PARTS=false
    else
        # Several parts
        PARTS=true
    fi
    # Download the stream(s)
    for STREAM in $STREAMS ; do
        if [ -z $LOCAL_FILE ]; then
            FILE=$TITLE
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
DL_ALL=false
SEASON=false
# Main part of script
OPTIND=1

while getopts "hasv" opt; do
    case "$opt" in
        h)
            usage
            exit 0
            ;;
        v)
            echo -e "NRK-TV-Downloader v$VERSION"
            exit 0
            ;;
        a)  DL_ALL=true
            ;;
        f)  DL_ALL=true
            SEASON=true
            ;;
    esac
done

shift $((OPTIND-1))

[ "$1" = "--" ] && shift
if [ -z $1 ]
then
    usage
    exit 1
fi

for var in "$@"
do
    case $var in

        *akamaihd.net*)
            download $var
            ;;
        *tv.nrk.no*)
            if $DL_ALL ; then
                program_all $var $SEASON
            else
                program $var
            fi
            ;;
        *)
            usage
            ;;
    esac
done

# The End!
