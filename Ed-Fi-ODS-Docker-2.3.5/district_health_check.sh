#!/bin/bash

# Ed-Fi District Health Check Script
# Usage: ./district-health-check.sh [district_id]

DISTRICT_ID=${1:-255901}
DISTRICT_DIR="$HOME/Ed-Fi-ODS-Docker-2.3.5/district-$DISTRICT_ID"

echo "=== Ed-Fi District $DISTRICT_ID Health Check ==="
echo "Time: $(date)"
echo

# Check if district directory exists
if [ ! -d "$DISTRICT_DIR" ]; then
    echo "❌ District directory not found: $DISTRICT_DIR"
    exit 1
fi

cd "$DISTRICT_DIR"

echo "📍 Location: $DISTRICT_DIR"
echo

# 1. Container Status
echo "🔍 CONTAINER STATUS"
echo "=================="
docker-compose -f docker-compose-district-$DISTRICT_ID.yml ps
echo

# 2. Services Health
echo "💓 SERVICES HEALTH"
echo "=================="
SERVICES=(
    "nginx-$DISTRICT_ID"
    "api-$DISTRICT_ID" 
    "adminapp-$DISTRICT_ID"
    "swagger-$DISTRICT_ID"
    "db-admin-$DISTRICT_ID"
    "db-ods-$DISTRICT_ID"
    "pb-admin-$DISTRICT_ID"
    "edfi_ods_$DISTRICT_ID"
)

for service in "${SERVICES[@]}"; do
    status=$(docker inspect --format='{{.State.Status}}' $service 2>/dev/null || echo "missing")
    health=$(docker inspect --format='{{.State.Health.Status}}' $service 2>/dev/null || echo "no-health")
    
    if [ "$status" = "running" ]; then
        echo "✅ $service: $status ($health)"
    else
        echo "❌ $service: $status"
    fi
done
echo

# 3. Network Connectivity Test
echo "🌐 NETWORK CONNECTIVITY"
echo "======================"
# Test internal connectivity from nginx to other services
docker exec nginx-$DISTRICT_ID nslookup api-$DISTRICT_ID 2>/dev/null && echo "✅ nginx → api-$DISTRICT_ID" || echo "❌ nginx → api-$DISTRICT_ID"
docker exec nginx-$DISTRICT_ID nslookup adminapp-$DISTRICT_ID 2>/dev/null && echo "✅ nginx → adminapp-$DISTRICT_ID" || echo "❌ nginx → adminapp-$DISTRICT_ID"  
docker exec nginx-$DISTRICT_ID nslookup swagger-$DISTRICT_ID 2>/dev/null && echo "✅ nginx → swagger-$DISTRICT_ID" || echo "❌ nginx → swagger-$DISTRICT_ID"

# Test aliases
docker exec nginx-$DISTRICT_ID nslookup api 2>/dev/null && echo "✅ nginx → api (alias)" || echo "❌ nginx → api (alias)"
docker exec nginx-$DISTRICT_ID nslookup adminapp 2>/dev/null && echo "✅ nginx → adminapp (alias)" || echo "❌ nginx → adminapp (alias)"
docker exec nginx-$DISTRICT_ID nslookup docs 2>/dev/null && echo "✅ nginx → docs (alias)" || echo "❌ nginx → docs (alias)"
echo

# 4. Port Status
echo "🔌 PORT STATUS"
echo "============="
PORTS=(
    "8${DISTRICT_ID: -1}00:NGINX"
    "6${DISTRICT_ID: -1}01:PgBouncer-Admin" 
    "6${DISTRICT_ID: -1}02:PgBouncer-ODS"
)

for port_info in "${PORTS[@]}"; do
    port=$(echo $port_info | cut -d: -f1)
    name=$(echo $port_info | cut -d: -f2)
    
    if netstat -ln | grep ":$port " > /dev/null 2>&1; then
        echo "✅ $name: Port $port listening"
    else
        echo "❌ $name: Port $port not listening"
    fi
done
echo

# 5. Recent Logs (Last 30 lines per service)
echo "📝 RECENT LOGS (Last 30 lines)"
echo "==============================="

for service in "${SERVICES[@]}"; do
    echo "--- $service ---"
    docker-compose -f docker-compose-district-$DISTRICT_ID.yml logs --tail 30 --no-color $service-$DISTRICT_ID 2>/dev/null | tail -10
    echo
done

# 6. Critical Error Check
echo "🚨 CRITICAL ERRORS CHECK"
echo "========================"
echo "Checking for common errors in logs..."

# Check for NGINX upstream errors
nginx_errors=$(docker-compose -f docker-compose-district-$DISTRICT_ID.yml logs nginx-$DISTRICT_ID 2>/dev/null | grep -i "upstream" | tail -5)
if [ ! -z "$nginx_errors" ]; then
    echo "❌ NGINX Upstream Errors:"
    echo "$nginx_errors"
else
    echo "✅ No NGINX upstream errors"
fi

# Check for database connection errors
db_errors=$(docker-compose -f docker-compose-district-$DISTRICT_ID.yml logs api-$DISTRICT_ID 2>/dev/null | grep -i "connection\|database\|postgres" | grep -i "error\|fail" | tail -3)
if [ ! -z "$db_errors" ]; then
    echo "❌ Database Connection Errors:"
    echo "$db_errors"
else
    echo "✅ No database connection errors"
fi

# Check for SSL/Certificate errors
ssl_errors=$(docker-compose -f docker-compose-district-$DISTRICT_ID.yml logs 2>/dev/null | grep -i "ssl\|certificate\|tls" | grep -i "error\|fail" | tail -3)
if [ ! -z "$ssl_errors" ]; then
    echo "❌ SSL/Certificate Errors:"
    echo "$ssl_errors"
else
    echo "✅ No SSL/certificate errors"
fi

echo
echo "=== Health Check Complete ==="
echo "💡 Quick Tests:"
echo "   curl -k https://localhost:8${DISTRICT_ID: -1}00/api/metadata"
echo "   curl -k https://localhost:8${DISTRICT_ID: -1}00/adminapp"
echo "   curl -k https://localhost:8${DISTRICT_ID: -1}00/docs"