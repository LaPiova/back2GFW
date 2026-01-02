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
REALITY_DEST="www.microsoft.com:443"  # SNI target for REALITY
REALITY_SERVER_NAMES="www.microsoft.com,microsoft.com"

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
    apt-get update -qq
    apt-get install -y docker-compose-plugin
    echo -e "${GREEN}✓ Docker Compose installed successfully${NC}"
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
    KEYS=$(docker run --rm ghcr.io/xtls/xray-core x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
    
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
    
    cat > "$INSTALL_DIR/config.json" << EOF
{
    // ============================================================
    // Xray Portal Configuration (Overseas Node)
    // ============================================================
    // This node acts as:
    //   1. Entry point for users (VLESS + REALITY)
    //   2. Rendezvous point for the Bridge (gRPC)
    //   3. Traffic router via reverse proxy
    // ============================================================
    
    "log": {
        "loglevel": "warning",
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log"
    },
    
    "inbounds": [
        // ----------------------------------------------------
        // Inbound 1: User-facing (VLESS + Vision + REALITY)
        // - Port 443 for stealth (looks like HTTPS)
        // - REALITY eliminates the need for certificates
        // - Vision flow for performance
        // ----------------------------------------------------
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
                    "serverNames": [${REALITY_SERVER_NAMES//,/\",\"}],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": ["${SHORT_ID}"]
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        },
        
        // ----------------------------------------------------
        // Inbound 2: Bridge connection (gRPC tunnel receiver)
        // - Port 8443 for internal tunnel
        // - Bridge connects here with its UUID
        // - This is the "tunnel endpoint" side of the portal
        // ----------------------------------------------------
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
    
    // ============================================================
    // Reverse Proxy: Portal Definition
    // - tag: identifies this portal
    // - domain: virtual domain for routing (must match bridge)
    // ============================================================
    "reverse": {
        "portals": [
            {
                "tag": "portal",
                "domain": "reverse.internal"
            }
        ]
    },
    
    "outbounds": [
        // ----------------------------------------------------
        // Outbound 1: Freedom (direct exit - not used normally)
        // ----------------------------------------------------
        {
            "tag": "direct",
            "protocol": "freedom"
        },
        
        // ----------------------------------------------------
        // Outbound 2: Blackhole (block unwanted traffic)
        // ----------------------------------------------------
        {
            "tag": "blocked",
            "protocol": "blackhole"
        }
    ],
    
    // ============================================================
    // Routing Rules
    // - User traffic -> Portal -> (tunneled to Bridge)
    // - Bridge tunnel traffic handled by reverse module
    // ============================================================
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            // Rule 1: Route user inbound to the portal (reverse tunnel)
            // This is the KEY rule: user traffic enters via inbound-user
            // and exits through the portal which tunnels it to the bridge
            {
                "type": "field",
                "inboundTag": ["inbound-user"],
                "outboundTag": "portal"
            },
            
            // Rule 2: Handle the bridge's tunnel connection
            // Traffic from the bridge establishes the reverse tunnel
            {
                "type": "field",
                "inboundTag": ["inbound-bridge"],
                "outboundTag": "portal"
            }
        ]
    }
}
EOF

    # Remove JSON comments (Xray supports them, but let's be safe)
    # Actually, Xray-core DOES support // comments natively, so we keep them
    
    echo -e "${GREEN}✓ Configuration created at $INSTALL_DIR/config.json${NC}"
}

#######################################
# Create Docker Compose file
#######################################
create_docker_compose() {
    echo -e "${YELLOW}Creating Docker Compose file...${NC}"
    
    cat > "$INSTALL_DIR/docker-compose.yml" << 'EOF'
version: "3.8"

services:
  xray:
    image: ghcr.io/xtls/xray-core:latest
    container_name: xray-portal
    restart: always
    network_mode: host
    volumes:
      - ./config.json:/etc/xray/config.json:ro
      - ./logs:/var/log/xray
    command: ["run", "-c", "/etc/xray/config.json"]
EOF

    mkdir -p "$INSTALL_DIR/logs"
    
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
    
    sleep 2
    
    if docker compose ps | grep -q "running"; then
        echo -e "${GREEN}✓ Xray container is running${NC}"
    else
        echo -e "${RED}✗ Container failed to start. Check logs:${NC}"
        docker compose logs
        exit 1
    fi
}

#######################################
# Display credentials
#######################################
display_credentials() {
    # Get server IP
    SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 icanhazip.com || echo "YOUR_SERVER_IP")
    
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
    cat > "$INSTALL_DIR/credentials.txt" << EOF
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
EOF

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
