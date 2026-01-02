# Installation & Connection Guide

Complete step-by-step guide to deploy and connect your Back2GFW reverse proxy VPN.

---

## Prerequisites

### Overseas Server (Portal)
- ✅ Any VPS with public IP (DigitalOcean, Vultr, Linode, etc.)
- ✅ Ubuntu 20.04+ or Debian 11+
- ✅ Root/sudo access
- ✅ Ports 443 and 8443 open in firewall

### China Server (Bridge)  
- ✅ Any VPS (Aliyun, Tencent Cloud, etc.)
- ✅ Ubuntu 20.04+ or Debian 11+
- ✅ Root/sudo access
- ⛔ **NO inbound ports required** (this is the stealth feature!)

### Client Device
- ✅ Shadowrocket (iOS) / v2rayN (Windows) / v2rayNG (Android) / Clash

---

## Step 1: Deploy Portal (Overseas Server)

### 1.1 Connect to your overseas server

```bash
ssh root@YOUR_OVERSEAS_IP
```

### 1.2 Download and run the installer

**Option A: Direct execution**
```bash
curl -fsSL https://raw.githubusercontent.com/LaPiova/back2GFW/main/install_portal.sh -o install_portal.sh
chmod +x install_portal.sh
./install_portal.sh
```

**Option B: Clone repository**
```bash
git clone https://github.com/LaPiova/back2GFW.git
cd back2GFW
chmod +x install_portal.sh
./install_portal.sh
```

### 1.3 Save the output credentials

The script will display:
```
═══════════════════════════════════════════════════════════════
  SAVE THESE CREDENTIALS - NEEDED FOR BRIDGE & CLIENT SETUP  
═══════════════════════════════════════════════════════════════

[Portal Server Info]
  Server IP:      203.0.113.50
  User Port:      443
  Bridge Port:    8443

[User Connection (for Client Apps)]
  UUID:           a1b2c3d4-e5f6-7890-abcd-ef1234567890
  Public Key:     Abc123XyzPublicKeyHere...
  Short ID:       1a2b3c4d

[Bridge Connection (for install_bridge.sh)]
  Bridge UUID:    f0e1d2c3-b4a5-6789-0fed-cba987654321

═══════════════════════════════════════════════════════════════
                     VLESS CLIENT LINK                         
═══════════════════════════════════════════════════════════════

vless://a1b2c3d4-e5f6-7890-abcd-ef1234567890@203.0.113.50:443?...
```

> ⚠️ **IMPORTANT**: Copy the credentials to a secure location. You'll need them for Step 2 and Step 3.

Credentials are also saved to: `/opt/xray-portal/credentials.txt`

---

## Step 2: Deploy Bridge (China Server)

### 2.1 Connect to your China server

```bash
ssh root@YOUR_CHINA_SERVER_IP
```

### 2.2 Download and run the installer

```bash
curl -fsSL https://raw.githubusercontent.com/LaPiova/back2GFW/main/install_bridge.sh -o install_bridge.sh
chmod +x install_bridge.sh
./install_bridge.sh
```

### 2.3 Enter the credentials when prompted

The script will ask for:
```
Portal Server IP/Domain: 203.0.113.50
Portal gRPC Port [8443]: (press Enter for default)
Bridge UUID: f0e1d2c3-b4a5-6789-0fed-cba987654321
```

### 2.4 Verify the tunnel is established

```bash
cd /opt/xray-bridge
docker compose logs -f
```

You should see the bridge connecting to the portal without errors.

---

## Step 3: Configure Client

### 3.1 Copy the VLESS link

From Step 1, copy the full VLESS link:
```
vless://UUID@SERVER_IP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp&headerType=none#Portal
```

### 3.2 Import into your client app

#### iOS (Shadowrocket)
1. Open Shadowrocket
2. Tap `+` → `Type: Subscribe`
3. Paste the VLESS link
4. Tap `Done`
5. Toggle the connection switch ON

#### Windows (v2rayN)
1. Open v2rayN
2. Click `Servers` → `Import bulk URLs from clipboard`
3. Paste the VLESS link
4. Right-click the server → `Set as active server`
5. Click the system proxy button to enable

#### Android (v2rayNG)
1. Open v2rayNG
2. Tap `+` → `Import config from clipboard`
3. Paste the VLESS link
4. Tap the server to select it
5. Tap the play button to connect

#### macOS/Linux (Clash/v2rayA)
1. Create a Clash config or use v2rayA web UI
2. Add the VLESS server manually with parameters from the link

---

## Step 4: Verify Connection

### Test from client
1. Connect to the VPN in your client app
2. Visit: https://www.ip.cn or https://ip.sb
3. Your IP should show a **China** location

### Test traffic flow
```
📱 Client → 🌍 Portal (Overseas) → 🇨🇳 Bridge (China) → 🎯 Target Site
```

---

## Troubleshooting

### Bridge won't connect to Portal

```bash
# On China server - check logs
cd /opt/xray-bridge && docker compose logs --tail=50

# Verify Portal is reachable (run from China server)
curl -v https://PORTAL_IP:443 --insecure
nc -zv PORTAL_IP 8443
```

**Common causes:**
- Portal firewall blocking port 8443
- Incorrect Bridge UUID
- Portal not running

### Client won't connect

```bash
# On Portal server - check logs
cd /opt/xray-portal && docker compose logs --tail=50
```

**Common causes:**
- Incomplete VLESS link (truncated when copying)
- Wrong UUID or Public Key
- Portal port 443 blocked

### Slow speeds

1. Check server bandwidth limits in your VPS dashboard
2. Try a Portal location closer to you
3. Ensure both servers have adequate CPU/RAM

---

## Management Commands

### Portal (Overseas)
```bash
cd /opt/xray-portal

docker compose logs -f      # View live logs
docker compose restart      # Restart service
docker compose down         # Stop service
docker compose up -d        # Start service
cat credentials.txt         # View saved credentials
```

### Bridge (China)
```bash
cd /opt/xray-bridge

docker compose logs -f      # View live logs
docker compose restart      # Restart service
docker compose down         # Stop service
docker compose up -d        # Start service
```

---

## Security Tips

1. **Delete credentials.txt** after setup if you've saved them elsewhere
2. **Use strong firewall rules** - only open necessary ports on Portal
3. **Update regularly**: `docker compose pull && docker compose up -d`
4. **Monitor logs** for unusual activity

---

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Review logs on both servers
3. Open an issue on GitHub with:
   - Error messages from logs
   - Your setup (server providers, OS versions)
   - Steps you've taken
