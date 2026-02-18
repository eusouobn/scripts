#!/bin/bash

DESTINO="/mnt/videos"
mkdir -p "$DESTINO"

BASE="video_$(date +%Y-%m-%d_%H-%M-%S)"

VIDEO="$DESTINO/${BASE}_video.mkv"
AUDIO="$DESTINO/${BASE}_audio.wav"
FINAL="$DESTINO/${BASE}_final.mkv"

AUDIO_DEVICE="alsa_input.usb-ezcap_ezcap_GameLink_Neo_Pro_38200002-02.analog-stereo"

echo ">>> Iniciando captura..."

# Beep de sincronização
speaker-test -t sine -f 1000 -l 1 >/dev/null 2>&1 &

sleep 0.2

# Vídeo
LIBVA_DRIVER_NAME=radeonsi ffmpeg \
-init_hw_device vaapi=va:/dev/dri/renderD128 -filter_hw_device va \
-extra_hw_frames 128 \
-fflags nobuffer+genpts -flags low_delay \
-use_wallclock_as_timestamps 1 \
-thread_queue_size 8192 \
-f v4l2 -input_format nv12 -video_size 2560x1440 -framerate 60 -i /dev/video0 \
-vf "format=nv12,hwupload" \
-c:v hevc_vaapi -rc_mode CQP -qp 26 \
-an \
"$VIDEO" &

PID_VIDEO=$!

# Áudio
ffmpeg \
-thread_queue_size 8192 \
-f pulse -i "$AUDIO_DEVICE" \
-c:a pcm_s16le \
-af "aresample=async=1:first_pts=0" \
"$AUDIO" &

PID_AUDIO=$!

echo ">>> Gravando... pressione ENTER para parar"
read

echo ">>> Parando..."

kill -INT $PID_VIDEO
kill -INT $PID_AUDIO

wait

echo ">>> Fazendo mux..."

ffmpeg -i "$VIDEO" -i "$AUDIO" -c copy "$FINAL"

echo ">>> Finalizado:"
echo "$FINAL"
