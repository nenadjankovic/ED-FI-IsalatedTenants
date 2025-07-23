#!/bin/bash
cd "$(dirname "$0")"
docker-compose -f docker-compose-district-255902.yml --env-file .env-district-255902 down
echo "District 255902 services stopped!"
