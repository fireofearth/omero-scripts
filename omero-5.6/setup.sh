#!bin/bash

set -e

echo "Running script as $(whoami)"

HELP="""
The AIM Install Script for OMERO.server + OMERO.web + AIMViewer
Installs everything(!) to a newly installed Ubuntu 18.04 computer with systemd. Directories / files (not exclusive) will be directly modified or created by these apps:

/opt/Ice-3.6.5              # Ice RPC framework
/etc/sysconfig              # environmental variables for startup scripts
/etc/systemd/system         # add startup scripts
~/.profile                  # modify PATH variable and add export program env variables
~/prog/n                    # the Node.js version manager
~/prog/omero/data           # data stored by OMERO.server
~/prog/omero/OMERO.server   # OMERO.server files
~/prog/omero/OMERO.insight  # OMERO.insight program
~/prog/omero/venv_server    # python binaries for OMERO.server and OMERO.insight, including dependencies
~/code/aimviewer            # AIMViewer app from OMERO.web
~/omero/data                # data stored by OMERO.server (default location)

It will install these programs:

Python3, Python3-venv, etc... (see script for details)
OMERO.server:  the OMERO server
OMERO.insight: the Java client for OMERO
Ice:           RPC framework used by OMERO
postgresql:    metadata for OMERO.server
Redis:         image cache for OME Seadragon
Nginx:         serves files for OMERO.web and plugins
N:             Node.js + NPM version manager used for front-end compilation tasks

It will not repeat installation tasks already done previously so this script can be run multiple times for whatever reason.

--help, -h  show this help message and quit
--deps      to update this machine and install all APT dependencies
--pip       to pip install Python dependencies
--npm       to npm install NPM dependencies
--data-path path to OMERO.server data directory
"""

OMERO_PATH=~/prog/omero
OMEROHOST=localhost
OMEROPORT=4064

OMERO_INIT_PASS=
OMERO_DATA_PATH=
SHOULD_INSTALL=
SHOULD_PIP_INSTALL=
SHOULD_NPM_INSTALL=

