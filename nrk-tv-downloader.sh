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
DOWNLOAD_SUBS=true
EPISODE_FORMAT=false
EPISODE_FOLDERS=false
TARGET_PATH="." # default to current folder unless specified

# Curl flags (for making it silent)
readonly CURL_="-s -L"

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
        printf '%02d:%02d:%02d' $dh $dm $ds
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
    echo -e "\t -u do not download subtitles"
    echo -e "\t -e episode mode - format episodes as Series.name.SXXEXX.mp4"
    echo -e "\t -f create series and season number folders for episodes (use together with -e)"
    echo -e "\t -t target directory for downloaded files (e.g. /mnt/media/TV)"
    echo -e "\t -h print this\n"
    echo -e "\nFor updates see <https://github.com/odinuge/nrk-tv-downloader>"
}

# Get the filesize of a file
function get_filesize()
{
    local file=$1
    du -h "$file" 2>/dev/null | gawk '{print $1B}'
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

# Get a more human readable representation of $1 seconds
function sec_to_human_readable {
  local INPUT_S=$1
  local H=$((INPUT_S/60/60))
  local M=$((INPUT_S/60%60))
  local S=$((INPUT_S%60))
  (( $H > 0 )) && printf '%d hours ' $H
  (( $M > 0 )) && printf '%d minutes ' $M && return
  printf '%d seconds' $S
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
            printf "\n - Skipping program, %s\n\n" \
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
        elif [[ $line != *bitrate\=* || $line != *speed\=* ]]; then
            $is_newline || echo && is_newline=true
            printf " - %s %s" \
                "$(print_red "${DOWNLOADER_BIN} error")" \
                "$line"

            continue
        fi
        is_newline=false

        # Bitrate of source in Kbit/s
        local bitrate="$(echo "$line" \
            | gawk '/bitrate=/{print}' \
            | sed -E 's/^.*bitrate= *([0-9]+).*$/\1/g' \
        )"

        # Speed relative to video "speed"
        # Eg. speed=5 -> 5x -> 5 times faster downloading
        # than the speed of the video
        local speed="$(echo "$line" \
            | gawk '/speed=/{print}' \
            | sed -E 's/^.*speed= *([0-9.]+).+$/\1/' \
        )"

        # Downloadspeed in Mbit/s
        local dl_speed=$(echo "$bitrate $speed" | awk '{printf("%.1f", $1*$2/1024)}')
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

        # Percent of total download - 0% -> 100%
        local percent_dl="$(((curr_s*100)/length_sec))"

        # Download ETA, estimated with the remaining time, and the dl speed
        local eta=$(echo "$length_sec $curr_s $speed"|awk '{printf("%.0f", ($1-$2)/$3)}')

        printf '\r - Status: %s of %s - %s%%, %.1fMbit/s - ETA: %s   ' \
            "$curr_stamp" \
            "$length_stamp" \
            "$percent_dl" \
            "$dl_speed" \
            "$(sec_to_human_readable $eta)"

    done < <($DOWNLOADER_BIN -i "$stream" \
        $downloader_params \
        -y "$localfile" 2>&1 \
        || echo -e "\rReturncode$?\r"
    )
    printf '\r - Status: %s of %s - %s%%, %.1fMbit/s - ETA: %s   \n' \
            "$length_stamp" \
            "$length_stamp" \
            "100" \
            "$dl_speed" \
            "$(sec_to_human_readable 0)"

    printf " - Download complete\n"
    printf " - Filesize: %sB\n" "$(get_filesize "$localfile")"
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
    /tag\"\:/{
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
    gethtmlAttr "$html" "meta property=\"$name\"" "content"
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

#Add a "0" before the numbers 1-9
function prefix_number()
{
  local number=$1
  if [ $number -lt 10 ] ; then
    echo "0$number"
  else
    echo "$number"
  fi
}

# Download all the episodes!
function program_all()
{
    local url=$1
    local ONLY_CURRENT=$SEASON
    local html=$(curl $CURL_ "$url")
    local program_id=$(gethtmlMeta "$html" 'og:url' \
        | sed -E 's/.*([A-Z]{4}[0-9]{8}).*/\1/'
    )
    local series_name=$(gethtmlMeta "$html" 'og:url' \
        | sed -E 's/.*serie\/([^/]+).*/\1/'
    )
    if $ONLY_CURRENT ; then
        seasons=$(gethtmlMeta "$html" 'seasonid')
        if [[ -z $seasons ]]; then
          seasons=$(gethtmlAttr "$html" "seasontabs" "data-module-settings" \
              |  sed -E "s/.*([0-9]{5}).*/\1/"
          )
        fi
    else
        seasons=$(gethtmlAttr "$html" "data-season" "data-season")
        if [[ -z $seasons ]]; then
          seasons=$(gethtmlAttr "$html" "season-episodes" "id" \
              |  sed -E "s/.*([0-9]{5}).*/\1/"
          )
        fi
    fi
    if [[ -z $seasons ]]; then
      printf "Unable to download. Found no seasons."
      exit 1
    fi

    if ! $ONLY_CURRENT ; then
        printf 'Available seasons of "%s": %s\n' \
          "$series_name" \
          "$(echo $seasons | wc -w)"
    fi
    # Loop through all seasons, or just the selected one
    for season in $seasons ; do
        local url="https://tv.nrk.no/program/Episodes/$series_name/$season"
        if [ "$season" = "extra" ]; then
            url="https://tv.nrk.no/extramaterial/$series_name"
        fi
        local s_html=$(curl $CURL_ "$url")

        # Find only episodes with program-rights
        # will match lines in awk like `/episode-item/ && !/no-rights/ {}`
        local episodes=$(gethtmlAttr "$s_html" "episode-item/ && !/no-rights" "data-episode")
        local season_name=$(gethtmlContent "$s_html" "h1>")

        if [ "$season" = "extra" ]; then
            season_name="extramaterial"
        fi
        printf 'Available episodes in "%s": %s\n' \
            "$season_name" \
            "$(echo $episodes | wc -w)"

        if $DRY_RUN ; then
            continue
        fi
        # loop through all the episodes
        for episode in $episodes ; do
            program "https://tv.nrk.no/serie/$series_name/$episode"
        done

    done
}

function embedded_video()
{
    local url=$1
    local season=$SEASON
    local html=$(curl $CURL_ "$url")

    local episodes=$(gethtmlAttr "$html" 'class="nrk-video\"' "data-nrk-id")

    if [[ -z $episodes ]]; then
      echo "Found no video streams in the given url..."
      return
    fi
    echo "Downloading video streams from given url"
    for episode in $episodes ; do
      printf "Downloading \"%s\"\n" "$episode"
      local stream="https://nordond17b-f.akamaihd.net/i/nordics/open/skam/${episode}_,205,380,659,1394,2410,.mp4.csmil/master.m3u8"
      download "$stream" "${episode}.mp4"

    done
}

# Download program from url $1, to a local file $2 (if provided)
function program()
{
    local url="$1"

    local html=$(curl $CURL_ -L "$url")
    local program_id=$(gethtmlMeta "$html" 'og:url' \
        | sed -E 's/.*([A-Z]{4}[0-9]{8}).*/\1/'
    )

    # Fetch the info with the v8-API
    local v8=$(curl $CURL_ \
        "http://v8.psapi.nrk.no/mediaelement/${program_id}")

    local streams=$(parsejson "$v8" "url")

    local localfile=""
    local title=""
    local season=""
    local episode=""

    # Figure out title and local filename format
    if $EPISODE_FORMAT && [ $(parsejson "$v8" "mediaElementType") == "Episode" ] ; then
      # Episode format enabled and available
      title=$(parsejson "$v8" "seriesTitle")

      local ep_num_or_date=$(parsejson "$v8" "episodeNumberOrDate")
      local season_ep_format=""

      if [[ $ep_num_or_date == *":"* ]]; then #season epsiode format
        local season_prefix="sesong-"
        local arr_episode_format=(${ep_num_or_date//:/ })
        season=$(parsejson "$v8" "relativeOriginUrl" \
            | gawk '/sesong/{printf("%s", $0)}' RS='/')

        season=${season#$season_prefix}
        season="$(prefix_number "$season")"
        episode="$(prefix_number "${arr_episode_format[0]}")"
        season_ep_format="S${season}E${episode}"
      else
        season_ep_format=episodeNumberOrDate # date format
      fi

      localfile="$title.$season_ep_format"
      localfile="${localfile// /.}"
    else
      # Standard format
      title=$(parsejson "$v8" "fullTitle")
      season=$(parsejson "$v8" "relativeOriginUrl" \
          | gawk '/sesong/{printf(" %s", $0)}' RS='/')
      localfile="$title$season"
      localfile="${localfile// /_}"
    fi

    printf 'Program "%s"\n' "$title"

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

    # setup target path and file
    local localfolder="$TARGET_PATH/"
    mkdir -p "$localfolder" # create if not exists

    if $EPISODE_FORMAT && $EPISODE_FOLDERS && [ $(parsejson "$v8" "mediaElementType") == "Episode" ] ; then
      local series_folder="$localfolder$title"
      mkdir -p "$series_folder"
      series_folder="$series_folder/Season $season"
      mkdir -p "$series_folder"
      localfolder="$series_folder/"
    fi

    # TODO FIXME Fix the name of the file
    localfile="${localfile//&\#230;/ae}"
    localfile="${localfile//ø/o}"
    localfile="${localfile//å/aa}"
    localfile="${localfile//:/-}"
    localfile="$localfolder$localfile"

    # Check if program has a valid subtitle (if downloading subs enabled)
    if $DOWNLOAD_SUBS ; then
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

    while getopts "hasnudeft:" opt; do
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
            u)  DOWNLOAD_SUBS=false
                ;;
            e)  EPISODE_FORMAT=true
                ;;
            f)  EPISODE_FOLDERS=true
                ;;
            t)  if [ -z "$OPTARG" ] ; then
                  usage
                  exit 0
                else
                  TARGET_PATH="$OPTARG"
                fi
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
            *nrk.no*|*p3.no*)
                embedded_video "$var"
                ;;
            *)
                ;;
        esac
    done
}

main "$@"
# The End!
