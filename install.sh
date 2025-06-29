#!/bin/bash
#
# Powerd By Mr-Amwer
# This script enables duplicate-cn in server.conf. You can share the same client.ovpn file for multiple users.
# Based on Nyr https://github.com/gayankuruppu/openvpn-install-for-multiple-users

# checks if ubuntu is 1604
if grep -qs "Ubuntu 16.04" "/etc/os-release"; then
    echo 'Ubuntu 16.04 is no longer supported'
    exit
fi

# cehcks if run in bash
if readlink /proc/$$/exe | grep -q "dash"; then
    echo "This script needs to be run with bash, not sh"
    echo "Run This script by bash to fix this problem"
    exit
fi

# checks if run in root
if [[ "$EUID" -ne 0 ]]; then
    echo "Run this as root"
    exit
fi

# checks if tun device is enabled
if [[ ! -e /dev/net/tun ]]; then
    echo "The TUN device is not enabled"
    exit
fi

# checks the operating system version
if [[ -e /etc/debian_version ]]; then
    OS=debian
    GROUPNAME=nogroup
elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
    OS=centos
    GROUPNAME=nobody
else
    echo "This script only works on Debian, Ubuntu or CentOS"
    exit
fi

newclient() {
    # Generates the custom client.ovpn
    cp /etc/openvpn/server/client-common.txt ~/$1.ovpn
    echo "<ca>" >>~/$1.ovpn
    cat /etc/openvpn/server/easy-rsa/pki/ca.crt >>~/$1.ovpn
    echo "</ca>" >>~/$1.ovpn
    echo "<cert>" >>~/$1.ovpn
    sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/server/easy-rsa/pki/issued/$1.crt >>~/$1.ovpn
    echo "</cert>" >>~/$1.ovpn
    echo "<key>" >>~/$1.ovpn
    cat /etc/openvpn/server/easy-rsa/pki/private/$1.key >>~/$1.ovpn
    echo "</key>" >>~/$1.ovpn
    echo "<tls-auth>" >>~/$1.ovpn
    sed -ne '/BEGIN OpenVPN Static key/,$ p' /etc/openvpn/server/ta.key >>~/$1.ovpn
    echo "</tls-auth>" >>~/$1.ovpn
}

if [[ -e /etc/openvpn/server/server.conf ]]; then
    echo "OpenVPN is already installed"
    echo
    echo "Still you can't connect multiple users to the OpenVPN server?"
    echo "Restart the server!"
    echo
    exit
else
    clear
    echo 'Install OpenVPN for Multiple Users'
    echo
    # OpenVPN setup and first user creation
    echo "Listening to IPv4 Address."
    # Autodetect IP address and pre-fill for the user
    IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
    read -p "IP address: " -e -i $IP IP
    # If $IP is a private IP address, the server must be behind NAT
    if echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
        echo
        echo "Enter Public IPv4 Address"
        read -p "Public IP Address: " -e PUBLICIP
    fi
    echo
    echo "Choose OpenVPN Protocol (default UDP):"
    echo "   1) UDP (recommended)"
    echo "   2) TCP"
    read -p "Protocol [1-2]: " -e -i 1 PROTOCOL
    case $PROTOCOL in
    1)
        PROTOCOL=udp
        ;;
    2)
        PROTOCOL=tcp
        ;;
    esac
    echo
    echo "Enter OpenVPN Port (default 1194)"
    read -p "Port: " -e -i 1194 PORT
    echo
    echo "Enter Radius server ip  "
    read -p "Radius IP : " -e -i 192.168.1.1 RADIUSIP
    echo
    echo "Enter Radius server password  "
    read -p "Radius pass : " -e -i 125 RADIUSPASS
    echo
    echo "if you want the current server to be setup independently, enter option 1, otherwise enter the name of the server group "
    read -p "Server group or option 1 : " -e -i 1 SETUPTYPE
    if [ "$SETUPTYPE" = "1" ]; then
        echo "Choose DNS for VPN (default System)"
        echo "   1) Current system resolvers"
        echo "   2) 1.1.1.1"
        echo "   3) Google"
        echo "   4) OpenDNS"
        echo "   5) Verisign"
        read -p "DNS [1-5]: " -e -i 2 DNS
        echo
        echo "Enter the name Client Certificate (One Word)"
        read -p "Client name: " -e -i client CLIENT
        echo
        echo "Please wait few minutes"
        read -n1 -r -p "Press any key to continue..."
        # If running inside a container, disable LimitNPROC to prevent conflicts
        if systemd-detect-virt -cq; then
            mkdir /etc/systemd/system/openvpn-server@server.service.d/ 2>/dev/null
            echo '[Service]
