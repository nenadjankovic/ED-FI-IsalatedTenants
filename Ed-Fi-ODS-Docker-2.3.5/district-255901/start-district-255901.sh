#!/bin/bash
cd "$(dirname "$0")"
docker-compose -f docker-compose-district-255901.yml --env-file .env-district-255901 up -d
echo "District 255901 services started!"
echo "Access: https://localhost:8100"
