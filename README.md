# OpenVPN + IBSng Auto Installer (Ubuntu)

This script installs and configures an OpenVPN server on Ubuntu and integrates it with the IBSng accounting system using the RADIUS plugin.

## Features

- Full OpenVPN server setup
- EasyRSA integration for certificate management
- RADIUS plugin configuration for IBSng
- Firewall and routing setup
- Client configuration file generator

## Requirements

- Ubuntu (not supported on version 16.04 and not suitable for > 22.04)
- Root privileges
- TUN device enabled

## Usage

1. Run the script using `bash`:
   ```bash
   bash <(curl -Ls https://raw.githubusercontent.com/mhdi-khosravi/openvpn-ibsng-ubuntu/main/install.sh)
   ```

2. Follow the on-screen instructions:
   - Enter your server's IP address
   - Choose protocol (UDP/TCP)
   - Enter the OpenVPN port
   - Provide IBSng server IP and secret
   - Specify setup mode (standalone or group)
   - Configure DNS
   - Enter client certificate name

3. The script will:
   - Download and setup EasyRSA
   - Generate server and client certificates
   - Configure OpenVPN with IBSng
   - Enable IP forwarding and firewall rules

4. Your client `.ovpn` file will be saved in your home directory.

## Note

- This script is only tested on Ubuntu (not CentOS).
- You must have an active IBSng server.
- Make sure ports are open on your firewall and NAT router.