LimitNPROC=infinity' >/etc/systemd/system/openvpn-server@server.service.d/disable-limitnproc.conf
        fi
        if [[ "$OS" = 'debian' ]]; then
            apt-get update
            apt-get install openvpn iptables openssl ca-certificates -y
        else
            # Else, the distro is CentOS
            yum install epel-release -y
            yum install openvpn iptables openssl ca-certificates -y
        fi
        # Get easy-rsa
        EASYRSAURL="https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.5/EasyRSA-nix-3.0.5.tgz"
        wget -O ~/easyrsa.tgz "$EASYRSAURL" 2>/dev/null || curl -Lo ~/easyrsa.tgz "$EASYRSAURL"
        tar xzf ~/easyrsa.tgz -C ~/
        mv ~/EasyRSA-3.0.5/ /etc/openvpn/server/
        mv /etc/openvpn/server/EasyRSA-3.0.5/ /etc/openvpn/server/easy-rsa/
        chown -R root:root /etc/openvpn/server/easy-rsa/
        rm -f ~/easyrsa.tgz
        cd /etc/openvpn/server/easy-rsa/
        # Create the PKI, set up the CA and the server and client certificates
        ./easyrsa init-pki
        ./easyrsa --batch build-ca nopass
        EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-server-full server nopass
        EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full $CLIENT nopass
        EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
        # Move the stuff we need
        cp pki/ca.crt pki/private/ca.key pki/issued/server.crt pki/private/server.key pki/crl.pem /etc/openvpn/server
        # CRL is read with each client connection, when OpenVPN is dropped to nobody
        chown nobody:$GROUPNAME /etc/openvpn/server/crl.pem
        # Generate key for tls-auth
        openvpn --genkey --secret /etc/openvpn/server/ta.key
        # Create the DH parameters file using the predefined ffdhe2048 group
        echo '-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA//////////+t+FRYortKmq/cViAnPTzx2LnFg84tNpWp4TZBFGQz
+8yTnc4kmz75fS/jY2MMddj2gbICrsRhetPfHtXV/WVhJDP1H18GbtCFY2VVPe0a
87VXE15/V8k1mE8McODmi3fipona8+/och3xWKE2rec1MKzKT0g6eXq8CrGCsyT7
YdEIqUuyyOP7uWrat2DX9GgdT0Kj3jlN9K5W7edjcrsZCwenyO4KbXCeAvzhzffi
7MA0BM0oNC9hkXL+nOmFg/+OTxIy7vKBg8P+OxtMb61zO7X8vC7CIAXFjvGDfRaD
ssbzSibBsu/6iGtCOGEoXJf//////////wIBAg==
-----END DH PARAMETERS-----' >/etc/openvpn/server/dh.pem
        # Generate server.conf
        echo "port $PORT
proto $PROTOCOL
dev tun
sndbuf 0
rcvbuf 0
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA512
tls-auth ta.key 0
topology subnet
server 10.8.0.0 255.255.0.0
ifconfig-pool-persist ipp.txt" >/etc/openvpn/server/server.conf
        echo 'push "redirect-gateway def1 bypass-dhcp"' >>/etc/openvpn/server/server.conf
        # DNS
        case $DNS in
        1)
            # Locate the proper resolv.conf
            # Needed for systems running systemd-resolved
            if grep -q "127.0.0.53" "/etc/resolv.conf"; then
                RESOLVCONF='/run/systemd/resolve/resolv.conf'
            else
                RESOLVCONF='/etc/resolv.conf'
            fi
            # Obtain the resolvers from resolv.conf and use them for OpenVPN
            grep -v '#' $RESOLVCONF | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
                echo "push \"dhcp-option DNS $line\"" >>/etc/openvpn/server/server.conf
            done
            ;;
        2)
            echo 'push "dhcp-option DNS 1.1.1.1"' >>/etc/openvpn/server/server.conf
            echo 'push "dhcp-option DNS 1.0.0.1"' >>/etc/openvpn/server/server.conf
            ;;
        3)
            echo 'push "dhcp-option DNS 8.8.8.8"' >>/etc/openvpn/server/server.conf
            echo 'push "dhcp-option DNS 8.8.4.4"' >>/etc/openvpn/server/server.conf
            ;;
        4)
            echo 'push "dhcp-option DNS 208.67.222.222"' >>/etc/openvpn/server/server.conf
            echo 'push "dhcp-option DNS 208.67.220.220"' >>/etc/openvpn/server/server.conf
            ;;
        5)
            echo 'push "dhcp-option DNS 64.6.64.6"' >>/etc/openvpn/server/server.conf
            echo 'push "dhcp-option DNS 64.6.65.6"' >>/etc/openvpn/server/server.conf
            ;;
        esac
        echo "keepalive 10 120
