#!/bin/bash
#######################################################################################################################
# Greenbone Vulnerability Manager source build script
# For Ubuntu / Debian
# David Harrop
# July 2023
#######################################################################################################################

if [[ $EUID -eq 0 ]]; then
    echo
    echo -e "${LRED}This script must NOT be run as root, it will prompt for sudo when needed." 1>&2
    echo -e ${NC}
    exit 1
fi

# Check if sudo is installed. (Debian does not always include sudo by default.)
if ! command -v sudo &> /dev/null; then
    echo "${LRED}Sudo is not installed. Please install sudo."
    echo -e ${NC}
    exit 1
fi

if ! [ $(id -nG "$USER" 2>/dev/null | egrep "sudo" | wc -l) -gt 0 ]; then
    echo
    echo -e "${LRED}The current user (${USER}) must be a member of the 'sudo' group. Run: sudo usermod -aG sudo ${USER}" 1>&2
    echo -e ${NC}
    exit 1
fi

# Select GVM install versions           (check below links for latest release versions)
export GVM_LIBS_VERSION=22.7.3          # https://github.com/greenbone/gvm-libs
export GVMD_VERSION=22.9.0              # https://github.com/greenbone/gvmd
export PG_GVM_VERSION=22.6.1            # https://github.com/greenbone/pg-gvm
export GSA_VERSION=22.7.1               # https://github.com/greenbone/gsa
export GSAD_VERSION=22.6.0              # https://github.com/greenbone/gsad
export OPENVAS_SMB_VERSION=22.5.4       # https://github.com/greenbone/openvas-smb
export OPENVAS_SCANNER_VERSION=22.7.6   # https://github.com/greenbone/openvas-scanner
export OSPD_OPENVAS_VERSION=22.6.0      # https://github.com/greenbone/ospd-openvas
export NOTUS_VERSION=22.6.0             # https://github.com/greenbone/notus-scanner

# Set global variables and paths
export INSTALL_PREFIX=/usr/local
export PATH=$PATH:$INSTALL_PREFIX/sbin
export SOURCE_DIR=$HOME/source && mkdir -p $SOURCE_DIR
export INSTALL_DIR=$HOME/install && mkdir -p $INSTALL_DIR
export BUILD_DIR=$HOME/build && mkdir -p $BUILD_DIR

# Select PostgreSQL repo. Yes = use official repo, else use the distro default Postgres packages.
export OFFICIAL_POSTGRESQL="yes"
if [[ ${OFFICIAL_POSTGRESQL} = "yes" ]]; then
    # Install from official postgresql.org repo
    export POSTGRESQL="postgresql-15 postgresql-server-dev-15"
  else
    # Install distro default Postgres version. Check available version numbers with: apt-cache show postgresql*
    export POSTGRESQL="postgresql postgresql-server-dev-13"
        #Try this if all all else fails with your particular distro's version of postgresql:
            #export POSTGRESQL="postgresql-server-all"
fi

SERVER_NAME=""                       # Preferred server hostname (no installer prompt if has value)
LOCAL_DOMAIN=""                      # Local DNS suffix (no installer prompt if has value)
PROXY_SITE=""                        # Will default to $SERVER_NAME.$LOCAL_DOMAIN if no value provided here
GVM_URL="http://localhost:9392"      # GVM native web front end URL - don't change this
CERT_COUNTRY="AU"                    # For RSA SSL cert, 2 character country code only, must not be blank
CERT_STATE="Victoria"                # For RSA SSL cert, Optional to change, must not be blank
CERT_LOCATION="Melbourne"            # For RSA SSL cert, Optional to change, must not be blank
CERT_ORG="Itiligent"                 # For RSA SSL cert, Optional to change, must not be blank
CERT_OU="I.T."                       # For RSA SSL cert, Optional to change, must not be blank
CERT_DAYS="3650"                     # For RSA SSL cert, Number of days until self signed certificate expiry
DIR_SSL_CERT="/etc/nginx/ssl/cert"   # Nginx SSL certificate location - don't change this
DIR_SSL_KEY="/etc/nginx/ssl/private" # Nginx SSL private key location - don't change this
ADMIN_USER="itiligent"               # Set the default admin account username
ADMIN_PASS="password"                # Set the default admin account password

clear

# Prepare text output colours
CYAN='\033[0;36m'
GREY='\033[0;37m'
GREYB='\033[1;37m'
LYELLOW='\033[0;93m'
NC='\033[0m' #No Colour

# Script branding header
echo
echo -e "${GREYB}Itiligent GVM Appliance Setup."
echo -e "               ${CYAN}Powered by Greenbone"
echo
echo

# Get the default route interface IP
DEFAULT_IP=$(ip addr show $(ip route | awk '/default/ { print $5 }') | grep "inet" | head -n 1 | awk '/inet/ {print $2}' | cut -d'/' -f1)

