NRK-TV-Downloader
======================
This is just another simple shell-script that dumps HLS video streams from NRK-TV into a h264-MPEG-4 container.
A HLS streams is just a bunch of short files, and this script downloads each piece via Curl into one single file. 
This script has nothing to do with NRK!
It is only meant for private use, and I am not responsible for anyone's use of it. 
Because the script relies on "HTML-Parsing" it can break at any time.


This script may be useful for those who are struggeling with low bandwidth and/or bad playback performance.

Current version: 0.4.5 

Usage
======================
    chmod +x NRK-TV-Downloader.sh
    [...]
    Usage: ./NRK-TV-Downloader.sh COMMAND [PARAMETERS]...

    Commands:
        stream [HLS_STREAM] [LOCAL_FILE]
        program [PROGRAM_URL] <LOCAL_FILE>
        help 

    Example: 
    $ ./NRK-TV-Downloader.sh program http://tv.nrk.no/serie/tore-paa-sporet/dmpf71005710/17-02-2013 
	

Requirements
======================
This script requires simple bash, sed, awk, printf and curl.

License
======================
    NRK-TV-Dowloader

                DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
                        Version 2, December 2004
    
     Copyright (C) 2013 Odin Ugedal <odinuge[at]gmail[dot]com>

     Everyone is permitted to copy and distribute verbatim or modified
     copies of this license document, and changing it is allowed as long
     as the name is changed.

                DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
       TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

      0. You just DO WHAT THE FUCK YOU WANT TO.

		