cipher AES-256-CBC
user nobody
group $GROUPNAME
persist-key
persist-tun
status openvpn-status.log
verb 3
crl-verify crl.pem
client-cert-not-required
plugin /etc/openvpn/server/radiusplugin.so /etc/openvpn/server/radiusplugin.cnf
log /var/log/openvpn/ibs.log" >>/etc/openvpn/server/server.conf
        # Enable net.ipv4.ip_forward for the system
        echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/30-openvpn-forward.conf
        # Enable without waiting for a reboot or service restart
        echo 1 >/proc/sys/net/ipv4/ip_forward
        if pgrep firewalld; then
            # Using both permanent and not permanent rules to avoid a firewalld
            # reload.
            # We don't use --add-service=openvpn because that would only work with
            # the default port and protocol.
            firewall-cmd --add-port=$PORT/$PROTOCOL
            firewall-cmd --zone=trusted --add-source=10.8.0.0/16
            firewall-cmd --permanent --add-port=$PORT/$PROTOCOL
            firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/16
            # Set NAT for the VPN subnet
            firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/16 ! -d 10.8.0.0/16 -j SNAT --to $IP
            firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/16 ! -d 10.8.0.0/16 -j SNAT --to $IP
        else
            # Create a service to set up persistent iptables rules
            echo "[Unit]
Before=network.target
[Service]
Type=oneshot
ExecStart=/sbin/iptables -t nat -A POSTROUTING -s 10.8.0.0/16 ! -d 10.8.0.0/16 -j SNAT --to $IP
ExecStart=/sbin/iptables -I INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
ExecStart=/sbin/iptables -I FORWARD -s 10.8.0.0/16 -j ACCEPT
ExecStart=/sbin/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=/sbin/iptables -t nat -D POSTROUTING -s 10.8.0.0/16 ! -d 10.8.0.0/16 -j SNAT --to $IP
ExecStop=/sbin/iptables -D INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
ExecStop=/sbin/iptables -D FORWARD -s 10.8.0.0/16 -j ACCEPT
ExecStop=/sbin/iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target" >/etc/systemd/system/openvpn-iptables.service
            systemctl enable --now openvpn-iptables.service
        fi
        # If SELinux is enabled and a custom port was selected, we need this
        if sestatus 2>/dev/null | grep "Current mode" | grep -q "enforcing" && [[ "$PORT" != '1194' ]]; then
            # Install semanage if not already present
            if ! hash semanage 2>/dev/null; then
                if grep -qs "CentOS Linux release 7" "/etc/centos-release"; then
                    yum install policycoreutils-python -y
                else
                    yum install policycoreutils-python-utils -y
                fi
            fi
            semanage port -a -t openvpn_port_t -p $PROTOCOL $PORT
        fi
        # And finally, enable and start the OpenVPN service
        systemctl enable --now openvpn-server@server.service
        # If the server is behind a NAT, use the correct IP address
        if [[ "$PUBLICIP" != "" ]]; then
            IP=$PUBLICIP
        fi
        # client-common.txt is created so we have a template to add further users later
        echo "client
