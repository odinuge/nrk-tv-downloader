# nrk-tv-downloader
> Lightweight bash utility to easily download content from nrk-tv,
> radio and super.

![Terminal with nrk-tv-downloader](screenshot.png)

## About

This is just another simple shell-script that downloads programs from nrk-tv. It also supports nrk-radio and nrk-super.

This script has nothing to do with NRK!


## Install
```bash
git clone https://github.com/odinuge/nrk-tv-downloader/ --recursive
```

### Subtitles
To download subtitles you need [tt-to-subrip](https://github.com/odinuge/tt-to-subrip/). To get it, you have to clone this repo with the `--recursive` flag, or execute the following (inside this repo):

```
git submodule update --init --recursive

```

## Usage

```
$ ./nrk-tv-downloader.sh

Usage: ./nrk-tv-downloader.sh <OPTION>... [PROGRAM_URL(s)]...

Options:
     -a download all episodes, in all seasons.
     -s download all episodes in season
     -n skip files that exists
     -d dry run - list what is possible to download
     -u do not download subtitles
     -e episode mode - format episodes as Series.name.SXXEXX.mp4
     -f create series and season number folders for episodes (use together with -e)
     -q will ask you to select quality
     -t target directory for downloaded files (e.g. /mnt/media/TV - no trailing slash)
     -h print this


For updates see <https://github.com/odinuge/nrk-tv-downloader>

Example:
$ ./nrk-tv-downloader.sh -s "https://tv.nrk.no/serie/skam/MYNT15000116/sesong-2/episode-1"
$ ./nrk-tv-downloader.sh "http://skam.p3.no/"
```

## Code style
The source code (`nrk-tv-downloader.sh`) is formatted with [shfmt](https://github.com/mvdan/sh). To format the code, run:

```bash
$ shfmt -l -w nrk-tv-downloader.sh
```

## Requirements
This script requires bash, rev, cut, grep, sed, gawk, printf, curl and ffmpeg/avconv.

## License
MIT © [Odin Ugedal](https://ugedal.com)
