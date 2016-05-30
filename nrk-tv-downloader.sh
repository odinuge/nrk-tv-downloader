#!/bin/bash
#
# nrk-tv-downloader
#
# Contributors:
# Odin Ugedal <odin@ugedal.com>
# Henrik Lilleengen <mail@ithenrik.com>
#
shopt -s expand_aliases

DEPS="sed awk gawk printf curl cut grep rev"
DRY_RUN=false

# Curl flags (for making it silent)
readonly CURL_="-s"

# Check the shell
if [ -z "$BASH_VERSION" ]; then
    echo -e "This script needs bash"
    exit 1
fi

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
        readonly SUB_DOWNLOADER=true
    fi
else
    readonly SUB_DOWNLOADER=true
fi

DOWNLOADER_BIN=""
readonly DOWNLOADERS="ffmpeg avconv"

# Check for ffmpeg or avconv
for downloader in $DOWNLOADERS; do
    if hash $downloader 2>/dev/null; then
        readonly DOWNLOADER_BIN=$downloader
    fi
done

if [ -z $DOWNLOADER_BIN ]; then
    echo "This program needs one of these tools: $DOWNLOADERS"
    exit 1
fi

PROBE_BIN=""
readonly PROBES="ffprobe avprobe"
for probe in $PROBES; do
    if hash $probe 2>/dev/null; then
        readonly PROBE_BIN=$probe
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
function sec_to_timestamp()
{
    local sec
    read sec
    echo $sec \
        | awk '{printf("%02d:%02d:%02d",($1/60/60%24),($1/60%60),($1%60))}'
}

# Print USAGE
function usage()
{
    echo -e "nrk-tv-downloader "
    echo -e "\nUsage: \e[01;32m$0 <OPTION>... [PROGRAM_URL(s)]...\e[00m"
    echo -e "\nOptions:"
    echo -e "\t -a download all episodes, in all seasons."
    echo -e "\t -s download all episodes in season"
    echo -e "\t -n skip files that exists"
    echo -e "\t -d dry run - list what is possible to download"
    echo -e "\t -h print this\n"
    echo -e "\nFor updates see <https://github.com/odinuge/nrk-tv-downloader>"
}

# Get the filesize of a file
function getfilesize()
{
    local file=$1
    du -h $file 2>/dev/null | awk '{print $1}'
}

