#!bin/bash

set -e

echo "Running script as $(whoami)"

OMERO_PATH=~/prog/omero
OMERO_DATA_PATH=~/hdd/omero/data
OMERO_INIT_PASS=Orionsbelt32

ROOTPASS=$OMERO_INIT_PASS
OMEROHOST=localhost
OMEROPORT=4064

HELP="""
The AIM Install Script for OMERO.server + OMERO.web + OME Seadragon
Installs everything(!) to a newly installed Ubuntu 18.04 computer with systemd. Directories / files will be directly modified or created by these apps:

/opt/Ice-3.6.4              # Ice RPC framework
/etc/sysconfig              # environmental variables for startup scripts
/etc/systemd/system         # add startup scripts
~/.profile                  # modified PATH variable, etc
~/prog/n                    # the Node.js version manager
~/prog/omero/data           # data stored by OMERO.server
~/prog/omero/OMERO.server
~/prog/omero/OMERO.insight
~/prog/omero/web_plugins/ome_seadragon
~/.local/<python stuff>     # adds various local Python libraries

It will install the programs:

OMERO.server:  the OMERO server
OMERO.insight: the Java client for OMERO
Ice:           RPC framework
postgresql:    metadata for OMERO.server
ome_seadragon: integration for OpenSlide and OMERO
redis:         image cache for OME Seadragon
nginx:         serves files for OMERO.web and plugins
N:             Node.js + NPM version manager used for Grunt and other front-end compilation tasks

It will not repeat installation tasks already done previously so this script can be run multiple times for whatever reason.

--help, -h  show this help message and quit
--deps      to update this machine and install all APT dependencies
--pip       to pip install Python dependencies
--npm       to npm install NPM dependencies
"""

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
    esac
    shift
done

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
fi

#####################
# Install ZeroC Ice #
#####################

ICE_NAME="ice-3.6.5-0.3.0"
ICE_TAR="$ICE_NAME-ubuntu1804-amd64.tar.gz"
if [[ ! -d /opt/Ice-3.6.5 ]]; then
    echo "Installing $ICE_NAME"
    if [[ ! -f "$ICE_TAR" ]]; then
        wget -P ~/ "https://github.com/ome/zeroc-ice-ubuntu1804/releases/download/0.3.0/$ICE_TAR"
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
if [[ ! -d "$VENV_SERVER" ]]; then
    echo "set Python VENV for OMERO"
    python -m venv $VENV_SERVER
fi

VENV_BIN=$VENV_SERVER/bin
if [[ -n "$SHOULD_PIP_INSTALL" ]] && ! $VENV_BIN/pip freeze | grep -qx "zeroc-ice==[0-9\.]*$" ; then
    echo "Install zeroc-ice 3.6.* Python package"
    $VENV_SERVER/pip install "https://github.com/ome/zeroc-ice-ubuntu1804/releases/download/0.3.0/zeroc_ice-3.6.5-cp36-cp36m-linux_x86_64.whl"
fi

if [[ -n "$SHOULD_PIP_INSTALL" ]] && ! $VENV_BIN/pip freeze | grep -qx "omero-py==[0-9\.]*$" ; then
    echo "Install omero-py 5.6.* Python package"
    $VENV_SERVER/pip install "omero-py>=5.6.0"
fi

PROFILE_APPEND="""# Python VENV
VENV_SERVER=$VENV_SERVER
export PATH+=:\$VENV_SERVER/bin
"""

if ! grep -qxF "VENV_SERVER=$VENV_SERVER" ~/.profile ; then
    echo "$PROFILE_APPEND" >> ~/.profile
fi
source ~/.profile

###################
# set up Postgres #
###################

# TODO: this is outdated: should install PostgreSQL 11

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

# TODO: is OMERO.insight 5.5.6 compatible? What about 5.5.8?
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

