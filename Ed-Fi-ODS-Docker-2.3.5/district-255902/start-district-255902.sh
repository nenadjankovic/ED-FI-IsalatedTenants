#!/bin/bash
cd "$(dirname "$0")"
docker-compose -f docker-compose-district-255902.yml --env-file .env-district-255902 up -d
echo "District 255902 services started!"
echo "Access: https://localhost:8200"