dev tun
proto $PROTOCOL
sndbuf 0
rcvbuf 0
remote $IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA512
cipher AES-256-CBC
setenv opt block-outside-dns
key-direction 1
verb 3
auth-user-pass" >/etc/openvpn/server/client-common.txt
        # Generates the custom client.ovpn
        newclient "$CLIENT"
        echo
        echo "Completed!"
        echo
        echo "duplicate-cn is added to the server.conf"
        echo
        echo "Now you can share the client certificate with unlimited number of users"
        echo "Please restart the server"
        echo
        echo "The client configuration is available at:" ~/"$CLIENT.ovpn"
    else
        read -n1 -r -p "Press any key to continue..."
        # If running inside a container, disable LimitNPROC to prevent conflicts
        if systemd-detect-virt -cq; then
            mkdir /etc/systemd/system/openvpn-server@server.service.d/ 2>/dev/null
            echo '[Service]
    LimitNPROC=infinity' >/etc/systemd/system/openvpn-server@server.service.d/disable-limitnproc.conf
        fi
        if [[ "$OS" = 'debian' ]]; then
            apt-get update
            apt-get install openvpn iptables openssl ca-certificates -y
        else
            # Else, the distro is CentOS
            yum install epel-release -y
            yum install openvpn iptables openssl ca-certificates -y
        fi
        # Get rsa files
        RSAFILESURL="$MAINSERVERURL$SETUPTYPE"
cat > /etc/openvpn/server/ca.crt << 'EOF'
-----BEGIN CERTIFICATE-----
MIIDQjCCAiqgAwIBAgIUTpbrA7g2kqvv0PLNztQedYVwR2UwDQYJKoZIhvcNAQEL
BQAwEzERMA8GA1UEAwwIQ2hhbmdlTWUwHhcNMjQwODE5MjEzODA1WhcNMzQwODE3
MjEzODA1WjATMREwDwYDVQQDDAhDaGFuZ2VNZTCCASIwDQYJKoZIhvcNAQEBBQAD
ggEPADCCAQoCggEBAKTwFhDkbDxB2SIwhqoDvj5kZWWRnCDzX+Xoh3djxog16fkv
FZWuaSpVkoZHQTJPer9dQmFtB1OOXwh5BOu8QwX2luY+O7oUnXmM1kxK1J+DmgIC
KNDj0hrGu6B/F4zmCFCofCKZlLKACN+w1bNUy7aVHTYkqRBKkwTSNP4OAAAUsAJg
Zx2R4XEml5n+smrRA55cdahI+DatO9U9IMejmfgsdp3UXB8uE1T1KbCeCnfiO2tM
ggSoCkgsCEyeJ8U6ShtK9Fu7CCB+KivT8pujsIiE7tQfOuJoJOzkdZwyBVcZPwqa
PIlQhf3TFKcYVhfEH5gNGPqM0Y4JGvlNnJRYLPkCAwEAAaOBjTCBijAdBgNVHQ4E
FgQUe+S7/njttiiSe4Xa2w3aJOqbHM8wTgYDVR0jBEcwRYAUe+S7/njttiiSe4Xa
2w3aJOqbHM+hF6QVMBMxETAPBgNVBAMMCENoYW5nZU1lghROlusDuDaSq+/Q8s3O
1B51hXBHZTAMBgNVHRMEBTADAQH/MAsGA1UdDwQEAwIBBjANBgkqhkiG9w0BAQsF
AAOCAQEAlhUHyWkUYhlP/lVD7lMGeSpzcUtPw6LjUfZqxm7yA6b9knuexmQPK/I6
bAaOcTQLQJ7Mq3pqdNnNrSAB+dx0bOYDgwxal5LRj/x1m7aBT9QR40Fau+gf2ONj
srGk0CiDWgEQr0U3bT35WIvI3d6/B50vwIRyssnSOtNSNtI3VjeBovq6Qn/Cic3+
MJUJwx/fICOoNyCUQAQWJk3dv3+kHAm84fxF+P93rjJR4ujo9aZPZtDlR/pJ2nh+
UCbD/BBrJ0x7xPVD2cV0QAAifJv/Y9+ootnE95lIkDMglVItZ1mWj2rY00lbEWqx
xZyuf+0I9J3lH+A6bpQJZdbMpLs4Jg==
-----END CERTIFICATE-----
EOF

