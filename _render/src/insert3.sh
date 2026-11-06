#!/bin/bash
# Encode the new return/insert clip (seq38: bank starts fully outside -> pushed into the slot).
# 67 frames @30fps; the last 6 frames cross-fade back to frame 1 so the clip loops seamlessly.
set -e
cd "$(dirname "$0")/.."
FF=/opt/homebrew/bin/ffmpeg
IN="-framerate 30 -start_number 440 -i _vert/seq38/f_%04d.png"
FIRST="-loop 1 -framerate 30 -t 0.2 -i _vert/seq38/f_0440.png"
FX="[0:v]scale=888:1924,format=yuv420p,setpts=PTS-STARTPTS[a];[1:v]scale=888:1924,format=yuv420p,setpts=PTS-STARTPTS[b];[a][b]xfade=transition=fade:duration=0.2:offset=2.0333[v]"
$FF -y -hide_banner -loglevel error $IN $FIRST -filter_complex "$FX" -map "[v]" -frames:v 67 -c:v libx264 -crf 19 -preset veryfast -movflags +faststart _vert/insert3.mp4
$FF -y -hide_banner -loglevel error $IN $FIRST -filter_complex "$FX" -map "[v]" -frames:v 67 -c:v libx265 -crf 24 -preset medium -tag:v hvc1 -movflags +faststart _vert/insert3_hevc.mp4
echo ENC_DONE
