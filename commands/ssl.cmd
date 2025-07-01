#!/usr/bin/env bash

[[ ! ${FORTRESS_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

if [[ ${#FORTRESS_PARAMS[@]} -eq 0 ]]; then
    SUBCOMMAND="status"
    SUBCOMMAND_ARGS=()
else
    SUBCOMMAND="${FORTRESS_PARAMS[0]}"
    SUBCOMMAND_ARGS=("${FORTRESS_PARAMS[@]:1}")
fi

function sslStatus() {
    info "SSL Certificate Status"
    echo ""
    
    local certs_found=0
    local acme_file="${FORTRESS_PROXY_DIR}/acme.json"
    local certs_dir="${FORTRESS_PROXY_DIR}/certs"
    
    # Check Let's Encrypt certificates
    if [[ -f "$acme_file" ]]; then
        if command -v jq >/dev/null 2>&1; then
            local cert_count=$(jq -r '.letsencrypt.Certificates | length' "$acme_file" 2>/dev/null || echo "0")
            if [[ "$cert_count" -gt 0 ]]; then
                echo "🔒 Let's Encrypt Certificates: $cert_count found"
                certs_found=1
                
                # List domains if possible
                echo "   Domains:"
                jq -r '.letsencrypt.Certificates[] | .domain.main' "$acme_file" 2>/dev/null | while read -r domain; do
                    if [[ -n "$domain" ]]; then
                        echo "   - $domain"
                    fi
                done
            else
                echo "🔓 Let's Encrypt Certificates: None found"
            fi
        else
            if [[ -s "$acme_file" ]]; then
                echo "🔒 Let's Encrypt file exists (jq not available for details)"
                certs_found=1
            else
                echo "🔓 Let's Encrypt file empty or missing"
            fi
        fi
    else
        echo "🔓 Let's Encrypt file not found"
    fi
    
    echo ""
    
    # Check manual certificates
    if [[ -d "$certs_dir" ]] && [[ -n "$(ls -A "$certs_dir" 2>/dev/null)" ]]; then
        local manual_certs=$(ls -1 "$certs_dir"/*.crt "$certs_dir"/*.pem 2>/dev/null | wc -l || echo "0")
        if [[ "$manual_certs" -gt 0 ]]; then
            echo "📁 Manual Certificates: $manual_certs found"
            echo "   Files:"
            ls -la "$certs_dir"/*.{crt,pem,key} 2>/dev/null | awk '{print "   - " $9 " (" $5 " bytes, " $6 " " $7 " " $8 ")"}' || echo "   - Unable to list files"
            certs_found=1
        else
            echo "📁 Manual Certificates: None found"
        fi
    else
        echo "📁 Manual Certificates directory: Empty or missing"
    fi
    
    echo ""
    
    # Check Traefik status
    if docker ps --format "table {{.Names}}" | grep -q "fortress_traefik"; then
        echo "🌐 Traefik Status: Running"
        
        # Check if Traefik API is accessible
        if curl -s http://localhost:8080/ping >/dev/null 2>&1; then
            echo "📊 Traefik API: Accessible"
        else
            echo "📊 Traefik API: Not accessible"
        fi
    else
        echo "🌐 Traefik Status: Not running"
    fi
    
    echo ""
    
    if [[ $certs_found -eq 0 ]]; then
        warning "No SSL certificates found. Consider running 'fortress ssl renew' after setting up domains."
        return 1
    else
        success "SSL certificates are configured"
        return 0
    fi
}

function sslRenew() {
    local DOMAIN="${SUBCOMMAND_ARGS[0]}"
    
    if [[ -z "$DOMAIN" ]]; then
        fatal "ssl renew: Domain name is required. Usage: fortress ssl renew <domain.com>"
    fi
    
    info "Renewing SSL certificate for domain: $DOMAIN"
    
    # Check if Traefik is running
    if ! docker ps --format "table {{.Names}}" | grep -q "fortress_traefik"; then
        fatal "ssl renew: Traefik is not running. Start it with 'fortress svc up proxy'"
    fi
    
    # Force renewal by removing existing certificate
    local acme_file="${FORTRESS_PROXY_DIR}/acme.json"
    if [[ -f "$acme_file" ]]; then
        info "Backing up current acme.json..."
        cp "$acme_file" "${acme_file}.backup.$(date +%Y%m%d_%H%M%S)"
        
        if command -v jq >/dev/null 2>&1; then
            info "Removing certificate for $DOMAIN from acme.json..."
            # Create a temporary file with the domain removed
            jq --arg domain "$DOMAIN" '
                .letsencrypt.Certificates = [
                    .letsencrypt.Certificates[] | 
                    select(.domain.main != $domain)
                ]
            ' "$acme_file" > "${acme_file}.tmp" && mv "${acme_file}.tmp" "$acme_file"
        else
            warning "jq not available - cannot selectively remove certificate. Manual intervention may be needed."
        fi
    fi
    
    # Restart Traefik to trigger certificate renewal
    info "Restarting Traefik to trigger certificate renewal..."
    (cd "${FORTRESS_PROXY_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "fortress_proxy" restart)
    
    # Wait a moment for Traefik to start
    sleep 5
    
    # Check if certificate was issued
    info "Waiting for certificate to be issued (this may take a few minutes)..."
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if [[ -f "$acme_file" ]] && command -v jq >/dev/null 2>&1; then
            if jq -e --arg domain "$DOMAIN" '.letsencrypt.Certificates[] | select(.domain.main == $domain)' "$acme_file" >/dev/null 2>&1; then
                success "Certificate for $DOMAIN has been issued!"
                return 0
            fi
        fi
        
        attempts=$((attempts + 1))
        echo -n "."
        sleep 10
    done
    
    echo ""
    warning "Certificate renewal process completed, but verification failed. Check Traefik logs:"
    echo "  fortress logs proxy"
    return 1
}

function sslAdd() {
    local CERT_FILE="${SUBCOMMAND_ARGS[0]}"
    local KEY_FILE="${SUBCOMMAND_ARGS[1]}"
    local CERT_NAME="${SUBCOMMAND_ARGS[2]}"
    
    if [[ -z "$CERT_FILE" ]] || [[ -z "$KEY_FILE" ]]; then
        fatal "ssl add: Certificate and key files are required. Usage: fortress ssl add <cert.crt> <cert.key> [name]"
    fi
    
    [[ ! -f "$CERT_FILE" ]] && fatal "ssl add: Certificate file '$CERT_FILE' not found"
    [[ ! -f "$KEY_FILE" ]] && fatal "ssl add: Key file '$KEY_FILE' not found"
    
    if [[ -z "$CERT_NAME" ]]; then
        CERT_NAME=$(basename "$CERT_FILE" .crt)
    fi
    
    local certs_dir="${FORTRESS_PROXY_DIR}/certs"
    mkdir -p "$certs_dir"
    
    info "Adding manual SSL certificate: $CERT_NAME"
    
    # Copy certificate files
    cp "$CERT_FILE" "${certs_dir}/${CERT_NAME}.crt"
    cp "$KEY_FILE" "${certs_dir}/${CERT_NAME}.key"
    
    # Set proper permissions
    chmod 644 "${certs_dir}/${CERT_NAME}.crt"
    chmod 600 "${certs_dir}/${CERT_NAME}.key"
    chown root:root "${certs_dir}/${CERT_NAME}".{crt,key}
    
    # Restart Traefik to load new certificates
    info "Restarting Traefik to load new certificates..."
    (cd "${FORTRESS_PROXY_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "fortress_proxy" restart)
    
    success "Manual certificate '$CERT_NAME' added successfully"
}

function sslRemove() {
    local CERT_NAME="${SUBCOMMAND_ARGS[0]}"
    
    if [[ -z "$CERT_NAME" ]]; then
        fatal "ssl remove: Certificate name is required. Usage: fortress ssl remove <cert-name>"
    fi
    
    local certs_dir="${FORTRESS_PROXY_DIR}/certs"
    local cert_file="${certs_dir}/${CERT_NAME}.crt"
    local key_file="${certs_dir}/${CERT_NAME}.key"
    
    if [[ ! -f "$cert_file" ]] && [[ ! -f "$key_file" ]]; then
        fatal "ssl remove: Certificate '$CERT_NAME' not found"
    fi
    
    warning "This will remove the manual certificate '$CERT_NAME'"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Certificate removal cancelled."
        return
    fi
    
    info "Removing manual certificate: $CERT_NAME"
    
    # Remove certificate files
    [[ -f "$cert_file" ]] && rm -f "$cert_file"
    [[ -f "$key_file" ]] && rm -f "$key_file"
    
    # Restart Traefik
    info "Restarting Traefik..."
    (cd "${FORTRESS_PROXY_DIR}" && ${DOCKER_COMPOSE_COMMAND} -p "fortress_proxy" restart)
    
    success "Certificate '$CERT_NAME' removed successfully"
}

function sslList() {
    info "Listing all SSL certificates"
    echo ""
    
    local acme_file="${FORTRESS_PROXY_DIR}/acme.json"
    local certs_dir="${FORTRESS_PROXY_DIR}/certs"
    
    echo "=== Let's Encrypt Certificates ==="
    if [[ -f "$acme_file" ]] && command -v jq >/dev/null 2>&1; then
        local domains=$(jq -r '.letsencrypt.Certificates[]? | .domain.main' "$acme_file" 2>/dev/null)
        if [[ -n "$domains" ]]; then
            echo "$domains" | while read -r domain; do
                if [[ -n "$domain" ]]; then
                    # Get certificate expiry if possible
                    local expiry=$(jq -r --arg domain "$domain" '.letsencrypt.Certificates[] | select(.domain.main == $domain) | .certificate' "$acme_file" 2>/dev/null | base64 -d | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")
                    echo "  $domain (expires: $expiry)"
                fi
            done
        else
            echo "  None found"
        fi
    else
        echo "  Cannot read acme.json (file missing or jq not available)"
    fi
    
    echo ""
    echo "=== Manual Certificates ==="
    if [[ -d "$certs_dir" ]] && [[ -n "$(ls -A "$certs_dir" 2>/dev/null)" ]]; then
        for cert_file in "$certs_dir"/*.crt; do
            if [[ -f "$cert_file" ]]; then
                local cert_name=$(basename "$cert_file" .crt)
                local expiry=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")
                local subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject= *//' || echo "Unknown")
                echo "  $cert_name (expires: $expiry)"
                echo "    Subject: $subject"
            fi
        done
    else
        echo "  None found"
    fi
}

case "${SUBCOMMAND}" in
    status)
        sslStatus
        ;;
    renew)
        sslRenew
        ;;
    add)
        sslAdd
        ;;
    remove)
        sslRemove
        ;;
    list)
        sslList
        ;;
    --help|-h)
        cat << 'EOF'
Usage: fortress ssl <COMMAND> [OPTIONS]

Manage SSL certificates for Fortress.

COMMANDS:
  status              Show SSL certificate status (default)
  list                List all SSL certificates with details
  renew <domain>      Renew Let's Encrypt certificate for domain
  add <cert> <key> [name]  Add manual SSL certificate
  remove <name>       Remove manual SSL certificate

EXAMPLES:
  fortress ssl status                    # Show certificate status
  fortress ssl list                     # List all certificates  
  fortress ssl renew example.com        # Renew Let's Encrypt cert for example.com
  fortress ssl add cert.crt cert.key    # Add manual certificate
  fortress ssl remove mycert             # Remove manual certificate

NOTES:
  - Let's Encrypt certificates are managed automatically by Traefik
  - Manual certificates should be placed in the proxy/certs directory
  - Traefik will be restarted when adding/removing manual certificates
  - For Let's Encrypt renewals, ensure your domain points to this server

EOF
        ;;
    *)
        fatal "ssl: Unknown command '${SUBCOMMAND}'. Use 'fortress ssl --help'."
        ;;
esac