# Download a stream $1, to a local file $2
function download()
{

    local stream=$1
    local localfile=$2

    if [ -z $stream ] ; then
        echo -e  "No stream provided"
        exit 1
    fi

    if [ -z $localfile ] ; then
        echo -e  "No local file provided"
        exit 1
    fi

    if [ -f $localfile ] && ! $DRY_RUN; then
        echo -n " - $localfile exists, overwrite? [y/N]: "
        if $NO_CONFIRM; then
            echo -e "\n - Skipping program, \e[32malready downloaded\e[00m\n"
            return
        fi
        read -n 1 ans
        echo
        if [ -z $ans ]; then
            return
        elif [ $ans = 'y' ]; then
            rm $localfile
        elif [ $ans = 'Y' ]; then
            rm $localfile
        else
            return
        fi
    fi

    # Make sure it is HLS, not flash
    # if it is flash, change url to HLS
    if [[ $stream == *manifest.f4m ]]; then
        #Replacing char(s)
        stream=$(echo $stream | sed -e 's/z/i/g')
        stream=$(echo $stream | sed -e 's/manifest.f4m/master.m3u8/g')
    fi

    # See if the stream is the master playlist
    if [[ "$stream" == *master.m3u8 ]]; then
        stream="$(getBestStream "$stream")"
    fi

    # Start timer
    local t=$(timer)

    # Get the length
    local probe_info
    probe_info=$($PROBE_BIN -v quiet -show_format "$stream" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e " -" $($IS_RADIO && echo Radio || echo Tv) "program is \e[31mnot available\e[0m: streamerror\n"
        return
    fi
    local length_sec=$(echo "$probe_info" \
        | grep duration \
        | cut -c 10-\
        | awk '{print int($1)}')
    local length_stamp=$(echo $length_sec \
        | sec_to_timestamp)
    if $DRY_RUN ; then
        echo -e " - Length: $length_stamp"
        echo -e " -" $($IS_RADIO && echo Radio || echo Tv) "program is \e[01;32mavailable.\e[00m\n"
        return
    fi

    local is_newline=true
    echo -e " - Downloading" $($IS_RADIO && echo radio || echo tv)  "program"

    local downloader_params
    if $IS_RADIO; then
        downloader_params="-codec:a libmp3lame -qscale:a 2 -loglevel info"
    else
        downloader_params="-c copy -bsf:a aac_adtstoasc -stats -loglevel info"
    fi

    while read -d "$(echo -e -n "\r")" line;
    do
        line=$(echo "$line" | tr '\r' '\n')
        if [[ $line =~ Returncode[1-9] ]]; then
            $is_newline || echo && is_newline=true
            echo -e " - \e[31mError\e[0m downloading program.\n"
            rm $localfile 2>/dev/null
            return
        elif [[ "$line" != *bitrate* ]]; then
            $is_newline || echo && is_newline=true
            echo -e " - \e[31m${DOWNLOADER_BIN} error:\e[0m $line"
            continue
        fi
        is_newline=false
        local curr_stamp=$(echo $line\
            | awk -F "=" '/time=/{print}' RS=" ")
        if [[ $DOWNLOADER_BIN == "ffmpeg" ]]; then
            curr_stamp=$(echo $curr_stamp | cut -c 6-13)
        else
            curr_stamp=$(echo $curr_stamp \
                | cut -c 6- \
                | sec_to_timestamp)
        fi
        curr_s=$(echo $curr_stamp \
            | tr ":" " " \
            | awk '{sec = $1*60*60+$2*60+$3;print sec}')
        echo -n -e "\r - Status: $curr_stamp of $length_stamp -"\
            "$((($curr_s*100)/$length_sec))%," \
            "$(getfilesize $localfile)  "
    done < <($DOWNLOADER_BIN -i "$stream" \
        $downloader_params \
        -y $localfile 2>&1 \
        || echo -e "\rReturncode$?\r"
)
    echo -e "\r - Status: $length_stamp of $length_stamp - " \
        "100%, " \
        "$(getfilesize $localfile)"
    echo -e " - Download complete"
    printf ' - Elapsed time: %s\n\n' $(timer $t)
}

# Get json value from v8
function parsejson()
{
    local json=$1
    local tag=$2
    local fnc='
    BEGIN{
        RS="{\"|,\"";
        FS="\":";
    }
    /tag/{
        gsub("\"","",$2);
        print $2;
    }'
    fnc="${fnc/tag/$tag}"
    echo $json | awk "$fnc"
}

# Get an attribute from a html tag
function gethtmlAttr()
{
    local html=$1
    local hint=$2
    local attr=$3
    local fnc='
    /hint/ {
        gsub( ".*attr=\"", "" );
        gsub( "\".*", "" );
        print;
    }'
    fnc=${fnc/hint/$hint}
    fnc=${fnc/attr/$attr}
    echo $html | awk "${fnc}" RS="[<>]"
}

# Get the content of a meta tag
function gethtmlMeta()
{
    local html=$1
    local name=$2
    gethtmlAttr "$html" "meta name=\"$name\"" "content"
}

# Get the content inside a html-Tag
function gethtmlContent()
{
    local html=$1
    local hint=$2
    local fnc='/hint/{
        gsub(".*>","");
        $1=$1;
        print;
        exit;
    }'
    echo $html | awk "${fnc/hint/$hint}" RS="<" ORS=""
}

# Get the stream with the best quality
function getBestStream()
{
    local master=$1
    local master_html=$(curl $CURL_ $master)
    local fnc='/BANDWIDTH/{
        match($0, /BANDWIDTH=([0-9]*)/, bitrate);
        match($0, /(http.*$|index.*$)/,url);
        printf "%s %s\n", bitrate[1], url[1];
    }'
    local new_stream=$(echo "$master_html" \
        | awk "${fnc}" RS="#EXT-X-STREAM-INF" \
        | sort -n -r \
        | awk '{print $2;exit}')

    if [[ "$new_stream" == "index*" ]]; then
        new_stream=$(echo $master | tr 'master.m3u8' "$new_stream")
    fi

    echo "$stream"

}

