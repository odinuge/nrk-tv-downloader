NRK-TV-Downloader
======================
This is just another simple shell-script that dumps HLS video streams from NRK-TV into a h264-MPEG-4 container.
The script is using ffmpeg, or curl as a fallback (not the best option) 
This script has nothing to do with NRK!
It is only meant for private use, and I am not responsible for anyone's use of it. 
Because the script relies on "HTML-Parsing" it can break at any time.


This script may be useful for those who are struggeling with low bandwidth and/or bad playback performance.

Current version: 0.5.0

Usage
======================
    chmod +x NRK-TV-Downloader.sh
    [...]
    Usage: ./NRK-TV-Downloader.sh <OPTION>... [PROGRAM_URL(s)]...

    Options:
         -a download all episodes, in all seasons.
         -s download all episodes in season
         -v print version
         -h print this


    For updates see <https://github.com/odinuge/NRK-TV-Downloader>  

    Example: 
    $ ./NRK-TV-Downloader.sh -a http://tv.nrk.no/serie/tore-paa-sporet/dmpf71005710/17-02-2013
	

Requirements
======================
This script requires bash, rev, cut, grep, sed, awk, printf and curl.

License
======================
MIT © [Odin Ugedal](https://ugedal.com)