OMERODIR="$OMERO_PATH/OMERO.server"
if [[ ! -d "$OMERO_PATH/$OMERO_SERVER" ]]; then
    OMERO_FILE="OMERO.server-5.6.0-ice36-b136"
    OMERO_FILE_ZIP="$OMERO_FILE.zip"
    if [[ ! -f ~/"$OMERO_FILE_ZIP" ]]; then
       wget -P ~/ "https://downloads.openmicroscopy.org/omero/5.6.0/artifacts/$OMERO_FILE_ZIP"
    fi
    unzip ~/"$OMERO_FILE_ZIP" -d "$OMERO_PATH"
    ln -s "$OMERO_PATH/$OMERO_FILE"
    rm ~/"$OMERO_FILE_ZIP"
fi

###########################
# Add executables to PATH #
###########################

PROFILE_APPEND="""# OMERO binary paths
OMERO_SERVER_BIN=$OMERO_PATH/OMERO.server/bin
OMERO_INSIGHT_BIN=$OMERO_PATH/OMERO.insight/bin
PATH+=:\$OMERO_INSIGHT_BIN:\$OMERO_SERVER_BIN
export OMERODIR=$OMERODIR
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

exit 0

############################
# Create Postgres database #
############################

# TODO: Not sure how to detect whether DB has been instantiated
echo "Instantiate DB in PostgreSQL"
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

OMERO_SERVER_SERVICE_SCRIPT="""
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
    echo "$OMERO_SERVER_SERVICE_SCRIPT" | sudo tee /etc/systemd/system/$OMERO_SERVICE > /dev/null
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

if [[ -n "$SHOULD_INSTALL" ]]; then
    sudo apt -y install nginx
fi

if [[ -n "$SHOULD_PIP_INSTALL" ]]; then
    pip install -r "$OMERO_PATH/OMERO.server/share/web/requirements-py27.txt"
fi

omero config set omero.web.application_server wsgi-tcp

NGINX_CONF_TMP="$OMERO_PATH/OMERO.server/nginx.conf.tmp"
NGINX_CONF=/etc/nginx/sites-available/omero-web
if [[ ! -f  "$NGINX_CONF" ]]; then
    echo "adding OMERO.web static files to NGINX"
    omero web config nginx --http 80 > "$NGINX_CONF_TMP"
    sudo cp "$NGINX_CONF_TMP" "$NGINX_CONF"
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo ln -s "$NGINX_CONF" /etc/nginx/sites-enabled
    sudo systemctl restart nginx
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

#####################
# OMERO Web plugins #
#####################

echo "set up OMERO.web plugins path"
WEB_PLUGINS_PATH="$OMERO_PATH/web_plugins"
mkdir -p "$WEB_PLUGINS_PATH"
PROFILE_APPEND="""
# OMERO web plugins path
WEB_PLUGINS_PATH=$WEB_PLUGINS_PATH
export PYTHONPATH+=:\$WEB_PLUGINS_PATH
"""
if ! grep -qxF "export PYTHONPATH+=:\$WEB_PLUGINS_PATH" ~/.profile ; then
    echo "$PROFILE_APPEND" >> ~/.profile
fi
source ~/.profile
if [[ -n "$SHOULD_NPM_INSTALL" ]] ; then
    npm install -g grunt
fi

######################################
# Install OME Seadragon dependencies #
######################################

# Redis is key/value store and is used for image caching

if [[ -n "$SHOULD_INSTALL" ]]; then
    sudo apt install -y redis
    sudo apt install -y openslide-tools
fi

####################################
# Download and setup OME Seadragon #
####################################

OME_SEADRAGON_VERSION=0.6.16
OME_SEADRAGON_PATH="$WEB_PLUGINS_PATH/ome_seadragon"
OME_SEADRAGON_ZIP=~/"v${OME_SEADRAGON_VERSION}.zip"
if [[ ! -d "$OME_SEADRAGON_PATH" ]] ; then
    echo "downloading OME Seadragon plugin"
    if [[ ! -f "$OME_SEADRAGON_ZIP" ]] ; then
        wget -P ~/ "https://github.com/crs4/ome_seadragon/archive/v${OME_SEADRAGON_VERSION}.zip"
    fi
    unzip "$OME_SEADRAGON_ZIP" -d "$WEB_PLUGINS_PATH"
    mv "$WEB_PLUGINS_PATH/ome_seadragon"{-${OME_SEADRAGON_VERSION},}
fi

