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
    Usage: ./NRK-TV-Downloader.sh [PARAMETERS]...

    Commands:
        [HLS_STREAM] [LOCAL_FILE]
        [PROGRAM_URL] <LOCAL_FILE>
        help 

    Example: 
    $ ./NRK-TV-Downloader.sh http://tv.nrk.no/serie/tore-paa-sporet/dmpf71005710/17-02-2013
	

Requirements
======================
This script requires bash, rev, cut, grep, sed, awk, printf and curl.

License
======================
[`NRK-TV-Dowloader`](https://github.com/odinuge/NRK-TV-Downloader)
is licensed under the MIT License:

> The MIT License (MIT)
>
> Copyright (c) 2013 Odin Ugedal <odin@ugedal.com>
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
> THE SOFTWARE.
>
> Contributors:
> Henrik Lilleengen <mail@ithenrik.com>
>

