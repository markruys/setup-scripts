#!/bin/bash

# Original script done by Don Darling
# Later changes by Koen Kooi and Brijesh Singh

# Revision history:
# 20090902: download from twice
# 20090903: Weakly assign MACHINE and DISTRO
# 20090904:  * Don't recreate local.conf is it already exists
#            * Pass 'unknown' machines to OE directly
# 20090918: Fix /bin/env location
#           Don't pass MACHINE via env if it's not set
#           Changed 'build' to 'bitbake' to prepare people for non-scripted usage
#           Print bitbake command it executes
# 20091012: Add argument to accept commit id.
# 20091202: Fix proxy setup

###############################################################################
# User specific vars like proxy servers
###############################################################################

#PROXYHOST=wwwgate.ti.com
#PROXYPORT=80

###############################################################################
# OE_BASE    - The root directory for all OE sources and development.
###############################################################################
OE_BASE=${PWD}

###############################################################################
# SET_ENVIRONMENT() - Setup environment variables for OE development
###############################################################################
function set_environment()
{
    #--------------------------------------------------------------------------
    # Specify distribution information
    #--------------------------------------------------------------------------
    DISTRO="angstrom-2008.1"
    DISTRO_DIRNAME=`echo $DISTRO | sed s#[.-]#_#g`

    #--------------------------------------------------------------------------
    # Specify the root directory for your OpenEmbedded development
    #--------------------------------------------------------------------------
    OE_BUILD_DIR=${OE_BASE}/build
    OE_BUILD_TMPDIR="${OE_BUILD_DIR}/tmp-${DISTRO_DIRNAME}"
    OE_SOURCE_DIR=${OE_BASE}/sources
    mkdir -p ${OE_BUILD_DIR}
    mkdir -p ${OE_SOURCE_DIR}
    export OE_BASE

    #--------------------------------------------------------------------------
    # Include up-to-date bitbake in our PATH.
    #--------------------------------------------------------------------------
    export PATH=${OE_SOURCE_DIR}/bitbake/bin:${PATH}

    #--------------------------------------------------------------------------
    # Make sure Bitbake doesn't filter out the following variables from our
    # environment.
    #--------------------------------------------------------------------------
    export BB_ENV_EXTRAWHITE="MACHINE DISTRO http_proxy ftp_proxy no_proxy GIT_PROXY_COMMAND"

    #--------------------------------------------------------------------------
    # Specify proxy information
    #--------------------------------------------------------------------------
    if [ -n $PROXYHOST ] ; then
        export http_proxy=http://${PROXYHOST}:${PROXYPORT}/
        export ftp_proxy=http://${PROXYHOST}:${PROXYPORT}/

        export SVN_CONFIG_DIR=${OE_BUILD_DIR}/subversion_config
        export GIT_CONFIG_DIR=${OE_BUILD_DIR}/git_config

        config_svn_proxy
        config_git_proxy
	fi

    #--------------------------------------------------------------------------
    # Set up the bitbake path to find the OpenEmbedded recipes.
    #--------------------------------------------------------------------------
    export BBPATH=${OE_BUILD_DIR}:${OE_SOURCE_DIR}/org.openembedded.dev${BBPATH_EXTRA}
    
	#--------------------------------------------------------------------------
    # Reconfigure dash 
    #--------------------------------------------------------------------------
    if [ $(readlink /bin/sh) = "dash" ] ; then
        sudo dpkg-reconfigure dash
    fi

}


###############################################################################
# UPDATE_ALL() - Make sure everything is up to date
###############################################################################
function update_all()
{
    set_environment
    update_bitbake
    update_oe
}


###############################################################################
# OE_BUILD() - Build an OE package or image
###############################################################################
function oe_build()
{
    set_environment
    cd ${OE_BUILD_DIR}
    if [ -z $MACHINE ] ; then
        echo "Executing: bitbake" $*
        bitbake $*
    else
        echo "Executing: MACHINE=${MACHINE} bitbake" $*
        MACHINE=${MACHINE} bitbake $*
    fi
}


###############################################################################
# OE_CONFIG() - Configure OE for a target 
###############################################################################
function oe_config()
{
    set_environment
    config_oe
}


###############################################################################
# UPDATE_BITBAKE() - Update Bitbake distribution
###############################################################################
function update_bitbake()
{
    if [ -n $PROXYHOST ] ; then
        config_git_proxy
    fi

    if [ ! -d ${OE_SOURCE_DIR}/bitbake ]; then
        echo Checking out bitbake
        git clone git://git.openembedded.net/bitbake ${OE_SOURCE_DIR}/bitbake
        cd ${OE_SOURCE_DIR}/bitbake && git checkout -b 1.8 origin/1.8
    else
        cd ${OE_SOURCE_DIR}/bitbake && git pull --rebase
    fi
}


