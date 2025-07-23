#!/bin/bash

# Ed-Fi Multi-District Generator Script
# =====================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"
CONFIG_FILE="$SCRIPT_DIR/districts-config.json"
BASE_DIR="$SCRIPT_DIR/.."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    command -v jq >/dev/null 2>&1 || { 
        log_error "jq is required but not installed."
        exit 1
    }
    
    command -v openssl >/dev/null 2>&1 || {
        log_error "openssl is required but not installed."
        exit 1
    }
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
    
    log_success "Dependencies check passed"
}

# Generate SSL certificates for district
generate_ssl_cert() {
    local district_id=$1
    local hostname=$2
    local cert_dir=$3
    
    log_info "Generating SSL certificate for district $district_id..."
    
    mkdir -p "$cert_dir"
    
    # Generate private key
    openssl genrsa -out "$cert_dir/server.key" 2048
    
    # Generate certificate
    openssl req -new -x509 -key "$cert_dir/server.key" -out "$cert_dir/server.crt" -days 365 \
        -subj "/C=US/ST=State/L=City/O=Ed-Fi District $district_id/CN=$hostname"
    
    log_success "SSL certificate generated for $hostname"
}

# Generate encryption key (safe for sed)
generate_encryption_key() {
    openssl rand -base64 32
}

# Process single district
process_district() {
    local district_data=$1
    
    # Extract district information
    local district_id=$(echo "$district_data" | jq -r '.id')
    local district_name=$(echo "$district_data" | jq -r '.name')
    local network_name=$(echo "$district_data" | jq -r '.network_name')
    local ssl_hostname=$(echo "$district_data" | jq -r '.ssl.hostname')
    local ssl_cert=$(echo "$district_data" | jq -r '.ssl.cert_file')
    local ssl_key=$(echo "$district_data" | jq -r '.ssl.key_file')
    
    # Ports
    local nginx_port=$(echo "$district_data" | jq -r '.ports.nginx')
    local pgbouncer_admin_port=$(echo "$district_data" | jq -r '.ports.pgbouncer_admin')
    local pgbouncer_ods_port=$(echo "$district_data" | jq -r '.ports.pgbouncer_ods')
    
    # Databases
    local admin_db=$(echo "$district_data" | jq -r '.databases.admin')
    local security_db=$(echo "$district_data" | jq -r '.databases.security')
    local ods_db=$(echo "$district_data" | jq -r '.databases.ods')
    
    # Common data
    local edfi_tag=$(jq -r '.common.edfi_tag' "$CONFIG_FILE")
    
    log_info "Processing district: $district_id ($district_name)"
    
    # Create district directory
    local district_dir="$BASE_DIR/district-$district_id"
    mkdir -p "$district_dir"/{ssl-certs,logs}
    
    # Generate SSL certificates
    generate_ssl_cert "$district_id" "$ssl_hostname" "$district_dir/ssl-certs"
    
    # Generate encryption key
    local encryption_key=$(generate_encryption_key)
    
    # Generate docker-compose.yml with ALL replacements
    log_info "Generating docker-compose file for district $district_id..."
    sed -e "s/{{district_id}}/$district_id/g" \
        -e "s/{{district_name}}/$district_name/g" \
        -e "s/{{network_name}}/$network_name/g" \
        -e "s/{{ssl_hostname}}/$ssl_hostname/g" \
        -e "s/{{ssl_cert_file}}/$ssl_cert/g" \
        -e "s/{{ssl_key_file}}/$ssl_key/g" \
        -e "s/{{nginx_port}}/$nginx_port/g" \
        -e "s/{{pgbouncer_admin_port}}/$pgbouncer_admin_port/g" \
        -e "s/{{pgbouncer_ods_port}}/$pgbouncer_ods_port/g" \
        -e "s/{{admin_db}}/$admin_db/g" \
        -e "s/{{security_db}}/$security_db/g" \
        -e "s/{{ods_db}}/$ods_db/g" \
        "$TEMPLATE_DIR/docker-compose-template.yml" > "$district_dir/docker-compose-district-$district_id.yml"
    
    # Generate .env file using a temp file to avoid sed issues
    log_info "Generating .env file for district $district_id..."
    cp "$TEMPLATE_DIR/.env-template" "/tmp/env-temp-$district_id"
    
    # Replace placeholders one by one
    sed -i "s/{{district_id}}/$district_id/g" "/tmp/env-temp-$district_id"
    sed -i "s/{{district_name}}/$district_name/g" "/tmp/env-temp-$district_id"
    sed -i "s/{{ssl_hostname}}/$ssl_hostname/g" "/tmp/env-temp-$district_id"
    sed -i "s/{{ssl_cert_file}}/$ssl_cert/g" "/tmp/env-temp-$district_id"
    sed -i "s/{{ssl_key_file}}/$ssl_key/g" "/tmp/env-temp-$district_id"
    sed -i "s/{{admin_db}}/$admin_db/g" "/tmp/env-temp-$district_id"
    sed -i "s/{{security_db}}/$security_db/g" "/tmp/env-temp-$district_id"
    sed -i "s/{{ods_db}}/$ods_db/g" "/tmp/env-temp-$district_id"
    sed -i "s/{{edfi_tag}}/$edfi_tag/g" "/tmp/env-temp-$district_id"
    sed -i "s/{{encryption_key}}/$encryption_key/g" "/tmp/env-temp-$district_id"
    
    mv "/tmp/env-temp-$district_id" "$district_dir/.env-district-$district_id"
    
    # Create startup script
    cat > "$district_dir/start-district-$district_id.sh" << STARTEOF
#!/bin/bash
cd "\$(dirname "\$0")"
docker-compose -f docker-compose-district-$district_id.yml --env-file .env-district-$district_id up -d
echo "District $district_id services started!"
echo "Access: https://localhost:$nginx_port"
STARTEOF
    chmod +x "$district_dir/start-district-$district_id.sh"
    
    # Create stop script
    cat > "$district_dir/stop-district-$district_id.sh" << STOPEOF
#!/bin/bash
cd "\$(dirname "\$0")"
docker-compose -f docker-compose-district-$district_id.yml --env-file .env-district-$district_id down
echo "District $district_id services stopped!"
STOPEOF
    chmod +x "$district_dir/stop-district-$district_id.sh"
    
    log_success "District $district_id setup completed!"
}

# Main execution
main() {
    log_info "Ed-Fi Multi-District Generator Starting..."
    echo "=========================================="
    
    check_dependencies
    
    # Process each district
    local districts=$(jq -c '.districts[]' "$CONFIG_FILE")
    while IFS= read -r district; do
        process_district "$district"
        echo ""
    done <<< "$districts"
    
    log_success "All districts processed successfully!"
}

# Run main function
main "$@"