# A default dns suffix is needed for initial prompts & default starting values.
get_domain_suffix() {
    echo "$1" | awk '{print $2}'
}
# Search for "search" and "domain" entries in /etc/resolv.conf
search_line=$(grep -E '^search[[:space:]]+' /etc/resolv.conf)
domain_line=$(grep -E '^domain[[:space:]]+' /etc/resolv.conf)
# Check if both "search" and "domain" lines exist
if [[ -n "$search_line" ]] && [[ -n "$domain_line" ]]; then
    # Both "search" and "domain" lines exist, extract the domain suffix from both
    search_suffix=$(get_domain_suffix "$search_line")
    domain_suffix=$(get_domain_suffix "$domain_line")
    # Print the domain suffix that appears first
    if [[ ${#search_suffix} -lt ${#domain_suffix} ]]; then
        DOMAIN_SUFFIX=$search_suffix
    else
        DOMAIN_SUFFIX=$domain_suffix
    fi
elif [[ -n "$search_line" ]]; then
    # If only "search" line exists
    DOMAIN_SUFFIX=$(get_domain_suffix "$search_line")
elif [[ -n "$domain_line" ]]; then
    # If only "domain" line exists
    DOMAIN_SUFFIX=$(get_domain_suffix "$domain_line")
else
    # If no "search" or "domain" lines found
    DOMAIN_SUFFIX="local"
fi

# GVM user setup and trigger to prompt for sudo
sudo useradd -r -M -U -G sudo -s /usr/sbin/nologin gvm
sudo usermod -aG gvm $USER
echo

# We need to ensure consistent default hostname and domain suffix values for TLS implementation. The below approach
# allows the user to either hit enter at the prompt to keep current values, or to manually update values. Silent install
# pre-set values (if provided) will bypass all prompts.

# Ensure SERVER_NAME is consistent with localhost entries
if [[ -z ${SERVER_NAME} ]]; then
    echo -e "${LYELLOW}Update Linux system HOSTNAME [Enter to keep: ${HOSTNAME}]${CYAN}"
    read -p "              Enter new HOSTNAME : " SERVER_NAME
    # If hit enter making no SERVER_NAME change, assume the existing hostname as current
    if [[ "${SERVER_NAME}" = "" ]]; then
        SERVER_NAME=$HOSTNAME
    fi
    echo
    # A SERVER_NAME was derived via the prompt
    # Apply the SERVER_NAME value & remove and update any old 127.0.1.1 localhost references
    $(sudo hostnamectl set-hostname $SERVER_NAME &> /dev/null &) &> /dev/null
    sudo sed -i '/127.0.1.1/d' /etc/hosts &> /dev/null
    echo '127.0.1.1       '${SERVER_NAME}'' | sudo tee -a /etc/hosts &> /dev/null
    $(sudo systemctl restart systemd-hostnamed &> /dev/null &) &> /dev/null
else
    echo
    # A SERVER_NAME value was derived from a pre-set silent install option.
    # Apply the SERVER_NAME value & remove and update any old 127.0.1.1 localhost references
    $(sudo hostnamectl set-hostname $SERVER_NAME &> /dev/null & ) &> /dev/null
    sudo sed -i '/127.0.1.1/d' /etc/hosts &> /dev/null
    echo '127.0.1.1       '${SERVER_NAME}'' | sudo tee -a /etc/hosts &> /dev/null
    $(sudo systemctl restart systemd-hostnamed &> /dev/null &) &> /dev/null
fi

# Ensure LOCAL_DOMAIN suffix and localhost entries are consistent
if [[ -z ${LOCAL_DOMAIN} ]]; then
    echo -e "${LYELLOW}Update Linux LOCAL DNS DOMAIN [Enter to keep: ${DOMAIN_SUFFIX}]${CYAN}"
    read -p "              Enter FULL LOCAL DOMAIN NAME: " LOCAL_DOMAIN
    # If hit enter making no LOCAL_DOMAIN name change, assume the existing domain suffix as current
    if [[ "${LOCAL_DOMAIN}" = "" ]]; then
        LOCAL_DOMAIN=$DOMAIN_SUFFIX
    fi
    echo
    # A LOCAL_DOMAIN value was derived via the prompt
    # Remove any old localhost & resolv file values and update these with the new LOCAL_DOMAIN value
    sudo sed -i "/${DEFAULT_IP}/d" /etc/hosts
    sudo sed -i '/domain/d' /etc/resolv.conf
    sudo sed -i '/search/d' /etc/resolv.conf
    # Refresh the /etc/hosts file with the server name and new local domain value
    echo ''${DEFAULT_IP}'	'${SERVER_NAME}.${LOCAL_DOMAIN} ${SERVER_NAME}'' | sudo tee -a /etc/hosts &> /dev/null
    # Refresh /etc/resolv.conf with new domain and search suffix values
    echo 'domain	'${LOCAL_DOMAIN}'' | sudo tee -a /etc/resolv.conf &> /dev/null
    echo 'search	'${LOCAL_DOMAIN}'' | sudo tee -a /etc/resolv.conf &> /dev/null
    $(sudo systemctl restart systemd-hostnamed &> /dev/null &) &> /dev/null
else
    echo
    # A LOCAL_DOMIN value was derived from a pre-set silent install option.
    # Remove any old localhost & resolv file values and update these with the new LOCAL_DOMAIN value
    sudo sed -i "/${DEFAULT_IP}/d" /etc/hosts
    sudo sed -i '/domain/d' /etc/resolv.conf
    sudo sed -i '/search/d' /etc/resolv.conf
    # Refresh the /etc/hosts file with the server name and new local domain value
    echo ''${DEFAULT_IP}'	'${SERVER_NAME}.${LOCAL_DOMAIN} ${SERVER_NAME}'' | sudo tee -a /etc/hosts &> /dev/null
    # Refresh /etc/resolv.conf with new domain and search suffix values
    echo 'domain	'${LOCAL_DOMAIN}'' | sudo tee -a /etc/resolv.conf &> /dev/null
    echo 'search	'${LOCAL_DOMAIN}'' | sudo tee -a /etc/resolv.conf &> /dev/null
    $(sudo systemctl restart systemd-hostnamed &> /dev/null &) &> /dev/null
fi

# Now that $SERVER_NAME and $LOCAL_DOMAIN values are updated and refreshed:
# Values are merged to build a local FQDN value (used for the default reverse proxy site name.)
DEFAULT_FQDN=$SERVER_NAME.$LOCAL_DOMAIN

# If the proxy site dns name is not manually overridden, keep the default FQDN as the proxy site name
if [ -z "${PROXY_SITE}" ]; then
    PROXY_SITE="${DEFAULT_FQDN}"
fi

# Workaround for OS specific python pip install syntax
source /etc/os-release
if [[ $VERSION_CODENAME = "bookworm" ]] || [[ $VERSION_CODENAME = "some_other" ]]; then
    PIP_OPTIONS="--no-warn-script-location --break-system-packages"
  else
    PIP_OPTIONS="--no-warn-script-location"
fi

echo
echo -e "${CYAN}#############################################################################"
echo -e " Updating Linux OS"
echo -e "#############################################################################${NC}"
echo
sudo apt-get update -qq &> /dev/null
# Avoid upgrade prompts and keep existing modified config files. Alternative is regular sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

echo
echo -e "${CYAN}#############################################################################"
echo -e " Installing common dependencies"
echo -e "#############################################################################${NC}"
echo
sudo apt-get install --no-install-recommends --assume-yes \
    build-essential curl cmake pkg-config python3 python3-pip gnupg wget sudo gnupg2 ufw htop &> /dev/null
    sudo DEBIAN_FRONTEND="noninteractive" apt-get install postfix mailutils -y &> /dev/null
    sudo service postfix restart &> /dev/null
    # Fix annoying "error: externally-managed-environment" message error with Python installs
        python_version_dir=$(python3 --version 2>&1 | grep -oP '\d+\.\d+' | head -n 1)
    sudo rm -rf /usr/lib/python${python_version_dir}/EXTERNALLY-MANAGED
    sudo pip3 install --upgrade pip &> /dev/null

# Import the Greenbone Community Signing key
curl -f -L https://www.greenbone.net/GBCommunitySigningKey.asc -o /tmp/GBCommunitySigningKey.asc
gpg --import /tmp/GBCommunitySigningKey.asc
echo "8AE4BE429B60A59B311C2E739823FAA60ED1E580:6:" | gpg --import-ownertrust

echo
echo -e "${CYAN}#############################################################################"
echo -e " Installing gvm-lib"
echo -e "#############################################################################${NC}"
echo
sudo apt-get install -y \
    libglib2.0-dev libgpgme-dev libgnutls28-dev uuid-dev libssh-gcrypt-dev libhiredis-dev libxml2-dev libpcap-dev libnet1-dev \
    libpaho-mqtt-dev libldap2-dev libradcli-dev doxygen xmltoman graphviz libldap2-dev libradcli-dev &> /dev/null

# Download the gvm-libs sources
export GVM_LIBS_VERSION=$GVM_LIBS_VERSION
curl -f -L https://github.com/greenbone/gvm-libs/archive/refs/tags/v$GVM_LIBS_VERSION.tar.gz -o $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz
curl -f -L https://github.com/greenbone/gvm-libs/releases/download/v$GVM_LIBS_VERSION/gvm-libs-v$GVM_LIBS_VERSION.tar.gz.asc -o $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz.asc $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz

# Build gvm-libs
tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION.tar.gz
mkdir -p $BUILD_DIR/gvm-libs && cd $BUILD_DIR/gvm-libs
cmake $SOURCE_DIR/gvm-libs-$GVM_LIBS_VERSION \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
    -DCMAKE_BUILD_TYPE=Release \
    -DSYSCONFDIR=/etc \
    -DLOCALSTATEDIR=/var
make -j$(nproc)
mkdir -p $INSTALL_DIR/gvm-libs
make DESTDIR=$INSTALL_DIR/gvm-libs install
sudo cp -rv $INSTALL_DIR/gvm-libs/* /

# Install gvm-libs
mkdir -p $INSTALL_DIR/gvm-libs
make DESTDIR=$INSTALL_DIR/gvm-libs install
sudo cp -rv $INSTALL_DIR/gvm-libs/* /

echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & installing gvmd"
echo -e "#############################################################################${NC}"

echo
if [[ ${OFFICIAL_POSTGRESQL} = "yes" ]]; then
    sudo apt-get -y install lsb-release &> /dev/null
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    sudo wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    sudo apt-key export ACCC4CF8 | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/greenbone.gpg
fi
sudo apt -y update
sudo apt-get install -y \
    libglib2.0-dev libgnutls28-dev libpq-dev libical-dev ${POSTGRESQL} xsltproc rsync libbsd-dev libgpgme-dev &> /dev/null

# Install optional dependencies for gvmd
sudo apt-get install -y --no-install-recommends \
    texlive-latex-extra texlive-fonts-recommended xmlstarlet zip rpm fakeroot dpkg nsis gnupg gpgsm wget sshpass openssh-client \
    socat snmp python3 smbclient python3-lxml gnutls-bin xml-twig-tools &> /dev/null

# Download the gvmd sources
export GVMD_VERSION=$GVMD_VERSION
curl -f -L https://github.com/greenbone/gvmd/archive/refs/tags/v$GVMD_VERSION.tar.gz -o $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz
curl -f -L https://github.com/greenbone/gvmd/releases/download/v$GVMD_VERSION/gvmd-$GVMD_VERSION.tar.gz.asc -o $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz.asc $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz

# Build gvmd
tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gvmd-$GVMD_VERSION.tar.gz
mkdir -p $BUILD_DIR/gvmd && cd $BUILD_DIR/gvmd
cmake $SOURCE_DIR/gvmd-$GVMD_VERSION \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
    -DCMAKE_BUILD_TYPE=Release \
    -DLOCALSTATEDIR=/var \
    -DSYSCONFDIR=/etc \
    -DGVM_DATA_DIR=/var \
    -DGVMD_RUN_DIR=/run/gvmd \
    -DOPENVAS_DEFAULT_SOCKET=/run/ospd/ospd-openvas.sock \
    -DGVM_FEED_LOCK_PATH=/var/lib/gvm/feed-update.lock \
    -DSYSTEMD_SERVICE_DIR=/lib/systemd/system \
    -DLOGROTATE_DIR=/etc/logrotate.d
make -j$(nproc)

# Install gvmd
mkdir -p $INSTALL_DIR/gvmd
make DESTDIR=$INSTALL_DIR/gvmd install
sudo cp -rv $INSTALL_DIR/gvmd/* /

cat <<EOF >$BUILD_DIR/gvmd.service
[Unit]
Description=Greenbone Vulnerability Manager daemon (gvmd)
After=network.target networking.service postgresql.service ospd-openvas.service
Wants=postgresql.service ospd-openvas.service
Documentation=man:gvmd(8)
ConditionKernelCommandLine=!recovery

[Service]
Type=exec
User=gvm
Group=gvm
PIDFile=/run/gvmd/gvmd.pid
RuntimeDirectory=gvmd
RuntimeDirectoryMode=2775
ExecStart=/usr/local/sbin/gvmd --foreground --osp-vt-update=/run/ospd/ospd-openvas.sock --listen-group=gvm
Restart=always
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF
sudo cp -v $BUILD_DIR/gvmd.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gvmd

echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & installing pg-gvm"
echo -e "#############################################################################${NC}"
echo
sudo apt-get install -y \
    libglib2.0-dev libical-dev ${POSTGRESQL} &> /dev/null

# Download the pg-gvm sources
export PG_GVM_VERSION=$PG_GVM_VERSION
curl -f -L https://github.com/greenbone/pg-gvm/archive/refs/tags/v$PG_GVM_VERSION.tar.gz -o $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz
curl -f -L https://github.com/greenbone/pg-gvm/releases/download/v$PG_GVM_VERSION/pg-gvm-$PG_GVM_VERSION.tar.gz.asc -o $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz.asc $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz

# Build pg-gvm
tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION.tar.gz
mkdir -p $BUILD_DIR/pg-gvm && cd $BUILD_DIR/pg-gvm
cmake $SOURCE_DIR/pg-gvm-$PG_GVM_VERSION \
    -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# Install pg-gvm
mkdir -p $INSTALL_DIR/pg-gvm
make DESTDIR=$INSTALL_DIR/pg-gvm install
sudo cp -rv $INSTALL_DIR/pg-gvm/* /

echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & installing gsa"
echo -e "#############################################################################${NC}"
echo
export GSA_VERSION=$GSA_VERSION
curl -f -L https://github.com/greenbone/gsa/releases/download/v$GSA_VERSION/gsa-dist-$GSA_VERSION.tar.gz -o $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz
curl -f -L https://github.com/greenbone/gsa/releases/download/v$GSA_VERSION/gsa-dist-$GSA_VERSION.tar.gz.asc -o $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz.asc $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz

# Extract and install gsa
mkdir -p $SOURCE_DIR/gsa-$GSA_VERSION
tar -C $SOURCE_DIR/gsa-$GSA_VERSION -xvzf $SOURCE_DIR/gsa-$GSA_VERSION.tar.gz
sudo mkdir -p $INSTALL_PREFIX/share/gvm/gsad/web/
sudo cp -rv $SOURCE_DIR/gsa-$GSA_VERSION/* $INSTALL_PREFIX/share/gvm/gsad/web/

echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & installing gsad"
echo -e "#############################################################################${NC}"
echo
sudo apt-get install -y \
    libmicrohttpd-dev libxml2-dev libglib2.0-dev libgnutls28-dev &> /dev/null

# Download gsad sources
export GSAD_VERSION=$GSAD_VERSION
curl -f -L https://github.com/greenbone/gsad/archive/refs/tags/v$GSAD_VERSION.tar.gz -o $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz
curl -f -L https://github.com/greenbone/gsad/releases/download/v$GSAD_VERSION/gsad-$GSAD_VERSION.tar.gz.asc -o $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz.asc $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz

# Build gsad
tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/gsad-$GSAD_VERSION.tar.gz
mkdir -p $BUILD_DIR/gsad && cd $BUILD_DIR/gsad
cmake $SOURCE_DIR/gsad-$GSAD_VERSION \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
    -DCMAKE_BUILD_TYPE=Release \
    -DSYSCONFDIR=/etc \
    -DLOCALSTATEDIR=/var \
    -DGVMD_RUN_DIR=/run/gvmd \
    -DGSAD_RUN_DIR=/run/gsad \
    -DLOGROTATE_DIR=/etc/logrotate.d
make -j$(nproc)

# Install gsad
mkdir -p $INSTALL_DIR/gsad
make DESTDIR=$INSTALL_DIR/gsad install
sudo cp -rv $INSTALL_DIR/gsad/* /
cat <<EOF >$BUILD_DIR/gsad.service
[Unit]
Description=Greenbone Security Assistant daemon (gsad)
Documentation=man:gsad(8) https://www.greenbone.net
After=network.target gvmd.service
Wants=gvmd.service

[Service]
Type=exec
User=gvm
Group=gvm
RuntimeDirectory=gsad
RuntimeDirectoryMode=2775
PIDFile=/run/gsad/gsad.pid
ExecStart=/usr/local/sbin/gsad --foreground --listen=127.0.0.1 --port=9392 --http-only
Restart=always
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
Alias=greenbone-security-assistant.service
EOF
sudo cp -v $BUILD_DIR/gsad.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable gsad

echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & installing openvas-smb"
echo -e "#############################################################################${NC}"
echo
sudo apt-get install -y \
    gcc-mingw-w64 libgnutls28-dev libglib2.0-dev libpopt-dev libunistring-dev heimdal-dev perl-base &> /dev/null

# Download the openvas-smb sources
export OPENVAS_SMB_VERSION=$OPENVAS_SMB_VERSION
curl -f -L https://github.com/greenbone/openvas-smb/archive/refs/tags/v$OPENVAS_SMB_VERSION.tar.gz -o $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz
curl -f -L https://github.com/greenbone/openvas-smb/releases/download/v$OPENVAS_SMB_VERSION/openvas-smb-v$OPENVAS_SMB_VERSION.tar.gz.asc -o $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz.asc $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz

# Build openvas-smb
tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION.tar.gz
mkdir -p $BUILD_DIR/openvas-smb && cd $BUILD_DIR/openvas-smb
cmake $SOURCE_DIR/openvas-smb-$OPENVAS_SMB_VERSION \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
    -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# Install openvas-smb
mkdir -p $INSTALL_DIR/openvas-smb
make DESTDIR=$INSTALL_DIR/openvas-smb install
sudo cp -rv $INSTALL_DIR/openvas-smb/* /

echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & installing openvas-scanner"
echo -e "#############################################################################${NC}"
echo
sudo apt-get install -y \
    bison libglib2.0-dev libgnutls28-dev libgcrypt20-dev libpcap-dev libgpgme-dev libksba-dev rsync nmap libjson-glib-dev \
    libbsd-dev python3-impacket libsnmp-dev pandoc pnscan &> /dev/null

# Download openvas-scanner sources
export OPENVAS_SCANNER_VERSION=$OPENVAS_SCANNER_VERSION
curl -f -L https://github.com/greenbone/openvas-scanner/archive/refs/tags/v$OPENVAS_SCANNER_VERSION.tar.gz -o $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz
curl -f -L https://github.com/greenbone/openvas-scanner/releases/download/v$OPENVAS_SCANNER_VERSION/openvas-scanner-v$OPENVAS_SCANNER_VERSION.tar.gz.asc -o $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz.asc $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz

# Build openvas-scanner
tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION.tar.gz
mkdir -p $BUILD_DIR/openvas-scanner && cd $BUILD_DIR/openvas-scanner
cmake $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION \
    -DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX \
    -DCMAKE_BUILD_TYPE=Release \
    -DINSTALL_OLD_SYNC_SCRIPT=OFF \
    -DSYSCONFDIR=/etc \
    -DLOCALSTATEDIR=/var \
    -DOPENVAS_FEED_LOCK_PATH=/var/lib/openvas/feed-update.lock \
    -DOPENVAS_RUN_DIR=/run/ospd
make -j$(nproc)

# Install openvas-scanner
mkdir -p $INSTALL_DIR/openvas-scanner
make DESTDIR=$INSTALL_DIR/openvas-scanner install
sudo cp -rv $INSTALL_DIR/openvas-scanner/* /

echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & installing ospd-openvas"
echo -e "#############################################################################${NC}"
echo
sudo apt-get install -y \
    python3 python3-pip python3-setuptools python3-packaging python3-wrapt python3-cffi python3-psutil python3-lxml \
    python3-defusedxml python3-paramiko python3-redis python3-gnupg python3-paho-mqtt &> /dev/null

# Download ospd-openvas sources
export OSPD_OPENVAS_VERSION=$OSPD_OPENVAS_VERSION
curl -f -L https://github.com/greenbone/ospd-openvas/archive/refs/tags/v$OSPD_OPENVAS_VERSION.tar.gz -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
curl -f -L https://github.com/greenbone/ospd-openvas/releases/download/v$OSPD_OPENVAS_VERSION/ospd-openvas-v$OSPD_OPENVAS_VERSION.tar.gz.asc -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz

# Install ospd-openvas
cd $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION
sudo python3 -m pip install ${PIP_OPTIONS} .

cat <<EOF >$BUILD_DIR/ospd-openvas.service
[Unit]
Description=OSPd Wrapper for the OpenVAS Scanner (ospd-openvas)
Documentation=man:ospd-openvas(8) man:openvas(8)
After=network.target networking.service redis-server@openvas.service mosquitto.service
Wants=redis-server@openvas.service mosquitto.service notus-scanner.service
ConditionKernelCommandLine=!recovery

[Service]
Type=exec
User=gvm
Group=gvm
RuntimeDirectory=ospd
RuntimeDirectoryMode=2775
PIDFile=/run/ospd/ospd-openvas.pid
ExecStart=/usr/local/bin/ospd-openvas --foreground --unix-socket /run/ospd/ospd-openvas.sock --pid-file /run/ospd/ospd-openvas.pid --log-file /var/log/gvm/ospd-openvas.log --lock-file-dir /var/lib/openvas --socket-mode 0o770 --mqtt-broker-address localhost --mqtt-broker-port 1883 --notus-feed-dir /var/lib/notus/advisories
SuccessExitStatus=SIGKILL
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF
sudo cp -v $BUILD_DIR/ospd-openvas.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ospd-openvas

echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & installing notus-scanner"
echo -e "#############################################################################${NC}"
echo
sudo apt-get install -y \
    python3 python3-pip python3-setuptools python3-paho-mqtt python3-psutil python3-gnupg &> /dev/null
    # Raspberry Pi specific notus dependencies
    PLATFORM=$(cat /proc/cpuinfo | grep Model)
    if [[ $PLATFORM = *"Raspberry Pi"* ]]; then
        sudo apt-get install python3-dev -y &> /dev/null
    fi

# Download notus-scanner sources
curl -f -L https://github.com/greenbone/notus-scanner/archive/refs/tags/v$NOTUS_VERSION.tar.gz -o $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz
curl -f -L https://github.com/greenbone/notus-scanner/releases/download/v$NOTUS_VERSION/notus-scanner-$NOTUS_VERSION.tar.gz.asc -o $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz.asc $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz
tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz

# Install notus-scanner
cd $SOURCE_DIR/notus-scanner-$NOTUS_VERSION
sudo python3 -m pip install ${PIP_OPTIONS} .

cat <<EOF >$BUILD_DIR/notus-scanner.service
[Unit]
Description=Notus Scanner
Documentation=https://github.com/greenbone/notus-scanner
After=mosquitto.service
Wants=mosquitto.service
ConditionKernelCommandLine=!recovery

[Service]
Type=exec
User=gvm
RuntimeDirectory=notus-scanner
RuntimeDirectoryMode=2775
PIDFile=/run/notus-scanner/notus-scanner.pid
ExecStart=/usr/local/bin/notus-scanner --foreground --products-directory /var/lib/notus/products --log-file /var/log/gvm/notus-scanner.log
SuccessExitStatus=SIGKILL
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF
sudo cp -v $BUILD_DIR/notus-scanner.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable notus-scanner

echo
echo -e "${CYAN}#############################################################################"
echo -e " Setting up greenbone-feed-sync, gvm-tools, redis-server & mosquitto"
echo -e "#############################################################################${NC}"
echo
# Greenbone-feed-sync ##################################################################
sudo apt-get install -y \
    python3 python3-pip &> /dev/null

sudo python3 -m pip install ${PIP_OPTIONS} greenbone-feed-sync

# Gvm-tools ############################################################################
sudo apt-get install -y \
    python3 python3-pip python3-venv python3-setuptools python3-packaging python3-lxml python3-defusedxml python3-paramiko &> /dev/null

sudo python3 -m pip install ${PIP_OPTIONS} gvm-tools

# Redis server #########################################################################
sudo apt-get install -y redis-server
sudo cp $SOURCE_DIR/openvas-scanner-$OPENVAS_SCANNER_VERSION/config/redis-openvas.conf /etc/redis/
sudo chown redis:redis /etc/redis/redis-openvas.conf
echo "db_address = /run/redis-openvas/redis.sock" | sudo tee -a /etc/openvas/openvas.conf
sudo systemctl start redis-server@openvas.service
sudo systemctl enable redis-server@openvas.service
sudo usermod -aG redis gvm

# Mqtt broker ##########################################################################
sudo apt-get install -y mosquitto
sudo systemctl start mosquitto.service
sudo systemctl enable mosquitto.service
echo -e "mqtt_server_uri = localhost:1883\ntable_driven_lsc = yes" | sudo tee -a /etc/openvas/openvas.conf

echo
echo -e "${CYAN}#############################################################################"
echo -e " Setting up Nginx reverse proxy"
echo -e "#############################################################################${NC}"
echo
sudo apt-get install -y nginx &> /dev/null

# Nginx SSL cert config
cd ~
cat <<EOF | tee cert_attributes.txt
[req]
distinguished_name  = req_distinguished_name
x509_extensions     = v3_req
prompt              = no
string_mask         = utf8only

[req_distinguished_name]
C                   = $CERT_COUNTRY
ST                  = $CERT_STATE
L                   = $CERT_LOCATION
O                   = $CERT_ORG
OU                  = $CERT_OU
CN                  = *.$(echo $PROXY_SITE | cut -d. -f2-)

[v3_req]
keyUsage            = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage    = serverAuth, clientAuth, codeSigning, emailProtection
subjectAltName      = @alt_names

[alt_names]
DNS.1               = $PROXY_SITE
DNS.2               = *.$(echo $PROXY_SITE | cut -d. -f2-)
IP.1                = $DEFAULT_IP
EOF

# Make default certificate destinations.
sudo mkdir -p $DIR_SSL_KEY
sudo mkdir -p $DIR_SSL_CERT

# Create certificate
openssl req -x509 -nodes -newkey rsa:2048 -keyout $PROXY_SITE.key -out $PROXY_SITE.crt -days $CERT_DAYS -config cert_attributes.txt
# Create a PFX formatted key for easier import to Windows hosts and change permissions to enable copying elsewhere
sudo openssl pkcs12 -export -out $PROXY_SITE.pfx -inkey $PROXY_SITE.key -in $PROXY_SITE.crt -password pass:1234
sudo chmod 0774 $PROXY_SITE.pfx

# Place SSL Certificate within Nginx defined path
sudo cp $PROXY_SITE.key $DIR_SSL_KEY/$PROXY_SITE.key
sudo cp $PROXY_SITE.crt $DIR_SSL_CERT/$PROXY_SITE.crt

cat <<EOF | sudo tee /etc/nginx/sites-available/$PROXY_SITE
server {
    # HTTPS site
    listen 443 ssl;
    server_name _;
    location / {
        proxy_pass $GVM_URL;
        proxy_buffering off;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
        access_log off;
    }
    ssl_certificate      /etc/nginx/ssl/cert/$PROXY_SITE.crt;
    ssl_certificate_key  /etc/nginx/ssl/private/$PROXY_SITE.key;
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout  5m;
}

server {
    # Redirect all other traffic to the HTTPS site
    listen 80 default_server;
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

# Symlink from sites-available to sites-enabled
sudo ln -s /etc/nginx/sites-available/$PROXY_SITE /etc/nginx/sites-enabled/

# Make sure default Nginx site is unlinked
sudo unlink /etc/nginx/sites-enabled/default

# Force nginx to require tls1.2 and above
sudo sed -i -e '/ssl_protocols/s/^/#/' /etc/nginx/nginx.conf 
sudo sed -i "/SSL Settings/a \        ssl_protocols TLSv1.2 TLSv1.3;" /etc/nginx/nginx.conf

# Restart Nginx
sudo systemctl restart nginx

# Update general ufw rules to force traffic via reverse proxy
sudo ufw default allow outgoing >/dev/null 2>&1
sudo ufw default deny incoming >/dev/null 2>&1
sudo ufw allow OpenSSH >/dev/null 2>&1
sudo ufw allow 80/tcp >/dev/null 2>&1
sudo ufw allow 443/tcp >/dev/null 2>&1
echo "y" | sudo ufw enable >/dev/null 2>&1
sudo ufw logging off

echo
echo -e "${CYAN}#############################################################################"
echo -e " Setting up the postgres db, gvm permissions & update feed digital signature."
echo -e "#############################################################################${NC}"
echo
# Set directory permissions ############################################################
sudo mkdir -p /var/lib/notus
sudo mkdir -p /run/gvmd
sudo chown -R gvm:gvm /var/lib/gvm
sudo chown -R gvm:gvm /var/lib/openvas
sudo chown -R gvm:gvm /var/lib/notus
sudo chown -R gvm:gvm /var/log/gvm
sudo chown -R gvm:gvm /run/gvmd
sudo chmod -R g+srw /var/lib/gvm
sudo chmod -R g+srw /var/lib/openvas
sudo chmod -R g+srw /var/log/gvm

# Set gvmd permissions #################################################################
sudo chown gvm:gvm /usr/local/sbin/gvmd
sudo chmod 6750 /usr/local/sbin/gvmd

# Feed validation ######################################################################
curl -f -L https://www.greenbone.net/GBCommunitySigningKey.asc -o /tmp/GBCommunitySigningKey.asc
export GNUPGHOME=/tmp/openvas-gnupg
mkdir -p $GNUPGHOME
gpg --import /tmp/GBCommunitySigningKey.asc
echo "8AE4BE429B60A59B311C2E739823FAA60ED1E580:6:" | gpg --import-ownertrust
export OPENVAS_GNUPG_HOME=/etc/openvas/gnupg
sudo mkdir -p $OPENVAS_GNUPG_HOME
sudo cp -r /tmp/openvas-gnupg/* $OPENVAS_GNUPG_HOME/
sudo chown -R gvm:gvm $OPENVAS_GNUPG_HOME

# Schedule a random daily feed update time
HOUR=$(shuf -i 0-23 -n 1)
MINUTE=$(shuf -i 0-59 -n 1)
sudo crontab -l >cron_1
# Remove any previously added feed update schedules
sed -i '/greenbone-feed-sync/d' cron_1
echo "${MINUTE} ${HOUR} * * * /usr/local/bin/greenbone-feed-sync" >>cron_1

# Set sudo permissions for scanner #####################################################
sudo sh -c "echo '%gvm ALL = NOPASSWD: /usr/local/sbin/openvas' >> /etc/sudoers"

# Set up PostgreSQL user and database ##################################################
sudo -Hiu postgres createuser -DRS gvm
sudo -Hiu postgres createdb -O gvm gvmd
sudo -Hiu postgres psql gvmd -c "create role dba with superuser noinherit; grant dba to gvm;"
sudo ldconfig

# Create admin user ####################################################################
sudo /usr/local/sbin/gvmd --create-user=${ADMIN_USER} --password=${ADMIN_PASS}

# Update feed owner ####################################################################
sudo /usr/local/sbin/gvmd --modify-setting 78eceaec-3385-11ea-b237-28d24461215b --value $(sudo /usr/local/sbin/gvmd --get-users --verbose | grep ${ADMIN_USER} | awk '{print $2}')

echo
echo -e "${CYAN}#############################################################################"
echo -e " Feed updates must complete before gvm can start, this may take a LONG time"
echo -e "#############################################################################${NC}"
echo
# Update the feed and start the services ###############################################
# One line because feed updates take so long that cached sudo credentials time out
sudo bash -c '/usr/local/bin/greenbone-feed-sync; crontab cron_1 systemctl start notus-scanner; systemctl start ospd-openvas; systemctl start gvmd; systemctl start gsad'

# Clean up
rm -R $SOURCE_DIR
rm -R $INSTALL_DIR
rm -R $BUILD_DIR
rm cert_attributes.txt
rm cron_1

# Cheap hack to display in stdout client certificate configs (where special characters normally break cut/pasteable output)
SHOWASTEXT1='$mypwd'
SHOWASTEXT2='"Cert:\LocalMachine\Root"'

printf "${GREY}+-------------------------------------------------------------------------------------------------------------
${CYAN}+ WINDOWS CLIENT SELF SIGNED SSL BROWSER CONFIG - SAVE THIS BEFORE CONTINUING!${GREY}
+
+ 1. In your home directory is a Windows friendly version of the new certificate ${LYELLOW}$PROXY_SITE.pfx${GREY}
+ 2. Copy this .pfx file to a location accessible by Windows.
+ 3. Import the PFX file into your Windows client with the below Powershell commands (as Administrator):
\n"
echo -e "${SHOWASTEXT1} = ConvertTo-SecureString -String "1234" -Force -AsPlainText"
echo -e "Import-pfxCertificate -FilePath $PROXY_SITE.pfx -Password "${SHOWASTEXT1}" -CertStoreLocation "${SHOWASTEXT2}""
echo -e "(Clear your browser cache and restart your browser to test.)"
printf "${GREY}+-------------------------------------------------------------------------------------------------------------
${CYAN}+ LINUX CLIENT SELF SIGNED SSL BROWSER CONFIG - SAVE THIS BEFORE CONTINUING!${GREY}
+
+ 1. In your home directory is a new Linux native OpenSSL certificate ${LYELLOW}$PROXY_SITE.crt${GREY}
+ 2. Copy this file to a location accessible by Linux.
+ 3. Import the CRT file into your Linux client certificate store with the below command (as sudo):
\n"
echo -e "mkdir -p \$HOME/.pki/nssdb && certutil -d \$HOME/.pki/nssdb -N"
echo -e "certutil -d sql:$HOME/.pki/nssdb -A -t "CT,C,c" -n $SSLNAME -i $SSLNAME.crt"
printf "+-------------------------------------------------------------------------------------------------------------\n"
echo
echo -e "${CYAN}GVM build & install complete\nhttps://${PROXY_SITE} - admin login: ${ADMIN_USER} pass: ${ADMIN_PASS}\n${LYELLOW}***Be sure to change the password***${NC}"
echo