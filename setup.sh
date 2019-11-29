#!bin/bash

set -e

echo "Running script as $(whoami)"

OMERO_PATH=~/prog/omero
OMERO_INIT_PASS=Orionsbelt32

HELP="""
Installs OMERO.server to $OMERO_PATH and loads it using systemctl.
It will not repeat installations

-u --update  to update this machine and install all dependencies

TODO: need stronger checks for whether db.sql script has been called
"""

SHOULD_UPDATE=

while [[ $# -gt 0 ]] ; do
    case "$1" in
        -h | --help)
            exit 0 ;;
        -u | --update)
            SHOULD_UPDATE=1 ;;
    esac
done

#################################
# Dependencies for OMERO.server #
#################################

if [[ -n "$SHOULD_UPDATE" ]]; then
    sudo apt update
    sudo apt -y upgrade
    sudo apt -y install unzip bc wget cron git curl
    # build tools and dependencies
    sudo apt -y install build-essential default-jdk postgresql zlib1g-dev
    # dependencies for Ice
    sudo apt -y install db5.3-util libbz2-dev libdb++-dev libdb-dev libexpat-dev libmcpp-dev libssl-dev mcpp zlib1g-dev
    sudo apt -y install python-{pip,tables,virtualenv,yaml,jinja2,pillow,numpy,wheel,setuptools}
fi

# install Ice 3.6.4
# not sure if this is library is necessary to run OMERO.server
if [[ ! -d /opt/Ice-3.6.4 ]] ; then
    wget -P ~/ "https://github.com/ome/zeroc-ice-ubuntu1804/releases/download/0.1.0/Ice-3.6.4-ubuntu1804-amd64.tar.xz"
    sudo tar xvf ~/"Ice-3.6.4-ubuntu1804-amd64.tar.xz" -C /opt --strip 1
    rm ~/Ice-3.6.4-ubuntu1804-amd64.tar.xz
    sudo chown -R root:root /opt/Ice-3.6.4
fi

# set Ice libraries
if [[ ! -f /etc/ld.so.conf.d/ice-x86_64.conf ]] ; then
    echo /opt/Ice-3.6.4/lib/x86_64-linux-gnu | sudo tee -a /etc/ld.so.conf.d/ice-x86_64.conf
    sudo chown root:root /etc/ld.so.conf.d/ice-x86_64.conf
    sudo ldconfig
fi

# set Ice 3.6.4 Python package
if [[ -n "$SHOULD_UPDATE" ]] && ! pip freeze | grep -qx "zeroc-ice==[0-9\.]*$" ; then
    pip install zeroc-ice>3.5,<3.7
fi

# set .profile. May want to change Ice verion to 3.6.5, etc...
PROFILE_APPEND="""

# OMERO admin settings
OMERO_DB_USER=$(whoami)
OMERO_DB_PASS=$OMERO_INIT_PASS
OMERO_DB_NAME=omero_database
OMERO_ROOT_PASS=$OMERO_INIT_PASS
OMERO_DATA_DIR=$OMERO_PATH/data
export OMERO_DB_USER OMERO_DB_PASS OMERO_DB_NAME OMERO_ROOT_PASS OMERO_DATA_DIR
export PGPASSWORD=\$OMERO_DB_PASS

# Ice settings
export ICE_HOME=/opt/Ice-3.6.4
export PATH+=:\$ICE_HOME/bin
export LD_LIBRARY_PATH+=:\$ICE_HOME/lib64:\$ICE_HOME/lib
export SLICEPATH=\$ICE_HOME/slice
"""

if ! grep -qxF "OMERO_DB_USER=$(whoami)" ~/.profile ; then
    echo "$PROFILE_APPEND" >> ~/.profile
fi
source ~/.profile

###################
# set up Postgres #
###################

if ! systemctl is-active --quiet postgresql ; then
    sudo systemctl restart postgresql # start as user
fi

if ! sudo -u postgres psql -tc '\du' | cut -d \| -f 1 | grep -qw "$OMERO_DB_USER"; then
    echo "CREATE USER $OMERO_DB_USER PASSWORD '$OMERO_DB_PASS'" | sudo -u postgres psql
fi

if ! psql -lqt | cut -d \| -f 1 | grep -qw "$OMERO_DB_NAME"; then
    sudo -u postgres createdb -E UTF8 -O $OMERO_DB_USER $OMERO_DB_NAME
fi

if ! psql -lqt | cut -d \| -f 1 | grep -qw "$OMERO_DB_USER"; then
    sudo -u postgres createdb -E UTF8 -O $OMERO_DB_USER $OMERO_DB_USER
fi

# create path for OMERO installation #

mkdir -p "$OMERO_PATH"
mkdir -p "$OMERO_PATH/data"

#########################
# install OMERO.insight #
#########################

OMERO_INSIGHT_VERSION="5.5.6"
OMERO_INSIGHT="OMERO.insight-$OMERO_INSIGHT_VERSION"
OMERO_INSIGHT_ZIP=~/"$OMERO_INSIGHT.zip"
if [[ ! -d "$OMERO_PATH/$OMERO_INSIGHT" ]]; then
    if [[ ! -f "$OMERO_INSIGHT_ZIP" ]]; then
        wget -P ~/ "https://github.com/ome/omero-insight/releases/download/v${OMERO_INSIGHT_VERSION}/$OMERO_INSIGHT.zip"
    fi
    unzip "$OMERO_INSIGHT_ZIP" -d "$OMERO_PATH"
    ln -s "$OMERO_PATH/$OMERO_INSIGHT" "$OMERO_PATH/OMERO.insight"
