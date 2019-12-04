# omero-scripts

## Specs

Requires Ubuntu 18.04 with systemd

## What I do

```
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
Ice:           RPC framework; not sure if this is really necessary
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
```

For a full installation with one command do

```
bash setup.sh --deps --pip --npm
```