while [[ $# -gt 0 ]] ; do
    case "$1" in
        -h | --help)
            echo "$HELP"
            exit 0 ;;
        --deps)
            SHOULD_INSTALL=1 ;;
        --pip)
            SHOULD_PIP_INSTALL=1 ;;
        --npm)
            SHOULD_NPM_INSTALL=1 ;;
        --data-path)
            shift
            if [[ $# -gt 0 ]] ; then
                if [[ -z "${1%/*}" ]] || [[ "${1##*/}" != data ]] ; then
                    echo "The subpath '${1%/*}' is not valid or path does not end with 'data'"
                    exit 1
                else
                    OMERO_DATA_PATH=$1
                fi
            else
                echo "No data path specified"
                exit 1
            fi
        ;;
        --omero-pass)
            shift
            if [[ $# -gt 0 ]] ; then
                pattern="[\t ]"
                if [[ ${#1} -lt 6 ]] || [[ "$1" =~ $pattern ]] ; then
                    echo "'$1' is not a good password; should be > 5 characters"
                    exit 1
                else
                    OMERO_INIT_PASS=$1
                fi
            else
                echo "No password specified"
                exit 1
            fi
            ;;
    esac
    shift
done

# set defaults if needed

if [[ -z "$OMERO_DATA_PATH" ]] ; then
    OMERO_DATA_PATH=~/omero/data
fi

if [[ -z "$OMERO_INIT_PASS" ]] ; then
    OMERO_INIT_PASS=Orionsbelt32
fi

ROOTPASS=$OMERO_INIT_PASS

#####################################
# Dependencies APT for OMERO.server #
#####################################

if [[ -n "$SHOULD_INSTALL" ]]; then
    sudo apt update
    sudo apt -y upgrade
    sudo apt -y install unzip bc wget cron git curl
    # build tools and dependencies
    sudo apt -y install build-essential openjdk-11-jdk python3 python3-venv
    # dependencies for Ice
    sudo apt -y install db5.3-util libbz2-dev libdb++-dev libdb-dev libexpat-dev libmcpp-dev libssl-dev mcpp zlib1g-dev
    # dependency postgresql
    # TODO: this is outdated: should install PostgreSQL 11
    sudo apt -y install postgresql
    sudo apt autoremove
fi

#####################
# Install ZeroC Ice #
#####################

ICE_NAME="ice-3.6.5-0.3.0"
ICE_TAR="$ICE_NAME-ubuntu1804-amd64.tar.gz"
if [[ ! -d "/opt/$ICE_NAME" ]]; then
    echo "Installing $ICE_NAME"
    if [[ ! -f "$ICE_TAR" ]]; then
        wget -q -P ~/ "https://github.com/ome/zeroc-ice-ubuntu1804/releases/download/0.3.0/$ICE_TAR"
    fi
    sudo tar xvf ~/"$ICE_TAR" -C /opt
    rm ~/"$ICE_TAR"
    sudo chown -R root:root /opt/$ICE_NAME
fi

if [[ ! -f /etc/ld.so.conf.d/ice-x86_64.conf ]] ; then
    echo "set $ICE_NAME libraries"
    echo /opt/"$ICE_NAME"/lib/x86_64-linux-gnu | sudo tee -a /etc/ld.so.conf.d/ice-x86_64.conf
    sudo chown root:root /etc/ld.so.conf.d/ice-x86_64.conf
    sudo ldconfig
fi

##################################
# Set initial .profile variables #
##################################

PROFILE_APPEND="""
# OMERO admin settings
OMERO_DB_USER=$(whoami)
OMERO_DB_PASS=$OMERO_INIT_PASS
OMERO_DB_NAME=omero_database
OMERO_ROOT_PASS=$OMERO_INIT_PASS
OMERO_DATA_DIR=$OMERO_DATA_PATH
export OMERO_DB_USER OMERO_DB_PASS OMERO_DB_NAME OMERO_ROOT_PASS OMERO_DATA_DIR
export PGPASSWORD=\$OMERO_DB_PASS

# OMERO AIM Users
AIM_GROUP=aim_data
AIM_PUBLIC_USER_NAME=aim_public
AIM_PUBLIC_USER_PASS=$OMERO_INIT_PASS

# Ice settings
export ICE_HOME=/opt/$ICE_NAME
export PATH+=:\$ICE_HOME/bin
export LD_LIBRARY_PATH+=:\$ICE_HOME/lib64:\$ICE_HOME/lib
export SLICEPATH=\$ICE_HOME/slice
"""

if ! grep -qxF "OMERO_DB_USER=$(whoami)" ~/.profile ; then
    echo "set OMERO variables in .profile"
    echo "$PROFILE_APPEND" >> ~/.profile
fi
source ~/.profile

#################################
# Install Python VENV for OMERO #
#################################

VENV_SERVER=$OMERO_PATH/venv_server
VENV_BIN=$VENV_SERVER/bin

if [[ ! -d "$VENV_SERVER" ]]; then
    echo "set Python VENV for OMERO"
    python3 -m venv $VENV_SERVER
fi

if [[ -n "$SHOULD_PIP_INSTALL" ]] && ! $VENV_BIN/pip freeze | grep -qx "zeroc-ice==[0-9\.]*$" ; then
    echo "Install zeroc-ice 3.6.* Python package"
    $VENV_BIN/pip install "https://github.com/ome/zeroc-ice-ubuntu1804/releases/download/0.3.0/zeroc_ice-3.6.5-cp36-cp36m-linux_x86_64.whl"
fi

if [[ -n "$SHOULD_PIP_INSTALL" ]] && ! $VENV_BIN/pip freeze | grep -qx "omero-py==[0-9\.]*$" ; then
    echo "Install omero-py 5.6.* Python package"
    $VENV_BIN/pip install "omero-py>=5.6.0"
fi

PROFILE_APPEND="""# Python VENV
VENV_SERVER=$VENV_SERVER
PATH=\$VENV_SERVER/bin:\$PATH
"""

if ! grep -qxF "VENV_SERVER=$VENV_SERVER" ~/.profile ; then
    echo "$PROFILE_APPEND" >> ~/.profile
fi
source ~/.profile

###################
# set up Postgres #
###################

# TODO: this is outdated: should install PostgreSQL 11 for better performance
# Postgres 10 still works fine though

if ! systemctl is-active --quiet postgresql ; then
    echo "starting PostgreSQL"
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
mkdir -p "$OMERO_DATA_DIR"

#########################
# install OMERO.insight #
#########################

OMERO_INSIGHT_SYMLINK="$OMERO_PATH/OMERO.insight"
if [[ ! -d "$OMERO_INSIGHT_SYMLINK" ]]; then
    echo "Installing OMERO.server"
    OMERO_INSIGHT="OMERO.insight-5.5.8"
    OMERO_INSIGHT_ZIP="$OMERO_INSIGHT.zip"
    if [[ ! -f "$OMERO_INSIGHT_ZIP" ]]; then
        wget -P ~/ "https://github.com/ome/omero-insight/releases/download/v5.5.8/$OMERO_INSIGHT_ZIP"
    fi
    unzip ~/"$OMERO_INSIGHT_ZIP" -d "$OMERO_PATH"
    ln -s "$OMERO_PATH/$OMERO_INSIGHT" "$OMERO_INSIGHT_SYMLINK"
    rm ~/"$OMERO_INSIGHT_ZIP"
fi

########################
# install OMERO.server #
########################

OMERO_SERVER_SYMLINK="$OMERO_PATH/OMERO.server"
if [[ ! -e "$OMERODIR" ]]; then
    echo "Installing OMERO.server"
    OMERO_SERVER="OMERO.server-5.6.0-ice36-b136"
    OMERO_SERVER_ZIP="$OMERO_SERVER.zip"
    if [[ ! -f ~/"$OMERO_SERVER_ZIP" ]]; then
       wget -P ~/ "https://downloads.openmicroscopy.org/omero/5.6.0/artifacts/$OMERO_SERVER_ZIP"
    fi
    unzip ~/"$OMERO_SERVER_ZIP" -d "$OMERO_PATH"
    ln -s "$OMERO_PATH/$OMERO_SERVER" "$OMERODIR"
    rm ~/"$OMERO_SERVER_ZIP"
fi

###########################
# Add executables to PATH #
###########################

# TODO: binaries are no longer stored in OMERO_INSIGHT_BIN; can remove
PROFILE_APPEND="""# OMERO binary paths
OMERO_SERVER_BIN=$OMERO_SERVER_SYMLINK/bin
OMERO_INSIGHT_BIN=$OMERO_INSIGHT_SYMLINK/bin
PATH+=:\$OMERO_INSIGHT_BIN:\$OMERO_SERVER_BIN
export OMERODIR=$OMERO_SERVER_SYMLINK
"""

if ! grep -qxF "OMERO_SERVER_BIN=$OMERO_PATH/OMERO.server/bin" ~/.profile ; then
    echo "$PROFILE_APPEND" >> ~/.profile
fi
source ~/.profile

#################
# Configuration #
#################

echo "OMERO.server DB config"
omero config set omero.data.dir "$OMERO_DATA_DIR"
omero config set omero.db.name "$OMERO_DB_NAME"
omero config set omero.db.user "$OMERO_DB_USER"
omero config set omero.db.pass "$OMERO_DB_PASS"
omero config set omero.glacier2.IceSSL.Ciphers HIGH:ADH:@SECLEVEL=0

############################
# Create Postgres database #
############################

# TODO: Not sure how to detect whether DB has been instantiated
DB_CREATION_SCRIPT="${OMERO_PATH}/OMERO.server/db.sql"
if [[ ! -f "$DB_CREATION_SCRIPT" ]] ; then
    echo "Instantiate DB in PostgreSQL"
    omero db script -f "$DB_CREATION_SCRIPT" --password "$OMERO_ROOT_PASS"
    psql -h localhost -U "$OMERO_DB_USER" "$OMERO_DB_NAME" < "$DB_CREATION_SCRIPT"
fi

###############################
# OMERO.server startup script #
###############################

OMERO_SERVICE_SCRIPT="""OMERODIR=$OMERO_SERVER_SYMLINK
ICE_HOME=/opt/$ICE_NAME
PATH=$VENV_BIN:/opt/$ICE_NAME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin
LD_LIBRARY_PATH=/opt/$ICE_NAME/lib64:/opt/$ICE_NAME/lib
export SLICEPATH=/opt/$ICE_NAME/slice
"""

sudo mkdir -p /etc/sysconfig
if [[ ! -f /etc/sysconfig/omero ]] ; then
    echo "Set up OMERO.server EnvironmentFile"
    echo "$OMERO_SERVICE_SCRIPT" | sudo tee /etc/sysconfig/omero > /dev/null
fi

OMERO_SERVER_SERVICE_SCRIPT="""
[Unit]
Description=Start the OMERO Server
After=syslog.target network.target

[Service]
User=$(whoami)
Group=$(whoami)
Type=oneshot
EnvironmentFile=-/etc/sysconfig/omero
ExecStart=$VENV_BIN/omero admin start
ExecStop=$VENV_BIN/omero admin stop
ExecReload=$VENV_BIN/omero admin restart
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
"""

OMERO_SERVICE="omero@$(whoami).service"
if [[ ! -f "/etc/systemd/system/$OMERO_SERVICE" ]] ; then
    echo "Set up OMERO.server Systemd service"
    echo "$OMERO_SERVER_SERVICE_SCRIPT" | sudo tee /etc/systemd/system/$OMERO_SERVICE > /dev/null
    sudo systemctl daemon-reload
fi

if ! systemctl is-active --quiet "omero@$(whoami)" ; then
    echo "Enable OMERO.server in Systemd"
    sudo systemctl enable "omero@$(whoami)"
    sudo systemctl start "omero@$(whoami)"
fi

#####################
# Install OMERO.web #
#####################

if [[ -n "$SHOULD_PIP_INSTALL" ]] && ! $VENV_BIN/pip freeze | grep -qx "omero-web==[0-9\.]*$" ; then
    echo "Install omero-web 5.6.* Python package"
    $VENV_BIN/pip install "omero-web>=5.6.1"
fi

if [[ -n "$SHOULD_PIP_INSTALL" ]] && ! $VENV_BIN/pip freeze | grep -qx "whitenoise==[0-9\.]*$" ; then
    echo "Install whitenoise <4 Python package"
    $VENV_BIN/pip install "whitenoise<4"
fi

omero config set omero.web.application_server wsgi-tcp
omero config set omero.web.application_server.max_requests 500
omero config set omero.web.wsgi_workers 13
omero config set omero.web.debug
! omero config get omero.web.middleware | grep -qF "whitenoise.middleware.WhiteNoiseMiddleware" && omero config append omero.web.middleware '{"index": 0, "class": "whitenoise.middleware.WhiteNoiseMiddleware"}'

#######################
# NGINX for OMERO.web #
#######################

if [[ -n "$SHOULD_INSTALL" ]]; then
    sudo apt -y install nginx
fi

NGINX_CONF=/etc/nginx/sites-available/omero-web
if [[ ! -f  "$NGINX_CONF" ]]; then
    echo "adding OMERO.web static files to NGINX"
    omero web config nginx --http 80 | sudo tee "$NGINX_CONF" > /dev/null
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo ln -s "$NGINX_CONF" /etc/nginx/sites-enabled
    sudo nginx -t
    sudo systemctl restart nginx
fi

############################
# OMERO.web startup script #
############################

OMERO_WEB_SERVICE_SCRIPT="""OMERODIR=$OMERO_SERVER_SYMLINK
PATH=$VENV_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
"""

sudo mkdir -p /etc/sysconfig
if [[ ! -f /etc/sysconfig/omero-web ]] ; then
    echo "creating OMERO.web service environmental variables"
    echo "$OMERO_WEB_SERVICE_SCRIPT" | sudo tee /etc/sysconfig/omero-web > /dev/null
fi

OMERO_WEB_SERVICE_SCRIPT="""
[Unit]
Description=Start the OMERO Web
After=syslog.target network.target omero@$(whoami).service

[Service]
User=$(whoami)
Group=$(whoami)
Type=oneshot
EnvironmentFile=-/etc/sysconfig/omero-web
ExecStart=$VENV_BIN/omero web start
ExecStop=$VENV_BIN/omero web stop
ExecReload=$VENV_BIN/omero web restart
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
"""

OMERO_WEB_SERVICE="omero-web@$(whoami).service"
if [[ ! -f "/etc/systemd/system/$OMERO_WEB_SERVICE" ]] ; then
    echo "creating OMERO.web service"
    echo "$OMERO_WEB_SERVICE_SCRIPT" | sudo tee /etc/systemd/system/$OMERO_WEB_SERVICE > /dev/null
    sudo systemctl daemon-reload
fi

if ! systemctl is-active --quiet "omero-web@$(whoami)" ; then
    echo "enabling OMERO.web systemd service"
    sudo systemctl enable "omero-web@$(whoami)"
    sudo systemctl start "omero-web@$(whoami)"
fi

############################
# Install N (Node.js, NPM) #
############################

# N (Node.js, NPM) is required for webapps to run.
# It is better to install these as local user and add them
# to user path to avoid using sudo and enabling security risks

if [[ ! -d ~/prog/n ]] ; then
    echo "installing N Node.js version manager"
    curl -L "https://git.io/n-install" | N_PREFIX=~/prog/n bash
fi

PROFILE_APPEND="""
# N binary path
N_BIN=$HOME/prog/n/bin
PATH+=:\$N_BIN
"""
if ! grep -qxF "N_BIN=$HOME/prog/n/bin" ~/.profile ; then
    echo "$PROFILE_APPEND" >> ~/.profile
fi
source ~/.profile

########################
# AIMViewer Django app #
########################

AIMVEWER_PATH=~/code/aimviewer
if [[ ! -d "$AIMVEWER_PATH" ]] ; then
    echo "installing AIMViewer"
    mkdir -p ~/code
    git clone "https://github.com/fireofearth/aimviewer.git"
    cd "$AIMVEWER_PATH/frontend/annotator"
    npm install
    # requires HTML folder to not be in static dir
    npm run build
    $VENV_BIN/pip install -e "$AIMVIEWER_PATH"
    cd
fi

! omero config get omero.web.apps | grep -qF "\"aimviewer\"" && omero config append omero.web.apps '"aimviewer"'
if ! omero config get omero.web.open_with | grep -qF "[\"AIM annotator\", \"aimviewer\", {\"supported_objects\": [\"image\"], \"script_url\": \"aimviewer/openwith_viewer.js\"}]" ; then
    omero config append omero.web.open_with "[\"AIM annotator\", \"aimviewer\", {\"supported_objects\": [\"image\"], \"script_url\": \"aimviewer/openwith_viewer.js\"}]"
fi
omero config set omero.web.viewer.view aimviewer.views.main_annotator

# TODO: set up cache, users, public user, and other web app variables