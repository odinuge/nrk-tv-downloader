#!/bin/bash
#
# nrk-tv-downloader
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

shopt -s expand_aliases

VERSION="0.9.91"
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
    hash $dep 2> /dev/null
    if [ $? -ne 0 ]; then
        echo -e "Error: Required program could not be found: $dep"
        exit 1
    fi
done

SUB_DOWNLOADER=false

# Check for sub-downloader
hash "tt-to-subrip" 2> /dev/null
if [ $? -ne 0 ]; then
    DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
    if [ -f "$DIR/tt-to-subrip/tt-to-subrip.awk" ]; then
        alias "tt-to-subrip"="$DIR/tt-to-subrip/tt-to-subrip.awk"
        SUB_DOWNLOADER=true
    fi
else
    SUB_DOWNLOADER=true
fi

DOWNLOADER_BIN=""
DOWNLOADERS="ffmpeg avconv"

# Check for ffmpeg or avconv
for downloader in $DOWNLOADERS; do
    if hash $downloader 2>/dev/null; then
        DOWNLOADER_BIN=$downloader
    fi
done

PROBE_BIN=""
PROBES="ffprobe avprobe"
for probe in $PROBES; do
    if hash $probe 2>/dev/null; then
        PROBE_BIN=$probe
    fi

done

if [ -z "$PROBE_BIN" ]; then
    echo "This program needs one of these probe tools: $PROBES"
    exit 1
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
    echo -e "nrk-tv-downloader v$VERSION"
    echo -e "\nUsage: \e[01;32m$0 <OPTION>... [PROGRAM_URL(s)]...\e[00m"
    echo -e "\nOptions:"
    echo -e "\t -a download all episodes, in all seasons."
    echo -e "\t -s download all episodes in season"
    echo -e "\t -n skip files that exists"
    echo -e "\t -d dry run - list what is possible to download"
    echo -e "\t -v print version"
    echo -e "\t -h print this\n"
    echo -e "\nFor updates see <https://github.com/odinuge/nrk-tv-downloader>"
}

# Get the filesize of a file
function getfilesize()
{
    local FILE=$1
    du -h $FILE 2>/dev/null | awk '{print $1}'
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

    if [ -f $LOCAL_FILE ] && ! $DRY_RUN; then
        echo -n " - $LOCAL_FILE exists, overwrite? [y/N]: "
        if $NO_CONFIRM; then
            echo -e "\n - Skipping program, \e[32malready downloaded\e[00m\n"
            return
        fi
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
        STREAM=$(getBestStream $STREAM)

    fi

    # Start timer
    t=$(timer)

    playlist=$(curl $CURL_ ${STREAM})

    for line in $playlist ; do
        if [[ "$line" == *http* ]]; then
            total=$((total+1))
        fi
    done

    # Get the length
    local probe_info
    probe_info=$($PROBE_BIN -v quiet -show_format "$STREAM")
    if [ $? -ne 0 ]; then
        echo -e " - Program is \e[31mnot available\e[0m: streamerror\n"
        return
    fi
    LENGTH_S=$(echo $probe_info | grep duration | cut -c 10-|awk '{print int($1)}')
    LENGTH_STAMP=$(echo $LENGTH_S | awk '{printf("%02d:%02d:%02d",($1/60/60%24),($1/60%60),($1%60))}')
    if $DRY_RUN ; then
        echo -e " - Length: $LENGTH_STAMP"
        echo -e " - Program is \e[01;32mavailable.\e[00m\n"
        return
    fi
    local IS_NEWLINE=true
    #STREAM="nnn"
    echo -e " - Downloading program"
    while read -d "$(echo -e -n "\r")" line;
    do
        line=$(echo "$line" | tr '\r' '\n')
        if [[ $line =~ Returncode[1-9] ]]; then
            $IS_NEWLINE || echo && IS_NEWLINE=true
            echo -e " - \e[31mError\e[0m downloading program.\n"
            rm $LOCAL_FILE 2>/dev/null
            return
        elif [[ "$line" != *bitrate* ]]; then
            $IS_NEWLINE || echo && IS_NEWLINE=true
            echo -e " - \e[31m${DOWNLOADER_BIN} error:\e[0m $line"
            continue
        fi
        IS_NEWLINE=false
        curr_stamp=$(echo $line| awk -F "=" '{print $6}' | rev | cut -c 12- | rev)
        curr_s=$(echo $curr_stamp | tr ":" " " | awk '{sec = $1*60*60+$2*60+$3;print sec}')
        echo -n -e "\r - Status: $curr_stamp of $LENGTH_STAMP -"\
            "$((($curr_s*100)/$LENGTH_S))%," \
            "$(getfilesize $LOCAL_FILE)  "
    done < <($DOWNLOADER_BIN -i "$STREAM" -c copy -bsf:a aac_adtstoasc -stats -loglevel 16 -y $LOCAL_FILE 2>&1 || echo -e "\rReturncode$?\r")
    echo -e "\r - Status: $LENGTH_STAMP of $LENGTH_STAMP - " \
        "100%, " \
        "$(getfilesize $LOCAL_FILE)"
    echo -e " - Download complete"
    printf ' - Elapsed time: %s\n\n' $(timer $t)
}

