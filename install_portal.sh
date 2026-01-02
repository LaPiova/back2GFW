#!/bin/bash
#
# install_portal.sh - Xray Reverse Proxy Portal (Overseas Node)
# 
# This script sets up the PUBLIC-facing Xray node that:
#   1. Accepts user connections via VLESS + Vision + REALITY (Port 443)
#   2. Accepts Bridge (China) connections via gRPC (Port 8443)
#   3. Routes user traffic through the reverse tunnel to China
#
# Usage: curl -fsSL <url> | bash
#        or: bash install_portal.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/xray-portal"
REALITY_DEST="www.microsoft.com:443"
REALITY_SERVER_NAMES='["www.microsoft.com","microsoft.com"]'

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Xray Reverse Proxy - Portal (Overseas) Installer       ║"
echo "║                                                              ║"
echo "║  This script will install the overseas entry point that:    ║"
echo "║  • Accepts user connections (VLESS+Reality on 443)          ║"
echo "║  • Accepts bridge connections (gRPC on 8443)                ║"
echo "║  • Routes traffic through the reverse tunnel                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

#######################################
# Install Docker if not present
#######################################
install_docker() {
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✓ Docker already installed${NC}"
        return
    fi
    
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}✓ Docker installed successfully${NC}"
}

#######################################
# Install Docker Compose if not present
#######################################
install_docker_compose() {
    if docker compose version &> /dev/null; then
        echo -e "${GREEN}✓ Docker Compose already installed${NC}"
        return
    fi
    
    echo -e "${YELLOW}Installing Docker Compose plugin...${NC}"
    # Try multiple methods
    if apt-get update -qq && apt-get install -y docker-compose-plugin 2>/dev/null; then
        echo -e "${GREEN}✓ Docker Compose installed via apt${NC}"
    else
        echo -e "${YELLOW}Installing Docker Compose standalone...${NC}"
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
        curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        echo -e "${GREEN}✓ Docker Compose installed standalone${NC}"
    fi
}

#######################################
# Generate cryptographic credentials
#######################################
generate_credentials() {
    echo -e "${YELLOW}Generating cryptographic credentials...${NC}"
    
    # Generate UUIDs
    USER_UUID=$(cat /proc/sys/kernel/random/uuid)
    BRIDGE_UUID=$(cat /proc/sys/kernel/random/uuid)
    
    # Generate REALITY x25519 keypair using xray binary in Docker
    echo -e "${YELLOW}Generating REALITY x25519 keypair...${NC}"
    
    # Get the raw output first
    KEYS_OUTPUT=$(docker run --rm ghcr.io/xtls/xray-core x25519 2>&1)
    echo -e "${CYAN}Xray x25519 output:${NC}"
    echo "$KEYS_OUTPUT"
    
    # Parse the keys - handle multiple output formats:
    # Format 1: "Private key: xxxxx" (with space)
    # Format 2: "PrivateKey:xxxxx" (no space, CamelCase)
    # We need to extract just the key value (after the colon)
    
    # Use sed to remove everything up to and including the last colon and any spaces
    PRIVATE_KEY=$(echo "$KEYS_OUTPUT" | grep -i "private" | sed 's/^[^:]*://' | tr -d '[:space:]')
    PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep -i "public" | sed 's/^[^:]*://' | tr -d '[:space:]')
    
    # Debug output
    echo -e "${CYAN}Parsed Private Key: [${PRIVATE_KEY}]${NC}"
    echo -e "${CYAN}Parsed Public Key: [${PUBLIC_KEY}]${NC}"
    
    # Validate keys are not empty
    if [[ -z "$PRIVATE_KEY" ]] || [[ -z "$PUBLIC_KEY" ]]; then
        echo -e "${RED}✗ Failed to generate x25519 keys${NC}"
        echo -e "${RED}Raw output was: $KEYS_OUTPUT${NC}"
        exit 1
    fi
    
    # Validate keys don't still contain colon (prefix leak)
    if [[ "$PRIVATE_KEY" == *":"* ]] || [[ "$PRIVATE_KEY" == *"Private"* ]] || [[ "$PRIVATE_KEY" == *"Key"* ]]; then
        echo -e "${RED}✗ Key parsing error - extracted key still contains prefix${NC}"
        echo -e "${RED}Private key was: $PRIVATE_KEY${NC}"
        exit 1
    fi
    
    # Generate ShortId (8 hex characters)
    SHORT_ID=$(openssl rand -hex 4)
    
    echo -e "${GREEN}✓ Credentials generated${NC}"
}

