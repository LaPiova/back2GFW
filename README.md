# Back to China (Back2GFW) - Xray Reverse Proxy VPN

A high-stealth VPN solution for accessing China-only content from overseas. Uses Xray's `reverse` module to bypass strict inbound firewall rules on the domestic server.

## 🔐 Security Features

- **Zero Inbound Ports on China Server**: The domestic node acts purely as a client, making only outbound connections
- **VLESS + Vision + REALITY**: State-of-the-art protocol that looks like legitimate HTTPS traffic
- **gRPC Tunnel**: Persistent connection that resembles microservice traffic to cloud providers

## 🏗️ Architecture

```
┌─────────────────┐       ┌──────────────────────────────────────┐       ┌─────────────────┐
│                 │       │          OVERSEAS NODE               │       │   CHINA NODE    │
│  📱 User        │       │         (Portal)                     │       │    (Bridge)     │
│  (Client)       │       │                                      │       │                 │
│                 │       │  ┌─────────────────────────────────┐ │       │  ┌───────────┐  │
│  Shadowrocket   │──────▶│  │ VLESS+Reality (Port 443)       │ │◀──────│  │ gRPC Out  │  │
│  v2rayN         │ VLESS │  │ User Inbound                    │ │ gRPC  │  │ (Bridge)  │  │
│  Clash          │ +TLS  │  └─────────────────────────────────┘ │Tunnel │  └───────────┘  │
│                 │       │              │                       │       │        │        │
└─────────────────┘       │              ▼                       │       │        ▼        │
                          │  ┌─────────────────────────────────┐ │       │  ┌───────────┐  │
                          │  │ Reverse Portal                  │ │       │  │  Direct   │  │
                          │  │ Routes traffic through tunnel   │ │       │  │  Exit     │  │
                          │  └─────────────────────────────────┘ │       │  └───────────┘  │
                          │                                      │       │        │        │
                          └──────────────────────────────────────┘       │        ▼        │
                                                                         │  🇨🇳 China     │
                                                                         │    Internet     │
                                                                         └─────────────────┘
```

**Traffic Flow:**
1. User connects to Overseas Portal via VLESS + Vision + REALITY (Port 443)
2. China Bridge maintains persistent gRPC tunnel to Portal (outbound only)
3. Portal routes user traffic through tunnel to Bridge
4. Bridge exits traffic to China internet

## 📋 Prerequisites

- **Overseas Server**: VPS with public IP (any provider: DigitalOcean, Vultr, etc.)
- **China Server**: VPS behind NAT (Aliyun, Tencent Cloud, etc.) - no public ports needed
- Both servers: Ubuntu 20.04+ or Debian 11+ (other distros may work)
- Root access on both servers

## 🚀 Quick Start

### Step 1: Deploy Portal (Overseas Server)

```bash
# SSH into your overseas server
ssh root@your-overseas-ip

# Download and run the installer
curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/back2GFW/main/install_portal.sh | bash

# Or clone and run locally
git clone https://github.com/YOUR_REPO/back2GFW.git
cd back2GFW
chmod +x install_portal.sh
./install_portal.sh
```

**Save the output!** You'll need these values:
- Server IP
- User UUID
- Public Key
- Short ID
- Bridge UUID
- VLESS Link

### Step 2: Deploy Bridge (China Server)

```bash
# SSH into your China server
ssh root@your-china-ip

# Download and run the installer
curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/back2GFW/main/install_bridge.sh | bash

# When prompted, enter the credentials from Step 1:
# - Portal IP
# - Bridge UUID
```

### Step 3: Configure Client

Import the VLESS link from Step 1 into your client app:

**Supported Clients:**
- iOS: Shadowrocket, Quantumult X, Surge
- Android: v2rayNG, Clash for Android
- Windows: v2rayN, Clash for Windows
- macOS: ClashX, V2rayU
- Linux: v2rayA, Qv2ray

## 📝 VLESS Link Format

```
vless://UUID@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp&headerType=none#Portal
```

**Parameters:**
| Parameter | Value | Description |
|-----------|-------|-------------|
| UUID | (from portal) | User authentication ID |
| SERVER_IP | Portal IP | Overseas server address |
| Port | 443 | Standard HTTPS port |
| flow | xtls-rprx-vision | XTLS Vision flow |
| security | reality | REALITY protocol |
| sni | www.microsoft.com | Server Name Indication |
| fp | chrome | Fingerprint |
| pbk | (from portal) | REALITY public key |
| sid | (from portal) | Short ID |

## 🔧 Management Commands

### Portal (Overseas)

```bash
cd /opt/xray-portal

# View logs
docker compose logs -f

# Restart
docker compose restart

# Stop
docker compose down

# View credentials
cat credentials.txt
```

### Bridge (China)

```bash
cd /opt/xray-bridge

# View logs
docker compose logs -f

# Restart
docker compose restart

# Stop
docker compose down
```

## 🛡️ Security Considerations

1. **Firewall**: Only port 443 and 8443 need to be open on the Portal
2. **China Server**: Ensure NO inbound ports are exposed publicly
3. **Credentials**: Store `credentials.txt` securely, delete after setup if desired
4. **SNI**: Using Microsoft's domain helps avoid detection
5. **Updates**: Regularly update Xray-core for security patches

## 🔍 Troubleshooting

### Bridge can't connect to Portal

```bash
# Check if Portal is running
curl -v https://PORTAL_IP:443 --insecure

# Check Bridge logs
cd /opt/xray-bridge && docker compose logs

# Verify gRPC port is accessible
nc -zv PORTAL_IP 8443
```

### Client can't connect

1. Verify the VLESS link is complete (no truncation)
2. Check if Portal port 443 is open: `nc -zv PORTAL_IP 443`
3. Try a different client app
4. Check Portal logs for errors

### Slow speeds

1. Check server bandwidth limits
2. Try disabling sniffing in config
3. Consider using a closer overseas server location

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.

## ⚠️ Disclaimer

This tool is for educational and legitimate privacy purposes only. Users are responsible for complying with local laws and regulations. The authors are not responsible for any misuse.