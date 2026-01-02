#!/bin/bash
#
# install_bridge.sh - Xray Reverse Proxy Bridge (Domestic China Node)
# 
# This script sets up the DOMESTIC node that:
#   1. Has ZERO inbound ports open (pure client mode)
#   2. Connects OUTBOUND to the Portal via gRPC
#   3. Routes traffic to target China websites
#
# Usage: curl -fsSL <url> | bash
#        or: bash install_bridge.sh
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
INSTALL_DIR="/opt/xray-bridge"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║      Xray Reverse Proxy - Bridge (China) Installer          ║"
echo "║                                                              ║"
echo "║  This script will install the domestic node that:           ║"
echo "║  • Opens ZERO inbound ports (stealth mode)                  ║"
echo "║  • Connects OUTBOUND to the Portal via gRPC                 ║"
echo "║  • Routes traffic to China destinations                      ║"
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
    
    # Try different methods for China
    if curl -fsSL https://get.docker.com | sh; then
        echo -e "${GREEN}✓ Docker installed via get.docker.com${NC}"
    else
        echo -e "${YELLOW}Trying Aliyun mirror...${NC}"
        curl -fsSL https://get.docker.com | sh -s -- --mirror Aliyun
    fi
    
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
# Prompt for Portal credentials
#######################################
prompt_credentials() {
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Enter the credentials from install_portal.sh output          ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Portal IP
    while true; do
        read -rp "Portal Server IP/Domain: " PORTAL_IP
        if [[ -n "$PORTAL_IP" ]]; then
            break
        fi
        echo -e "${RED}Portal IP cannot be empty${NC}"
    done
    
    # Portal gRPC Port (default 8443)
    read -rp "Portal gRPC Port [8443]: " PORTAL_GRPC_PORT
    PORTAL_GRPC_PORT=${PORTAL_GRPC_PORT:-8443}
    
    # Bridge UUID
    while true; do
        read -rp "Bridge UUID: " BRIDGE_UUID
        if [[ "$BRIDGE_UUID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
            break
        fi
        echo -e "${RED}Invalid UUID format. Should be like: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx${NC}"
    done
    
    echo ""
    echo -e "${GREEN}✓ Credentials received${NC}"
    echo -e "  Portal:      ${PORTAL_IP}:${PORTAL_GRPC_PORT}"
    echo -e "  Bridge UUID: ${BRIDGE_UUID}"
    echo ""
    
    read -rp "Confirm and continue? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        echo "Aborted."
        exit 1
    fi
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
    // Xray Bridge Configuration (Domestic China Node)
    // ============================================================
    // This node acts as:
    //   1. Outbound-only client (ZERO inbound ports)
    //   2. Reverse bridge - tunnels back to Portal
    //   3. Exit point for traffic to China destinations
    // ============================================================
    
    "log": {
        "loglevel": "warning",
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log"
    },
    
    // ============================================================
    // NO INBOUNDS - This is the stealth feature!
    // The bridge only makes OUTBOUND connections
    // ============================================================
    "inbounds": [],
    
    // ============================================================
    // Reverse Proxy: Bridge Definition
    // - tag: identifies this bridge (routes traffic here)
    // - domain: virtual domain for routing (must match portal)
    // ============================================================
    "reverse": {
        "bridges": [
            {
                "tag": "bridge",
                "domain": "reverse.internal"
            }
        ]
    },
    
    "outbounds": [
        // ----------------------------------------------------
        // Outbound 1: Tunnel to Portal (gRPC)
        // This establishes the reverse tunnel connection
        // Bridge -> Portal via gRPC, persistent connection
        // ----------------------------------------------------
        {
            "tag": "tunnel",
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "${PORTAL_IP}",
                        "port": ${PORTAL_GRPC_PORT},
                        "users": [
                            {
                                "id": "${BRIDGE_UUID}",
                                "encryption": "none"
                            }
                        ]
                    }
                ]
            },
            "streamSettings": {
                "network": "grpc",
                "grpcSettings": {
                    "serviceName": "tunnel"
                },
                "security": "none"
            }
        },
        
        // ----------------------------------------------------
        // Outbound 2: Freedom (direct exit to China internet)
        // This is where user traffic actually exits
        // ----------------------------------------------------
        {
            "tag": "direct",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4"
            }
        },
        
        // ----------------------------------------------------
        // Outbound 3: Blackhole (block unwanted traffic)
        // ----------------------------------------------------
        {
            "tag": "blocked",
            "protocol": "blackhole"
        }
    ],
    
    // ============================================================
    // Routing Rules
    // - Bridge tunnel traffic -> tunnel outbound (to Portal)
    // - User traffic (from tunnel) -> direct (to China sites)
    // ============================================================
    "routing": {
        "domainStrategy": "AsIs",
        "rules": [
            // Rule 1: Tunnel establishment traffic
            // The bridge communicates with portal via tunnel outbound
            {
                "type": "field",
                "inboundTag": ["bridge"],
                "outboundTag": "tunnel"
            },
            
            // Rule 2: User traffic exits directly to China
            // Traffic that comes through the reverse tunnel exits here
            {
                "type": "field",
                "inboundTag": ["bridge"],
                "domain": ["full:reverse.internal"],
                "outboundTag": "direct"
            }
        ]
    }
}
EOF

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
    container_name: xray-bridge
    restart: always
    # NOTE: No port mappings! This is outbound-only
    volumes:
      - ./config.json:/etc/xray/config.json:ro
      - ./logs:/var/log/xray
    command: ["run", "-c", "/etc/xray/config.json"]
    # DNS for China (use Aliyun DNS)
    dns:
      - 223.5.5.5
      - 223.6.6.6
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
    
    sleep 3
    
    if docker compose ps | grep -q "running"; then
        echo -e "${GREEN}✓ Xray container is running${NC}"
    else
        echo -e "${RED}✗ Container failed to start. Check logs:${NC}"
        docker compose logs
        exit 1
    fi
}

