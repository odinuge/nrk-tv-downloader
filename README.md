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

    Copyright (C) 2013 Odin Ugedal <odinuge[at]gmail[dot]com>

    This script has nothing to do with NRK!
    It is only meant for private use, and I am not responsible for anyone's use of it. 
    Because the script relies on "HTML-Parsing" it can break at any time.
    For updates see <https://github.com/odinuge/NRK-TV-Downloader>
	
    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program. If not, see <http://www.gnu.org/licenses/>.
		