# Download all the episodes!
function program_all()
{
    local url=$1
    local season=$2
    local html=$(curl $CURL_ $url)
    local program_id=$(gethtmlAttr "$html" "programid")

    local seasons=$(gethtmlAttr "$html" "data-season" "data-season")
    if $season ; then
        seasons=$(gethtmlAttr "$html" "seasonid")
    fi
    series_name=$(gethtmlMeta "$html" "seriesid")

    # Loop through all seasons, or just the selected one
    for season in $seasons ; do
        local url="https://tv.nrk.no/program/Episodes/$series_name/$season"
        if [ $season = "extra" ]; then
            url="https://tv.nrk.no/extramaterial/$series_name"
        fi
        local s_html=$(curl $CURL_ $url)
        local episodes=$(gethtmlAttr "$s_html" "data-episode" "data-episode")
        local season_name=$(gethtmlContent "$s_html" "h1>")

        if [ $season = "extra" ]; then
            season_name="extramaterial"
        fi
        echo -e "Downloading \"$season_name\""
        # loop through all the episodes
        for episode in $episodes ; do
            program "https://tv.nrk.no/serie/$series_name/$episode"
        done

    done
}

# Download program from url $1, to a local file $2 (if provided)
function program()
{
    local url=$1

    local html=$(curl $CURL_ -L $url)

    local program_id=$(gethtmlMeta "$html" "programid")

    # Fetch the info with the v8-API
    local v8=$(curl $CURL_ \
        "http://v8.psapi.nrk.no/mediaelement/${program_id}")

    local streams=$(parsejson "$v8" "url")
    local title=$(parsejson "$v8" "fullTitle")

    local season=$(parsejson "$v8" "relativeOriginUrl" \
        | awk '/sesong/{printf(" %s", $0)}' RS='/')

    title="$title$season"
    echo "Downloading \"$title\" "

    # TODO FIXME Fix the name of the file
    local localfile="$title"
    localfile="${localfile// /_}"
    localfile="${localfile//&#230;/ae}"
    localfile="${localfile//ø/o}"
    localfile="${localfile//å/aa}"
    localfile="${localfile//:/-}"

    # Check if program has a valid subtitle
    local subtitle=$(parsejson "$v8" "hasSubtitles")

    if [ $subtitle == "true" ] && $SUB_DOWNLOADER && ! $DRY_RUN ; then
        echo " - Downloading subtitle"

        curl $CURL_ "http://v8.psapi.nrk.no/programs/$program_id/subtitles/tt" \
            | tt-to-subrip > "$localfile.srt"
    elif $SUB_DOWNLOADER && ! $IS_RADIO; then
        if [ $subtitle == "true" ] ; then
            echo " - Subtitle is available"
        else
            echo " - Subtitle is not available"
        fi
    fi

    local parts
    if [[ -z $streams ]]; then
        # Only one part
        streams=$(gethtmlAttr "$html" "div id=\"playerelement\"" "data-media")
        # If stream is unable to be found,
        # make the user use "stream"
        if [[ ! $streams == *"akamaihd.net"* ]]; then
            message=$(parsejson "$v8" "messageType" \
                | awk '{gsub("[A-Z]"," &");print tolower($0)}')
            echo -e " -" $($IS_RADIO && echo Radio || echo Tv) "program is \e[31mnot available\e[0m:$message\n"
            return
        fi
        parts=false
    else
        # Several parts
        parts=true
    fi
    # Download the stream(s)
    for stream in $streams ; do

        if $parts ; then
            local part=$((part+1))
            local more="-Part_$part"
            localfile="${localfile// /_}$more"
        fi

        if $IS_RADIO; then
            localfile="${localfile}.mp3"
        elif [[ $localfile != *.mp4 && $localfile != *.mkv ]]; then
            localfile="${localfile}.mp4"
        fi

        # Download the stream
        download $stream $localfile
    done

}
DL_ALL=false
IS_RADIO=false
SEASON=false
NO_CONFIRM=false
# Main part of script
OPTIND=1

while getopts "hasnud" opt; do
    case "$opt" in
        h)
            usage
            exit 0
            ;;
        n)
            NO_CONFIRM=true
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
        *radio.nrk.no*)
            IS_RADIO=true
            $DL_ALL && program_all $var $SEASON || program $var
            ;;
        *tv.nrk.no*)
            $DL_ALL && program_all $var $SEASON || program $var
            ;;
        *)
            usage
            ;;
    esac
done

# The End!
