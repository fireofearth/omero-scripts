# omero-scripts

The most updated scfript is `omero-scripts/install-5.6/setup.sh` which installs OMERO.server 5.6.x.

## Specs

Requires basic (preferably clean) Ubuntu 18.04 install (with systemd).

## What I do

```
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
Commandline arguments:

--help, -h   show this help message and quit
--deps       (optional) to update this machine and install all APT dependencies
--pip        (optional) to pip install Python dependencies
--npm        (optional) to npm install NPM dependencies
--data-path  (optional) path to OMERO.server data directory (default: ~/omero/data)
--omero-pass (optional) OMERO.server root password. Please use this for production servers (default: Orionsbelt32)

File arguments: groups and users specified in the header included CSV files ./group_list.csv and ./user_list.csv will be added to OMERO.server. Please set user passwords in production servers.
```

For a full installation with one command do

```
bash setup.sh --deps --pip --npm --omero-pass <ROOT PASSWORD>
```

## Contributions

Much of this script is based on [Lucas Lianas](https://github.com/lucalianas) and [CRS4](https://github.com/crs4/ome_seadragon) Dockerfiles. I thank them for providing OME Seadragon, their help and the Docker images. Of course I also thank the [OME Team](https://www.openmicroscopy.org/omero/) for creating the OMERO distribution for Pathology image administration.