fi

########################
# install OMERO.server #
########################

OMERO_SERVER="OMERO.server-5.5.1-ice36-b122"
OMERO_SERVER_ZIP=~/"$OMERO_SERVER.zip"
if [[ ! -d "$OMERO_PATH/$OMERO_SERVER" ]]; then
    if [[ ! -f "$OMERO_SERVER_ZIP" ]]; then
       wget -P ~/ "https://downloads.openmicroscopy.org/omero/5.5.1/artifacts/$OMERO_SERVER.zip"
    fi
    unzip "$OMERO_SERVER_ZIP" -d "$OMERO_PATH"
    ln -s "$OMERO_PATH/$OMERO_SERVER" "$OMERO_PATH/OMERO.server"
fi

###########################
# Add executables to PATH #
###########################

PROFILE_APPEND="""

# OMERO binary paths
OMERO_SERVER_BIN=$OMERO_PATH/OMERO.server/bin
OMERO_INSIGHT_BIN=$OMERO_PATH/OMERO.insight/bin
PATH+=:\$OMERO_INSIGHT_BIN:\$OMERO_SERVER_BIN
"""

if ! grep -qxF "OMERO_SERVER_BIN=$OMERO_PATH/OMERO.server/bin" ~/.profile ; then
    echo "$PROFILE_APPEND" >> ~/.profile
fi
source ~/.profile

#################
# Configuration #
#################

omero config set omero.data.dir "$OMERO_DATA_DIR"
omero config set omero.db.name "$OMERO_DB_NAME"
omero config set omero.db.user "$OMERO_DB_USER"
omero config set omero.db.pass "$OMERO_DB_PASS"
omero config set omero.glacier2.IceSSL.Ciphers HIGH:ADH:@SECLEVEL=0

############################
# Create Postgres database #
############################

DB_CREATION_SCRIPT="${OMERO_PATH}/OMERO.server/db.sql"
if [[ ! -f "$DB_CREATION_SCRIPT" ]] ; then
    omero db script -f "$DB_CREATION_SCRIPT" --password "$OMERO_ROOT_PASS"
    psql -h localhost -U "$OMERO_DB_USER" "$OMERO_DB_NAME" < "$DB_CREATION_SCRIPT"
fi

###############################
# OMERO.server startup script #
###############################

OMERO_SERVICE_SCRIPT="""
ICE_HOME=/opt/Ice-3.6.4
PATH=/opt/Ice-3.6.4/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
LD_LIBRARY_PATH=/opt/Ice-3.6.4/lib64:/opt/Ice-3.6.4/lib
SLICEPATH=/opt/Ice-3.6.4/slice
"""

sudo mkdir -p /etc/sysconfig
if [[ ! -f /etc/sysconfig/omero ]] ; then
    echo "$OMERO_SERVICE_SCRIPT" | sudo tee /etc/sysconfig/omero > /dev/null
fi

OMERO_SERVICE_SCRIPT="""
[Unit]
Description=Start the OMERO Server
After=syslog.target network.target

[Service]
User=$(whoami)
Group=$(whoami)
Type=oneshot
EnvironmentFile=-/etc/sysconfig/omero
ExecStart=$OMERO_PATH/OMERO.server/bin/omero admin start
ExecStop=$OMERO_PATH/OMERO.server/bin/omero admin stop
ExecReload=$OMERO_PATH/OMERO.server/bin/omero admin restart
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
"""

OMERO_SERVICE="omero@$(whoami).service"
if [[ ! -f "/etc/systemd/system/$OMERO_SERVICE" ]] ; then
    echo "$OMERO_SERVICE_SCRIPT" | sudo tee /etc/systemd/system/$OMERO_SERVICE > /dev/null
    sudo systemctl daemon-reload
fi

if ! systemctl is-active --quiet "omero@$(whoami)" ; then
    sudo systemctl enable "omero@$(whoami)"
    sudo systemctl start "omero@$(whoami)"
fi

# clean up #

#rm -f "$OMERO_INSIGHT_ZIP"
#rm -f "$OMERO_SERVER_ZIP"

#######################
# NGINX for OMERO.web #
#######################

if [[ -n "$SHOULD_UPDATE" ]]; then
    sudo apt -y install nginx
    pip install -r "$OMERO_PATH/OMERO.server/share/web/requirements-py27.txt"
fi

omero config set omero.web.application_server wsgi-tcp

NGINX_CONF_TMP="$OMERO_PATH/OMERO.server/nginx.conf.tmp"
NGINX_CONF=/etc/nginx/sites-available/omero-web
if [[ ! -f  "$OMERO_NGINX_CONF" ]]; then
    omero web config nginx --http 80 > "$NGINX_CONF_TMP"
    sudo cp "$NGINX_CONF_TMP" "$NGINX_CONF"
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo ln -s "$NGINX_CONF" /etc/nginx/sites-enabled
    sudo systemctl restart nginx
fi



exit # stub














exit