#######################################
# Verify tunnel connection
#######################################
verify_connection() {
    echo -e "${YELLOW}Verifying tunnel connection...${NC}"
    
    sleep 2
    
    cd "$INSTALL_DIR"
    
    # Check if there are any connection errors in logs
    if docker compose logs 2>&1 | grep -qi "error\|fail"; then
        echo -e "${YELLOW}⚠ Possible issues detected in logs:${NC}"
        docker compose logs --tail=10
    else
        echo -e "${GREEN}✓ No obvious errors in logs${NC}"
    fi
}

#######################################
# Display status
#######################################
display_status() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    INSTALLATION COMPLETE                     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}Bridge is running!${NC}"
    echo ""
    echo -e "${BLUE}[Connection Info]${NC}"
    echo -e "  Portal:         ${GREEN}${PORTAL_IP}:${PORTAL_GRPC_PORT}${NC}"
    echo -e "  Bridge UUID:    ${GREEN}${BRIDGE_UUID}${NC}"
    echo -e "  Inbound Ports:  ${GREEN}NONE (stealth mode)${NC}"
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                         NEXT STEPS                            ${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "1. On your client device, import the VLESS link from Portal"
    echo -e "2. Connect to the Portal (${PORTAL_IP}:443)"
    echo -e "3. Your traffic will route: Client -> Portal -> Bridge -> China"
    echo ""
    echo -e "${CYAN}Useful commands:${NC}"
    echo -e "  View logs:      ${GREEN}cd $INSTALL_DIR && docker compose logs -f${NC}"
    echo -e "  Restart:        ${GREEN}cd $INSTALL_DIR && docker compose restart${NC}"
    echo -e "  Stop:           ${GREEN}cd $INSTALL_DIR && docker compose down${NC}"
    echo ""
    
    # Save config info
    cat > "$INSTALL_DIR/connection_info.txt" << EOF
=== Xray Bridge Connection Info ===
Generated: $(date)

Portal:         ${PORTAL_IP}:${PORTAL_GRPC_PORT}
Bridge UUID:    ${BRIDGE_UUID}
Inbound Ports:  NONE (stealth mode)

Traffic Flow:
Client -> Portal (${PORTAL_IP}:443) -> Bridge -> China Destinations
EOF

    echo -e "${CYAN}Connection info saved to: ${INSTALL_DIR}/connection_info.txt${NC}"
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
    prompt_credentials
    create_config
    create_docker_compose
    start_container
    verify_connection
    display_status
    
    echo -e "${GREEN}Bridge installation complete!${NC}"
    echo -e "${YELLOW}The reverse tunnel should now be established.${NC}"
}

main "$@"
