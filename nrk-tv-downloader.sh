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
    hash "$dep" 2> /dev/null
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
        alias "tt-to-subrip=$DIR/tt-to-subrip/tt-to-subrip.awk"
        readonly SUB_DOWNLOADER=true
    fi
else
    readonly SUB_DOWNLOADER=true
fi

DOWNLOADER_BIN=""
readonly DOWNLOADERS="ffmpeg avconv"

# Check for ffmpeg or avconv
for downloader in $DOWNLOADERS; do
    if hash "$downloader" 2>/dev/null; then
        readonly DOWNLOADER_BIN=$downloader
        break
    fi
done

if [ -z "$DOWNLOADER_BIN" ]; then
    echo "This program needs one of these tools: $DOWNLOADERS"
    exit 1
fi

PROBE_BIN=""
readonly PROBES="ffprobe avprobe"
for probe in $PROBES; do
    if hash "$probe" 2>/dev/null; then
        readonly PROBE_BIN=$probe
        break
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
        date '+%s'
    else
        local stime=$1
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

# Print in red
function print_red()
{
    # TODO FIXME Check whether term supports colors
    local input="$1"
    printf "\e[31m%s\e[0m" "$input"
}

# Print in green
function print_green()
{
    local input="$1"
    printf "\e[01;32m%s\e[00m" "$input"
}

function sec_to_timestamp()
{
    local sec
    read -r sec
    echo "$sec" \
        | gawk '{printf("%02d:%02d:%02d",($1/60/60%24),($1/60%60),($1%60))}'
}

# Print USAGE
function usage()
{
    echo -e "nrk-tv-downloader "
    echo -e "\nUsage: $(print_green "$0 <OPTION>... [PROGRAM_URL(s)]...")"
    echo -e "\nOptions:"
    echo -e "\t -a download all episodes, in all seasons."
    echo -e "\t -s download all episodes in season"
    echo -e "\t -n skip files that exists"
    echo -e "\t -d dry run - list what is possible to download"
    echo -e "\t -h print this\n"
    echo -e "\nFor updates see <https://github.com/odinuge/nrk-tv-downloader>"
}

# Get the filesize of a file
function get_filesize()
{
    local file=$1
    du -h "$file" 2>/dev/null | gawk '{print $1}'
}

# Return tv or radio
function is_tv_or_radio()
{
    if $IS_RADIO; then
        echo "Radio"
    else
        echo "Tv"
    fi
}