###############################################################################
# UPDATE_OE() - Update OpenEmbedded distribution.
###############################################################################
function update_oe()
{
    config_git_proxy

    if [ ! -d  ${OE_SOURCE_DIR}/org.openembedded.dev ]; then
        echo Checking out OpenEmbedded
        git clone "git://git.openembedded.net/openembedded" ${OE_SOURCE_DIR}/org.openembedded.dev
        cd ${OE_SOURCE_DIR}/org.openembedded.dev
        if [ ! -r ${COMMIT_ID} ]; 
        then
            echo "Checkout commit id: ${COMMIT_ID}"
            git checkout -b install ${COMMIT_ID}
        else
            git checkout -b org.openembedded.dev origin/org.openembedded.dev
        fi
    else
        echo Updating OpenEmbedded
        cd ${OE_SOURCE_DIR}/org.openembedded.dev
        git pull --rebase 
    fi
}


###############################################################################
# CONFIG_OE() - Configure OpenEmbedded
###############################################################################
function config_oe()
{
    #--------------------------------------------------------------------------
    # Determine the proper machine name
    #--------------------------------------------------------------------------
    case ${CL_MACHINE} in
        beagle)
            MACHINE="beagleboard"
            ;;
        dm6446evm)
            MACHINE="davinci-dvevm"
            ;;
        omap3evm)
            MACHINE="omap3evm"
            ;;
        shiva)
            MACHINE="omap3517-evm"
            ;;
        *)
            echo "Unknown machine ${CL_MACHINE}, passing it to OE directly"
            MACHINE="${CL_MACHINE}"
            ;;
    esac

    #--------------------------------------------------------------------------
    # Write out the OE bitbake configuration file.
    #--------------------------------------------------------------------------
    mkdir -p ${OE_BUILD_DIR}/conf

    # There's no need to rewrite local.conf when changing MACHINE
    if [ ! -e ${OE_BUILD_DIR}/conf/local.conf ]; then
        cat > ${OE_BUILD_DIR}/conf/local.conf <<_EOF
# Where to store sources
DL_DIR = "${OE_BUILD_DIR}/downloads"

INHERIT += "rm_work"

# Which files do we want to parse:
BBFILES := "${OE_SOURCE_DIR}/org.openembedded.dev/recipes/*/*.bb"
BBMASK = ""

# What kind of images do we want?
IMAGE_FSTYPES += "tar.bz2"

# Make use of my SMP box
#PARALLEL_MAKE     = "-j3"
BB_NUMBER_THREADS = "2"

DISTRO   = "${DISTRO}"
MACHINE ?= "${MACHINE}"

# Set TMPDIR instead of defaulting it to $pwd/tmp
TMPDIR = "${OE_BUILD_TMPDIR}"

# Work around qemu segfault issues
ENABLE_BINARY_LOCALE_GENERATION = "0"

# Go through the Firewall
#HTTP_PROXY        = "http://${PROXYHOST}:${PROXYPORT}/"

# Extra packages to include
#ANGSTROM_EXTRA_INSTALL=""

_EOF
fi
}

###############################################################################
# CONFIG_SVN_PROXY() - Configure subversion proxy information
###############################################################################
function config_svn_proxy()
{
    if [ ! -f ${SVN_CONFIG_DIR}/servers ]
    then
        mkdir -p ${SVN_CONFIG_DIR}
        cat >> ${SVN_CONFIG_DIR}/servers <<_EOF
[global]
http-proxy-host = ${PROXYHOST}
http-proxy-port = ${PROXYPORT}
_EOF
    fi
}


###############################################################################
# CONFIG_GIT_PROXY() - Configure GIT proxy information
###############################################################################
function config_git_proxy()
{
    if [ ! -f ${GIT_CONFIG_DIR}/git-proxy.sh ]
    then
        mkdir -p ${GIT_CONFIG_DIR}
        cat > ${GIT_CONFIG_DIR}/git-proxy.sh <<_EOF
if [ -x /bin/env ] ; then
    exec /bin/env corkscrew ${PROXYHOST} ${PROXYPORT} \$*
else
    exec /usr/bin/env corkscrew ${PROXYHOST} ${PROXYPORT} \$*
fi
_EOF
        chmod +x ${GIT_CONFIG_DIR}/git-proxy.sh
    fi
    export GIT_PROXY_COMMAND=${GIT_CONFIG_DIR}/git-proxy.sh
}


###############################################################################
# Build the specified OE packages or images.
###############################################################################
if [ $# -gt 0 ]
then
    if [ $1 = "update" ]
    then
        shift
        if [ ! -r $1 ]; then
            if [  $1 == "commit" ]
            then
                shift
                COMMIT_ID=$1
            fi
        fi
        update_all
        exit 0
    fi

    if [ $1 = "bitbake" ]
    then
        shift
        oe_build $*
        exit 0
    fi

    if [ $1 = "config" ]
    then
        shift
        CL_MACHINE=$1
        shift
        oe_config $*
        exit 0
    fi
fi

# Help Screen
echo ""
echo "Usage: $0 config <machine>"
echo "       $0 update"
echo "       $0 bitbake <bitbake target>"
echo ""
echo "You must invoke \"$0 config <machine>\" and then \"$0 update\" prior"
echo "to your first bitbake command"
echo ""
echo "The <machine> argument can be one of the following"
echo "       beagle:    BeagleBoard"
echo "       dm6446evm: DM6446 EVM"
echo "       omap3evm:  OMAP35x EVM"
echo "       shiva:     OMAP3517 EVM"
echo ""
echo "Other machines are valid as well, but listing those would make this message way too long"