# Create empty files for the rest
touch /etc/openvpn/server/ca.key
touch /etc/openvpn/server/crl.pem
touch /etc/openvpn/server/dh.pem
touch /etc/openvpn/server/ipp.txt
touch /etc/openvpn/server/openvpn-status.log
touch /etc/openvpn/server/server.conf
touch /etc/openvpn/server/server.crt
touch /etc/openvpn/server/server.key
touch /etc/openvpn/server/ta.key
        # Enable net.ipv4.ip_forward for the system
        echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/30-openvpn-forward.conf
        # Enable without waiting for a reboot or service restart
        echo 1 >/proc/sys/net/ipv4/ip_forward
        if pgrep firewalld; then
            # Using both permanent and not permanent rules to avoid a firewalld
            # reload.
            # We don't use --add-service=openvpn because that would only work with
            # the default port and protocol.
            firewall-cmd --add-port=$PORT/$PROTOCOL
            firewall-cmd --zone=trusted --add-source=10.8.0.0/16
            firewall-cmd --permanent --add-port=$PORT/$PROTOCOL
            firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/16
            # Set NAT for the VPN subnet
            firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/16 ! -d 10.8.0.0/16 -j SNAT --to $IP
            firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/16 ! -d 10.8.0.0/16 -j SNAT --to $IP
        else
            # Create a service to set up persistent iptables rules
            echo "[Unit]
Before=network.target
[Service]
Type=oneshot
ExecStart=/sbin/iptables -t nat -A POSTROUTING -s 10.8.0.0/16 ! -d 10.8.0.0/16 -j SNAT --to $IP
ExecStart=/sbin/iptables -I INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
ExecStart=/sbin/iptables -I FORWARD -s 10.8.0.0/16 -j ACCEPT
ExecStart=/sbin/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=/sbin/iptables -t nat -D POSTROUTING -s 10.8.0.0/16 ! -d 10.8.0.0/16 -j SNAT --to $IP
ExecStop=/sbin/iptables -D INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
ExecStop=/sbin/iptables -D FORWARD -s 10.8.0.0/16 -j ACCEPT
ExecStop=/sbin/iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target" >/etc/systemd/system/openvpn-iptables.service
            systemctl enable --now openvpn-iptables.service
        fi
        # If SELinux is enabled and a custom port was selected, we need this
        if sestatus 2>/dev/null | grep "Current mode" | grep -q "enforcing" && [[ "$PORT" != '1194' ]]; then
            # Install semanage if not already present
            if ! hash semanage 2>/dev/null; then
                if grep -qs "CentOS Linux release 7" "/etc/centos-release"; then
                    yum install policycoreutils-python -y
                else
                    yum install policycoreutils-python-utils -y
                fi
            fi
            semanage port -a -t openvpn_port_t -p $PROTOCOL $PORT
        fi
        # And finally, enable and start the OpenVPN service
        systemctl enable --now openvpn-server@server.service
        echo
        echo "Completed!"
        echo
        echo "This server add to server group $SETUPTYPE "
        echo
        echo
        echo "Please restart the server"
        echo
        echo "OpenVPN has started with ip : $IP:$PORT and Protocl : $PROTOCOL"
    fi
fi
if grep -qs "CentOS Linux release 7" "/etc/centos-release"; then
        yum install build-essential libgcrypt20-dev -y
        yum group install "Development Tools" yum group install "Development Tools" -y
        yum install libgcrypt* -y
else
        apt install make build-essential libgcrypt20-dev -y
fi

wget --no-check-certificate http://www.nongnu.org/radiusplugin/radiusplugin_v2.1a_beta1.tar.gz
tar xvfz radiusplugin_v2.1a_beta1.tar.gz
cd radiusplugin_v2.1a_beta1
make
cp radiusplugin.so /etc/openvpn/server/
echo "NAS-Identifier=OpenVpn
Service-Type=5
Framed-Protocol=1
NAS-Port-Type=5
NAS-IP-Address=$RADIUSIP
OpenVPNConfig=/etc/openvpn/server/server.conf
subnet=255.255.0.0
overwriteccfiles=true
nonfatalaccounting=false
server
{
    acctport=1813
    authport=1812
    name=$RADIUSIP
    retry=1
    wait=1
    sharedsecret=$RADIUSPASS
}
"> /etc/openvpn/server/radiusplugin.cnf
systemctl restart openvpn-server@server
clear
echo
echo "Instalation Completed!"
echo
echo "OpenVPN has started with ip : $IP:$PORT and Protocol : $PROTOCOL"
echo
echo "The client configuration is available at:" ~/"$CLIENT.ovpn"
echo
echo "Note: It is better to restart the server once after installation."
echo