# Get json value from V8
function parseJSON()
{
    local JSON=$1
    local TAG=$2
    local FNC='
    BEGIN{
        RS="{\"|,\"";
        FS="\":";
    }
    /TAG/{
        gsub("\"","",$2);
        print $2;
    }'
    FNC="${FNC/TAG/$TAG}"
    echo $JSON | awk "$FNC"
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
    echo $HTML | awk "${FNC}" RS="[<>]"
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
    FNC='/HINT/{
        gsub(".*>","");
        $1=$1;
        print
    }'
    echo $HTML | awk ${FNC/HINT/$HINT} RS="<" 2>/dev/null
}

# Get the stream with the best quality
function getBestStream()
{
    local MASTER_URL=$1
    local MASTER=$(curl $CURL_ $MASTER_URL)
    FNC='/BANDWIDTH/{
        match($0, /BANDWIDTH=([0-9]*)/, bitrate);
        match($0, /(http.*$)/,url);
        printf "%s %s\n", bitrate[1], url[1];
    }'
    echo $MASTER | awk "${FNC}" RS="#EXT-X-STREAM-INF" |
        sort -n -r | awk '{print $2;exit}'
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
        SEASONS=$(getHTMLAttr "$HTML" "seasonid")
    fi
    SERIES_NAME=$(getHTMLMeta "$HTML" "seriesid")

    # Loop through all seasons, or just the selected one
    for season in $SEASONS ; do
        URL="https://tv.nrk.no/program/Episodes/$SERIES_NAME/$season"
        if [ $season = "extra" ]; then
            URL="https://tv.nrk.no/extramaterial/$SERIES_NAME"
        fi
        S_HTML=$(curl $CURL_ $URL)
        EPISODES=$(getHTMLAttr "$S_HTML" "data-episode" "data-episode")
        SEASON_NAME=$(getHTMLContent "$S_HTML" "h1")
        echo -n "Downloading $SEASON_NAME"

        # loop through all the episodes
        for episode in $EPISODES ; do
            program "https://tv.nrk.no/serie/$SERIES_NAME/$episode"
        done

    done
}

# Download program from url $1, to a local file $2 (if provided)
function program()
{
    local URL=$1

    HTML=$(curl $CURL_ -L $URL)

    # See if program has more than one part
    STREAMS=$(getHTMLAttr "$HTML" "data-method=\"playStream\"" "data-argument")

    Program_ID=$(getHTMLMeta "$HTML" "programid")

    # Fetch the info with the V8-API
    V8=$(curl $CURL_ "http://v8.psapi.nrk.no/mediaelement/${Program_ID}")
    TITLE=$(parseJSON "$V8" "fullTitle")

    SEASON=$(parseJSON "$V8" "relativeOriginUrl" | awk '/sesong/{printf(" %s", $0)}' RS='/')

    TITLE="$TITLE$SEASON"
    echo "Downloading \"$TITLE\" "

    # TODO FIXME Fix the name of the file
    FILE="$TITLE"
    FILE="${FILE// /_}"
    FILE="${FILE//&#230;/ae}"
    FILE="${FILE//ø/o}"
    FILE="${FILE//å/aa}"
    FILE="${FILE//:/-}"

    # Check if program has a valid subtitle
    HAS_SUB=$(parseJSON "$V8" "hasSubtitles")

    if [ $HAS_SUB == "true" ] && $SUB_DOWNLOADER && ! $DRY_RUN ; then
        echo " - Downloading subtitle"

        curl $CURL_ "http://v8.psapi.nrk.no/programs/$Program_ID/subtitles/tt" | \
            tt-to-subrip > "$FILE.srt"
    elif $SUB_DOWNLOADER ; then
        if [ $HAS_SUB == "True" ] ; then
            echo " - Subtitle is available"
        else
            echo " - Subtitle is not available"
        fi
    fi

    if [[ -z $STREAMS ]]; then
        # Only one part
        STREAMS=$(getHTMLAttr "$HTML" "div id=\"playerelement\"" "data-media")
        # If stream is unable to be found,
        # make the user use "stream"
        if [[ ! $STREAMS == *"akamaihd.net"* ]]; then
            message=$(parseJSON "$V8" "messageType" | \
                awk '{gsub("[A-Z]"," &");print tolower($0)}')
            echo -e " - Program is \e[31mnot available\e[0m:$message\n"
            return
        fi
        PARTS=false
    else
        # Several parts
        PARTS=true
    fi
    # Download the stream(s)
    for STREAM in $STREAMS ; do

        if $PARTS ; then
            part=$((part+1))
            MORE="-Part_$part"
            FILE="${FILE// /_}$MORE"
        fi


        if [[ $FILE != *.mp4 && $FILE != *.mkv ]]; then
            FILE="${FILE}.mp4"
        fi

        # Download the stream
        download $STREAM $FILE
    done

}
DL_ALL=false
SEASON=false
NO_CONFIRM=false
# Main part of script
OPTIND=1

while getopts "hasndv" opt; do
    case "$opt" in
        h)
            usage
            exit 0
            ;;
        n)
            NO_CONFIRM=true
            ;;
        v)
            echo -e "nrk-tv-downloader v$VERSION"
            exit 0
            ;;
        d)  DRY_RUN=true
            ;;
        a)  DL_ALL=true
            ;;
        s)  DL_ALL=true
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
                program_all $var
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