if [[ -n "$SHOULD_PIP_INSTALL" ]] ; then
    pip install -r "$OME_SEADRAGON_PATH/requirements.txt"
fi

cd "$OME_SEADRAGON_PATH"
if [[ -n "$SHOULD_NPM_INSTALL" ]] ; then
    npm install
fi
grunt
cd

! omero config get omero.web.apps | grep -qF "\"ome_seadragon\"" && omero config append omero.web.apps '"ome_seadragon"'
omero config set omero.web.session_cookie_name ome_seadragon_web

#######################
# Enable CORS headers #
#######################

echo "setting the corsheaders Django middleware in OMERO.web"
! omero config get omero.web.apps | grep -qF "\"corsheaders\"" && omero config append omero.web.apps '"corsheaders"'
CORS_MIDDLEWARE='{"index": 0.5, "class": "corsheaders.middleware.CorsMiddleware"}'
! omero config get omero omero.web.middleware | grep -qF "\"$CORS_MIDDLEWARE\"" && omero config append omero.web.middleware "$CORS_MIDDLEWARE"
CORS_POST_CSF_MIDDLEWARE='{"index": 10, "class": "corsheaders.middleware.CorsPostCsrfMiddleware"}'
omero config get omero.web.middleware | grep -qF "\"$CORS_POST_CSF_MIDDLEWARE\"" && omero config append omero.web.middleware "$CORS_POST_CSF_MIDDLEWARE"

echo "no CORS whitelist, ALLOWING ALL HOSTS"
omero config set omero.web.cors_origin_allow_all True

################################################
# Create a OMERO public user for OME Seadragon #
################################################


echo "creating user group for OME Seadragon"
omero group add --ignore-existing --server "$OMEROHOST" \
    --port "$OMEROPORT" \
    --user root \
    --password "$ROOTPASS" \
    --type read-annotate "$AIM_GROUP"

echo "Creating PathViewer public user"
omero user add --ignore-existing --server "$OMEROHOST" \
    --port "$OMEROPORT" \
    --user root \
    --password "$ROOTPASS" \
    "$AIM_PUBLIC_USER_NAME" AIM PUBLIC \
    --group-name "$AIM_GROUP" \
    --userpassword "$AIM_PUBLIC_USER_PASS"

echo "Setup OMERO public user in omero.web.public settings"
URL_FILTER="^/ome_seadragon"
omero config set omero.web.public.enabled True
omero config set omero.web.public.user "$AIM_PUBLIC_USER_NAME"
omero config set omero.web.public.password "$AIM_PUBLIC_USER_PASS"
omero config set omero.web.public.url_filter "$URL_FILTER"
omero config set omero.web.public.server_id 1
echo "Setup OMERO public user in omero.web.ome_seadragon settings"
omero config set omero.web.ome_seadragon.ome_public_user "$AIM_PUBLIC_USER_NAME"

##########################################
# Setup Redis image cache and repository #
##########################################

REDISHOST=localhost
REDISPORT=6379
REDISDB=0
CACHE_EXPIRE_TIME='{"hours": 8}'

echo "Setup REDIS cache in omero.web.ome_seadragon settings"
omero config set omero.web.ome_seadragon.images_cache.cache_enabled True
omero config set omero.web.ome_seadragon.images_cache.driver 'redis'
omero config set omero.web.ome_seadragon.images_cache.host "$REDISHOST"
omero config set omero.web.ome_seadragon.images_cache.port "$REDISPORT"
omero config set omero.web.ome_seadragon.images_cache.database "$REDISDB"
omero config set omero.web.ome_seadragon.images_cache.expire_time "$CACHE_EXPIRE_TIME"
omero config set omero.web.ome_seadragon.repository "$OMERO_DATA_DIR"

############################
# OMERO.web startup script #
############################

OMERO_WEB_SERVICE_SCRIPT="""
PATH=$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin
PYTHONPATH=$WEB_PLUGINS_PATH
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
ExecStart=$OMERO_PATH/OMERO.server/bin/omero web start
ExecStop=$OMERO_PATH/OMERO.server/bin/omero web stop
ExecReload=$OMERO_PATH/OMERO.server/bin/omero web restart
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

exit
