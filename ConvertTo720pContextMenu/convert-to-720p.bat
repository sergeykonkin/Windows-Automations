@echo off
for %%a in (%*) do (
    ffmpeg -hwaccel cuda -i "%%~a" -vf scale=-1:720 -c:v h264_nvenc -preset slow -b:v 8M -c:a aac -b:a 128k "%%~dpna_720p.mp4"
)