# Download a stream $1, to a local file $2
function download()
{

    local stream=$1
    local localfile=$2

    if [ -z "$stream" ] ; then
        echo -e  "No stream provided"
        exit 1
    fi

    if [ -z "$localfile" ] ; then
        echo -e  "No local file provided"
        exit 1
    fi

    if [ -f "$localfile" ] && ! $DRY_RUN; then
        echo -n " - $localfile exists, overwrite? [y/N]: "
        if $NO_CONFIRM; then
            printf "\n - Skipping program, %s\n" \
                "$(print_green "already downloaded")"
            return
        fi
        read -r -n 1 ans
        echo
        if [ -z "$ans" ]; then
            return
        elif [ "$ans" = 'y' ]; then
            rm "$localfile"
        elif [ "$ans" = 'Y' ]; then
            rm "$localfile"
        else
            return
        fi
    fi

    # Make sure it is HLS, not flash
    # if it is flash, change url to HLS
    stream=${stream//z/i}
    stream=${stream//manifest.f4m/master.m3u8}

    # See if the stream is the master playlist
    if [[ "$stream" == *master.m3u8 ]]; then
        stream="$(getBestStream "$stream")"
    fi

    # Start timer
    local t
    t=$(timer)

    # Get the length
    local probe_info
    probe_info=$($PROBE_BIN -v quiet -show_format "$stream" 2>/dev/null)
    if [ $? -ne 0 ]; then
        printf " - %s program is %s: %s\n\n" \
            "$(is_tv_or_radio)" \
            "$(print_red "not available")" \
            "stremerror"
        return
    fi
    local length_sec=$(echo "$probe_info" \
        | grep duration \
        | cut -c 10-\
        | gawk '{print int($1)}')
    local length_stamp=$(echo "$length_sec" \
        | sec_to_timestamp)
    if $DRY_RUN ; then
        echo -e " - Length: $length_stamp"
        printf " - %s program is %s\n" \
            "$(is_tv_or_radio)" \
            "$(print_green "available")"
        return
    fi

    local is_newline=true
    printf " - Downloading %s program\n" "$(is_tv_or_radio)"

    local downloader_params
    if $IS_RADIO; then
        downloader_params="-codec:a libmp3lame -qscale:a 2 -loglevel info"
    else
        downloader_params="-c copy -bsf:a aac_adtstoasc -stats -loglevel info"
    fi

    while read -r -d "$(echo -e -n "\r")" line;
    do
        line=$(echo "$line" | tr '\r' '\n')
        if [[ $line =~ Returncode[1-9] ]]; then
            $is_newline || echo && is_newline=true
            printf " - %s downloading program.\n\n" \
                "$(print_red "Error")"
            rm "$localfile" 2>/dev/null
            return
        elif [[ "$line" != *bitrate* ]]; then
            $is_newline || echo && is_newline=true
            printf " - %s %s" \
                "$(print_red "${DOWNLOADER_BIN} error")" \
                "$line"

            continue
        fi
        is_newline=false
        local curr_stamp="$(echo "$line"\
            | gawk -F "=" '/time=/{print}' RS=" ")"
        if [[ $DOWNLOADER_BIN == "ffmpeg" ]]; then
            curr_stamp=$(echo "$curr_stamp" | cut -c 6-13)
        else
            curr_stamp=$(echo "$curr_stamp" \
                | cut -c 6- \
                | sec_to_timestamp)
        fi
        curr_s=$(echo "$curr_stamp" \
            | tr ":" " " \
            | gawk '{sec = $1*60*60+$2*60+$3;print sec}')
        printf "\r - Status: %s of %s - %s%%, %s  " \
            "$curr_stamp" \
            "$length_stamp" \
            "$(((curr_s*100)/length_sec))" \
            "$(get_filesize ${localfile})  "
    done < <($DOWNLOADER_BIN -i "$stream" \
        $downloader_params \
        -y "$localfile" 2>&1 \
        || echo -e "\rReturncode$?\r"
    )
    printf "\r - Status: %s of %s - 100%%, %s   \n" \
        "$length_stamp" \
        "$length_stamp" \
        "$(get_filesize "$localfile")"
    printf " - Download complete\n"
    printf ' - Elapsed time: %s\n\n' "$(timer "$t")"
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
    echo "$json" | gawk "$fnc"
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
    echo "$html" | gawk "${fnc}" RS="[<>]"
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
    echo "$html" | gawk "${fnc/hint/$hint}" RS="<" ORS=""
}

# Get the stream with the best quality
function getBestStream()
{
    local master=$1
    local master_html=$(curl $CURL_ "$master")
    local fnc='/BANDWIDTH/{
        match($0, /BANDWIDTH=([0-9]*)/, bitrate);
        match($0, /(http.*$|index.*$)/,url);
        printf "%s %s\n", bitrate[1], url[1];
    }'
    local new_stream=$(echo "$master_html" \
        | gawk "${fnc}" RS="#EXT-X-STREAM-INF" \
        | sort -n -r \
        | gawk '{print $2;exit}')

    if [[ "$new_stream" == "index*" ]]; then
        new_stream=${master//master.m3u8/$new_stream}
    fi

    echo "$stream"

}

# Download all the episodes!
function program_all()
{
    local url=$1
    local season=$SEASON
    local html=$(curl $CURL_ "$url")
    local program_id=$(gethtmlAttr "$html" "programid")

    local seasons=$(gethtmlAttr "$html" "data-season" "data-season")
    if $season ; then
        seasons=$(gethtmlAttr "$html" "seasonid")
    fi
    series_name=$(gethtmlMeta "$html" "seriesid")

    # Loop through all seasons, or just the selected one
    for season in $seasons ; do
        local url="https://tv.nrk.no/program/Episodes/$series_name/$season"
        if [ "$season" = "extra" ]; then
            url="https://tv.nrk.no/extramaterial/$series_name"
        fi
        local s_html=$(curl $CURL_ "$url")
        local episodes=$(gethtmlAttr "$s_html" "data-episode" "data-episode")
        local season_name=$(gethtmlContent "$s_html" "h1>")

        if [ "$season" = "extra" ]; then
            season_name="extramaterial"
        fi
        printf "Downloading \"%s\"\n" "$season_name"
        # loop through all the episodes
        for episode in $episodes ; do
            program "https://tv.nrk.no/serie/$series_name/$episode"
        done

    done
}

# Download program from url $1, to a local file $2 (if provided)
function program()
{
    local url="$1"

    local html=$(curl $CURL_ -L "$url")
    local program_id=$(gethtmlMeta "$html" "programid")

    # Fetch the info with the v8-API
    local v8=$(curl $CURL_ \
        "http://v8.psapi.nrk.no/mediaelement/${program_id}")

    local streams=$(parsejson "$v8" "url")
    local title=$(parsejson "$v8" "fullTitle")
    local season=$(parsejson "$v8" "relativeOriginUrl" \
        | gawk '/sesong/{printf(" %s", $0)}' RS='/')

    title="$title$season"
    printf "Downloading \"%s\"\n" "$title"

    # TODO FIXME Fix the name of the file
    local localfile="$title"
    localfile="${localfile// /_}"
    localfile="${localfile//&\#230;/ae}"
    localfile="${localfile//ø/o}"
    localfile="${localfile//å/aa}"
    localfile="${localfile//:/-}"

    if [[ -z $streams || ! "$streams" == *"http"* ]]; then
        local message
        message=$(parsejson "$v8" "messageType" \
            | gawk '{gsub("[A-Z]"," &");print tolower($0)}')
        printf " - %s program is %s: %s\n\n" \
            "$(is_tv_or_radio)" \
            "$(print_red "not available")" \
            "$message"
        return
    fi

    # Check if program has a valid subtitle
    local subtitle
    subtitle=$(parsejson "$v8" "hasSubtitles")

    if [ "$subtitle" == "true" ] && $SUB_DOWNLOADER && ! $DRY_RUN ; then
        echo " - Downloading subtitle"
        curl $CURL_ "http://v8.psapi.nrk.no/programs/$program_id/subtitles/tt" \
            | tt-to-subrip > "$localfile.srt"
    elif $SUB_DOWNLOADER && ! $IS_RADIO; then
        if [ "$subtitle" == "true" ] ; then
            printf " - Subtitle is %s\n" \
                "$(print_green "available")"
        else
            printf " - Subtitle is %s\n" \
                "$(print_red "not available")"
        fi
    fi

    local num_streams
    num_streams=$(echo "$streams" |  wc -w )
    local part=0

    # Download the stream(s)
    for stream in $streams ; do
        local dl_file="$localfile"

        if (( "$num_streams" > 1 )) ; then
            part=$((part+1))
            local more="-part_$part"
            dl_file="${dl_file// /_}$more"
        fi

        if $IS_RADIO; then
            dl_file="${dl_file}.mp3"
        elif [[ $localfile != *.mp4 && $localfile != *.mkv ]]; then
            dl_file="${dl_file}.mp4"
        fi

        # Download the stream
        download "$stream" "$dl_file"
    done

}
function main()
{
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
    if [ -z "$1" ]
    then
        usage
        exit 1
    fi

    for var in "$@"
    do
        case $var in

            *akamaihd.net*)
                download "$var"
                ;;
            *tv.nrk.no*|*radio.nrk.no*|*tv.nrksuper.no*)
                if [[ "$var" == *radio.nrk.no* ]]; then
                    IS_RADIO=true
                fi
                if $DL_ALL; then
                    program_all "$var"
                else
                    program "$var"
                fi
                ;;
            *)
                usage
                exit 1
                ;;
        esac
    done
}

main $@
# The End!