#######################################
# Create Xray configuration
#######################################
create_config() {
    echo -e "${YELLOW}Creating Xray configuration...${NC}"
    
    mkdir -p "$INSTALL_DIR"
    
    # Create config without comments (pure JSON)
    cat > "$INSTALL_DIR/config.json" << EOFCONFIG
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "tag": "inbound-user",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${USER_UUID}",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "dest": "${REALITY_DEST}",
                    "serverNames": ${REALITY_SERVER_NAMES},
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": ["${SHORT_ID}"]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        },
        {
            "tag": "inbound-bridge",
            "port": 8443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "${BRIDGE_UUID}"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "grpc",
                "grpcSettings": {
                    "serviceName": "tunnel"
                },
                "security": "none"
            }
        }
    ],
    "reverse": {
        "portals": [
            {
                "tag": "portal",
                "domain": "reverse.internal"
            }
        ]
    },
    "outbounds": [
        {
            "tag": "direct",
            "protocol": "freedom"
        },
        {
            "tag": "blocked",
            "protocol": "blackhole"
        }
    ],
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "inboundTag": ["inbound-user"],
                "outboundTag": "portal"
            },
            {
                "type": "field",
                "inboundTag": ["inbound-bridge"],
                "outboundTag": "portal"
            }
        ]
    }
}
EOFCONFIG

    echo -e "${GREEN}✓ Configuration created at $INSTALL_DIR/config.json${NC}"
}

#######################################
# Create Docker Compose file
#######################################
create_docker_compose() {
    echo -e "${YELLOW}Creating Docker Compose file...${NC}"
    
    cat > "$INSTALL_DIR/docker-compose.yml" << 'EOF'
services:
  xray:
    image: ghcr.io/xtls/xray-core:latest
    container_name: xray-portal
    restart: always
    network_mode: host
    volumes:
      - ./config.json:/etc/xray/config.json:ro
    command: ["run", "-c", "/etc/xray/config.json"]
EOF

    echo -e "${GREEN}✓ Docker Compose file created${NC}"
}

#######################################
# Start the container
#######################################
start_container() {
    echo -e "${YELLOW}Starting Xray container...${NC}"
    
    cd "$INSTALL_DIR"
    docker compose down 2>/dev/null || true
    docker compose up -d
    
    sleep 3
    
    # Check if container is running
    if docker ps --format '{{.Names}}' | grep -q "xray-portal"; then
        echo -e "${GREEN}✓ Xray container is running${NC}"
        echo -e "${CYAN}Recent logs:${NC}"
        docker compose logs --tail=5
    else
        echo -e "${RED}✗ Container failed to start. Check logs:${NC}"
        docker compose logs --tail=20
        exit 1
    fi
}

#######################################
# Display credentials
#######################################
display_credentials() {
    # Get server IP
    SERVER_IP=$(curl -s4 ifconfig.me 2>/dev/null || curl -s4 icanhazip.com 2>/dev/null || echo "YOUR_SERVER_IP")
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    INSTALLATION COMPLETE                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Portal is running on: ${SERVER_IP}:443${NC}"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  SAVE THESE CREDENTIALS - NEEDED FOR BRIDGE & CLIENT SETUP  ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}[Portal Server Info]${NC}"
    echo -e "  Server IP:      ${GREEN}${SERVER_IP}${NC}"
    echo -e "  User Port:      ${GREEN}443${NC}"
    echo -e "  Bridge Port:    ${GREEN}8443${NC}"
    echo ""
    echo -e "${BLUE}[User Connection (for Client Apps)]${NC}"
    echo -e "  UUID:           ${GREEN}${USER_UUID}${NC}"
    echo -e "  Public Key:     ${GREEN}${PUBLIC_KEY}${NC}"
    echo -e "  Short ID:       ${GREEN}${SHORT_ID}${NC}"
    echo -e "  SNI:            ${GREEN}www.microsoft.com${NC}"
    echo ""
    echo -e "${BLUE}[Bridge Connection (for install_bridge.sh)]${NC}"
    echo -e "  Bridge UUID:    ${GREEN}${BRIDGE_UUID}${NC}"
    echo ""
    
    # Generate VLESS link for user
    VLESS_LINK="vless://${USER_UUID}@${SERVER_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#Portal-${SERVER_IP}"
    
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                     VLESS CLIENT LINK                         ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${GREEN}${VLESS_LINK}${NC}"
    echo ""
    echo -e "${CYAN}Import this link into Shadowrocket, v2rayN, or other clients.${NC}"
    echo ""
    
    # Save credentials to file
    cat > "$INSTALL_DIR/credentials.txt" << EOFCREDS
=== Xray Portal Credentials ===
Generated: $(date)

[Portal Server Info]
Server IP:      ${SERVER_IP}
User Port:      443
Bridge Port:    8443

[User Connection (for Client Apps)]
UUID:           ${USER_UUID}
Public Key:     ${PUBLIC_KEY}
Short ID:       ${SHORT_ID}
SNI:            www.microsoft.com

[Bridge Connection (for install_bridge.sh)]
Bridge UUID:    ${BRIDGE_UUID}

[VLESS Link]
${VLESS_LINK}

=== Copy these values to install_bridge.sh ===
PORTAL_IP="${SERVER_IP}"
PORTAL_GRPC_PORT="8443"
BRIDGE_UUID="${BRIDGE_UUID}"
EOFCREDS

    echo -e "${CYAN}Credentials saved to: ${INSTALL_DIR}/credentials.txt${NC}"
    echo ""
}

#######################################
# Main
#######################################
main() {
    # Check root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
    
    install_docker
    install_docker_compose
    generate_credentials
    create_config
    create_docker_compose
    start_container
    display_credentials
    
    echo -e "${GREEN}Portal installation complete!${NC}"
    echo -e "${YELLOW}Next step: Run install_bridge.sh on your China server${NC}"
}

main "$@"
