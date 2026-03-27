#!/bin/bash
#
# Kokoro TTS Server Setup for AIrch
#
# This script:
#   1. Installs FastAPI + uvicorn in the kokoro-env
#   2. Deploys kokoro_server.py
#   3. Creates a systemd user service for auto-start
#
# Usage:
#   ssh rafael@AIrch.local 'bash -s' < scripts/kokoro_setup.sh
#   OR: scp scripts/kokoro_setup.sh rafael@AIrch.local:~ && ssh rafael@AIrch.local ./kokoro_setup.sh
#
set -euo pipefail

KOKORO_ENV="$HOME/kokoro-env"
KOKORO_PORT="${KOKORO_PORT:-8880}"
KOKORO_BIND="${KOKORO_BIND:-0.0.0.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Kokoro TTS Server Setup ==="

# 1. Check kokoro-env exists
if [ ! -d "$KOKORO_ENV" ]; then
    echo "ERROR: kokoro-env not found at $KOKORO_ENV"
    echo "Please create the Kokoro Python environment first."
    exit 1
fi

# 2. Install FastAPI + uvicorn
echo "[1/4] Installing FastAPI + uvicorn..."
"$KOKORO_ENV/bin/pip" install --quiet fastapi uvicorn

# 3. Check ffmpeg is available (needed for MP3/Opus conversion)
if command -v ffmpeg &>/dev/null; then
    echo "[2/4] ffmpeg found: $(which ffmpeg)"
else
    echo "[2/4] WARNING: ffmpeg not found. MP3/Opus conversion will fail."
    echo "       Install with: sudo pacman -S ffmpeg  (or apt install ffmpeg)"
fi

# 4. Deploy server script
echo "[3/4] Deploying kokoro_server.py..."
if [ -f "$SCRIPT_DIR/kokoro_server.py" ]; then
    cp "$SCRIPT_DIR/kokoro_server.py" "$KOKORO_ENV/kokoro_server.py"
else
    # If running remotely, the script should already be at ~/kokoro-env/
    echo "       kokoro_server.py not found in script dir. Make sure to copy it manually:"
    echo "       scp scripts/kokoro_server.py rafael@AIrch.local:~/kokoro-env/"
fi

# 5. Create systemd user service
echo "[4/4] Creating systemd user service..."
mkdir -p "$HOME/.config/systemd/user"

cat > "$HOME/.config/systemd/user/kokoro-tts.service" <<EOF
[Unit]
Description=Kokoro TTS FastAPI Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$KOKORO_ENV
ExecStart=$KOKORO_ENV/bin/uvicorn kokoro_server:app --host $KOKORO_BIND --port $KOKORO_PORT
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

# Enable and start
systemctl --user daemon-reload
systemctl --user enable kokoro-tts.service
systemctl --user restart kokoro-tts.service

echo ""
echo "=== Setup Complete ==="
echo "Kokoro TTS server running on http://$KOKORO_BIND:$KOKORO_PORT"
echo ""
echo "Commands:"
echo "  systemctl --user status kokoro-tts    # Check status"
echo "  systemctl --user restart kokoro-tts   # Restart"
echo "  systemctl --user stop kokoro-tts      # Stop"
echo "  journalctl --user -u kokoro-tts -f    # View logs"
echo ""
echo "Test:"
echo "  curl -X POST http://localhost:$KOKORO_PORT/v1/audio/speech \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"input\": \"Hello world\", \"voice\": \"af_heart\"}' \\"
echo "    --output test.mp3"
