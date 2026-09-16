#!/bin/bash
set -e

# Start Browserless background daemon directly via Node
(cd /usr/src/app && node build) &

# Wait for Browserless WebSocket server to become ready
echo "Waiting for Browserless to initialize on port 3000..."
while ! nc -z localhost 3000; do
  sleep 1
done

echo "Browserless ready. Starting traffic generator script..."
exec python3 /app/generator.py
