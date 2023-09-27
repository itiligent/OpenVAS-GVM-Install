#!/bin/bash
#######################################################################################################################
# Greenbone Vulnerability Manager upgrade script
# For Ubuntu / Debian
# David Harrop
# August 2023
#######################################################################################################################

if [[ $EUID -eq 0 ]]; then
    echo
    echo -e "${LRED}This script must NOT be run as root, it will prompt for sudo when needed." 1>&2
    echo -e ${NC}
    exit 1
fi

if ! [ $(id -nG "$USER" 2>/dev/null | egrep "sudo" | wc -l) -gt 0 ]; then
    echo
    echo -e "${LRED}The current user (${USER}) must be a member of the 'sudo' group, exiting..." 1>&2
    echo -e ${NC}
    exit 1
fi

# Select GVM install versions           (check below links for latest release versions)
export GVM_LIBS_VERSION=22.7.1          # https://github.com/greenbone/gvm-libs
export GVMD_VERSION=22.9.0              # https://github.com/greenbone/gvmd
export PG_GVM_VERSION=22.6.1            # https://github.com/greenbone/pg-gvm
export GSA_VERSION=22.7.0               # https://github.com/greenbone/gsa
export GSAD_VERSION=22.6.0              # https://github.com/greenbone/gsad
export OPENVAS_SMB_VERSION=22.5.3       # https://github.com/greenbone/openvas-smb
export OPENVAS_SCANNER_VERSION=22.7.5   # https://github.com/greenbone/openvas-scanner
export OSPD_OPENVAS_VERSION=22.6.0      # https://github.com/greenbone/ospd-openvas
export NOTUS_VERSION=22.6.0             # https://github.com/greenbone/notus-scanner

# Set global variables and paths
export INSTALL_PREFIX=/usr/local
export PATH=$PATH:$INSTALL_PREFIX/sbin
export SOURCE_DIR=$HOME/source && mkdir -p $SOURCE_DIR
export INSTALL_DIR=$HOME/install && mkdir -p $INSTALL_DIR
export BUILD_DIR=$HOME/build && mkdir -p $BUILD_DIR

clear

# Prepare text output colours
CYAN='\033[0;36m'
GREY='\033[0;37m'
GREYB='\033[1;37m'
LYELLOW='\033[0;93m'
NC='\033[0m' #No Colour

# Script branding header
echo
echo -e "${GREYB}Itiligent GVM Appliance Upgrader."
echo -e "               ${CYAN}Powered by Greenbone"
echo
echo

echo
echo -e "${CYAN}#############################################################################"
echo -e " Updating Linux OS"
echo -e "#############################################################################${NC}"
echo
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq 
sudo apt-get upgrade -qq -y
sudo pip3 install --upgrade pip >/dev/null
echo

# Stop GVM related services
sudo systemctl stop postgresql
sudo systemctl stop gvmd
sudo systemctl stop gsad
sudo systemctl stop ospd-openvas
sudo systemctl stop notus-scanner

echo
echo -e "${CYAN}#############################################################################"
echo -e " Installing gvm-lib"
echo -e "#############################################################################${NC}"
echo
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
echo -e " Building & upgrading gvmd"
echo -e "#############################################################################${NC}"
echo
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


echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & upgrading pg-gvm"
echo -e "#############################################################################${NC}"
echo
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
echo -e " Building & upgrading gsa"
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
echo -e " Building & upgrading gsad"
echo -e "#############################################################################${NC}"
echo
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

echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & upgrading openvas-smb"
echo -e "#############################################################################${NC}"
echo
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
echo -e " Building & upgrading openvas-scanner"
echo -e "#############################################################################${NC}"
echo
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
echo -e " Building & upgrading ospd-openvas"
echo -e "#############################################################################${NC}"
echo
# Download ospd-openvas sources
export OSPD_OPENVAS_VERSION=$OSPD_OPENVAS_VERSION
curl -f -L https://github.com/greenbone/ospd-openvas/archive/refs/tags/v$OSPD_OPENVAS_VERSION.tar.gz -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
curl -f -L https://github.com/greenbone/ospd-openvas/releases/download/v$OSPD_OPENVAS_VERSION/ospd-openvas-v$OSPD_OPENVAS_VERSION.tar.gz.asc -o $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz.asc $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz
tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION.tar.gz

# Install ospd-openvas
cd $SOURCE_DIR/ospd-openvas-$OSPD_OPENVAS_VERSION
sudo python3 -m pip install --upgrade ${PIP_OPTIONS} .

echo
echo -e "${CYAN}#############################################################################"
echo -e " Building & upgrading notus-scanner"
echo -e "#############################################################################${NC}"
echo
# Download notus-scanner sources
curl -f -L https://github.com/greenbone/notus-scanner/archive/refs/tags/v$NOTUS_VERSION.tar.gz -o $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz
curl -f -L https://github.com/greenbone/notus-scanner/releases/download/v$NOTUS_VERSION/notus-scanner-$NOTUS_VERSION.tar.gz.asc -o $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz.asc
gpg --verify $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz.asc $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz
tar -C $SOURCE_DIR -xvzf $SOURCE_DIR/notus-scanner-$NOTUS_VERSION.tar.gz

# Install notus-scanner
cd $SOURCE_DIR/notus-scanner-$NOTUS_VERSION
sudo python3 -m pip install --upgrade ${PIP_OPTIONS} .

echo
echo -e "${CYAN}#############################################################################"
echo -e " Upgrading greenbone-feed-sync & gvm-tools"
echo -e "#############################################################################${NC}"
echo
# Greenbone-feed-sync ##################################################################
sudo python3 -m pip install --upgrade ${PIP_OPTIONS} greenbone-feed-sync

# Gvm-tools ############################################################################
sudo python3 -m pip install --upgrade ${PIP_OPTIONS} gvm-tools

# Start GVM services
sudo systemctl daemon-reload
sudo systemctl start postgresql
sudo systemctl start gvmd
sudo systemctl start gsad
sudo systemctl start ospd-openvas
sudo systemctl start notus-scanner

# Lets update the feed whilst we are here
echo 
sudo /usr/local/bin/greenbone-feed-sync

# Clean up
rm -R $SOURCE_DIR
rm -R $INSTALL_DIR
rm -R $BUILD_DIR

echo -e ${NC}

