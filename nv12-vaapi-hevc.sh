#!/bin/bash

# 5. Variáveis e Criação de Pasta
# Garante que a pasta exista para não dar erro de "No such file"
DESTINO="/home/bn/Videos"
mkdir -p "$DESTINO"

NOME_VIDEO="$DESTINO/video_$(date +%Y-%m-%d_%H-%M-%S)_cqp.mkv"
AUDIO_DEVICE="alsa_input.usb-ezcap_ezcap_GameLink_Neo_Pro_38200002-02.analog-stereo"

# 6. Execução com prioridades reais
LIBVA_DRIVER_NAME=radeonsi stdbuf -oL -eL \
ffmpeg -init_hw_device vaapi=va:/dev/dri/renderD128 -filter_hw_device va \
-extra_hw_frames 64 \
-thread_queue_size 4096 -f v4l2 -input_format nv12 -video_size 2560x1440 -framerate 60 -i /dev/video0 \
-thread_queue_size 4096 -f pulse -i "$AUDIO_DEVICE" \
-vf "format=nv12,hwupload" \
-c:v hevc_vaapi -profile:v main -rc_mode CQP -qp 24 -g 120 \
-max_muxing_queue_size 4096 \
-c:a aac -b:a 192k -af "aresample=async=1" \
"$NOME_VIDEO"
