# nrk-tv-downloader
> Lightweight bash utility to easily download content from nrk-tv, radio and super.

![Terminal with nrk-tv-downloader](screenshot.png)

## About

This is just another simple shell-script that downloads programs from nrk-tv. It also supports nrk-radio and nrk-super.

This script has nothing to do with NRK!


## Install
    $ git clone https://github.com/odinuge/nrk-tv-downloader/ --recursive


## Usage


    chmod +x nrk-tv-downloader.sh
    [...]
    Usage: ./nrk-tv-downloader.sh <OPTION>... [PROGRAM_URL(s)]...

    Options:
         -a download all episodes, in all seasons.
         -s download all episodes in season
         -n skip files that exists
         -d dry run - list what is possible to download
         -h print this


    For updates see <https://github.com/odinuge/nrk-tv-downloader>

    Example:
    $ ./nrk-tv-downloader.sh -s "https://tv.nrk.no/serie/skam/MYNT15000116/sesong-2/episode-1"

## Requirements
This script requires bash, rev, cut, grep, sed, gawk, printf, curl and ffmpeg/avconv.

## License
MIT © [Odin Ugedal](https://ugedal.com)
