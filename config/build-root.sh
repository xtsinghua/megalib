#!/bin/bash

# This file is part of MEGAlib.
# Copyright (C) by Andreas Zoglauer.
#
# Please see the MEGAlib software license and documentation for more informations.


CONFIGUREOPTIONS="--gminimal --enable-asimage --enable-xft --enable-opengl --enable-mathmore --enable-minuit2 --enable-explicitlink --enable-rpath --enable-soversion"
# In case you have trouble with anything related to freetype, try to comment in this option
# CONFIGUREOPTIONS="${CONFIGUREOPTIONS} --enable-builtin-freetype"
COMPILEROPTIONS=`gcc --version | head -n 1`


# Check if some of the frequently used software is installed:
type curl >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: curl must be installed"
    exit 1
fi 


confhelp() {
  echo ""
  echo "Building ROOT"
  echo " " 
  echo "Usage: ./build-root.sh [options]";
  echo " "
  echo " "
  echo "Options:"
  echo "--tarball=[file name of ROOT tar ball]"
  echo "    Use this tarball instead of downloading it from the ROOT website" 
  echo " "
  echo "--environment-script=[file name of new environment script]"
  echo "    File in which the ROOT path is stored. This is used by the MEGAlib setup script" 
  echo " "
  echo "--debug=[off/no, on/yes, strong/hard]"
  echo "    Default is on."
  echo " "
  echo "--maxthreads=[integer >=1]"
  echo "    The maximum number of threads to be used for compilation. Default is the number of cores in your system."
  echo " "
  echo "--help or -h"
  echo "    Show this help."
  echo " "
  echo " "
}

# Store command line
CMD=""
while [[ $# -gt 0 ]] ; do
    CMD="${CMD} $1"
    shift
done

# Check for help
for C in ${CMD}; do
  if [[ ${C} == *-h* ]]; then
    echo ""
    confhelp
    exit 0
  fi
done

TARBALL=""
ENVFILE=""
MAXTHREADS=1024
DEBUG="off"
DEBUGSTRING=""
DEBUGOPTIONS=""

# Overwrite default options with user options:
for C in ${CMD}; do
  if [[ ${C} == *-t*=* ]]; then
    TARBALL=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-e*=* ]]; then
    ENVFILE=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-m*=* ]]; then
    MAXTHREADS=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-d*=* ]]; then
    DEBUG=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-h* ]]; then
    echo ""
    confhelp
    exit 0
  else
    echo ""
    echo "ERROR: Unknown command line option: ${C}"
    echo "       See \"$0 --help\" for a list of options"
    echo " "
    exit 1
  fi
done

echo ""
echo ""
echo ""
echo "Setting up ROOT..."
echo ""
echo "Verifying chosen configuration options:"
echo ""

if [ "${TARBALL}" != "" ]; then
  if [[ ! -f "${TARBALL}" ]]; then
    echo "ERROR: The chosen tarball cannot be found: ${TARBALL}"
    exit 1     
  else   
    echo " * Using this tarball: ${TARBALL}"    
  fi
fi

if [ "${ENVFILE}" != "" ]; then
  if [[ ! -f "${ENVFILE}" ]]; then
    echo "ERROR: The chosen environment file cannot be found: ${ENVFILE}"
    exit 1     
  else   
    echo " * Using this environment file: ${ENVFILE}"    
  fi
fi


if [ ! -z "${MAXTHREADS##[0-9]*}" ] 2>/dev/null; then
  echo "ERROR: The maximum number of threads must be number and not ${MAXTHREADS}!"
  exit 1
fi  
if [ "${MAXTHREADS}" -le "0" ]; then
  echo "ERROR: The maximum number of threads must be at least 1 and not ${MAXTHREADS}!"
  exit 1
else 
  echo " * Using this maximum number of threads: ${MAXTHREADS}"
fi


if ( [[ ${DEBUG} == of* ]] || [[ ${DEBUG} == no ]] ); then
  DEBUG="off"
  DEBUGSTRING=""
  DEBUGOPTIONS=""
  echo " * Using no debugging code"
elif ( [[ ${DEBUG} == on ]] || [[ ${DEBUG} == y* ]] || [[ ${DEBUG} == nor* ]] ); then
  DEBUG="normal"
  DEBUGSTRING="_debug"
  DEBUGOPTIONS="--build=debug"
  echo " * Using debugging code"
else
  echo "ERROR: Unknown debugging code selection: ${DEBUG}"
  confhelp
  exit 0
fi


echo " "
echo " "
echo "Getting ROOT..."
VER=""
ROOTTOPDIR=""
if [ "${TARBALL}" != "" ]; then
  # Use given ROOT tarball
  echo "The given ROOT tarball is ${TARBALL}"
  
  # Determine the name of the top level directory in the tar ball
  ROOTTOPDIR=`tar tzf ${TARBALL} | sed -e 's@/.*@@' | uniq`
  RESULT=$?
  if [ "${RESULT}" != "0" ]; then
    echo "ERROR: Cannot find top level directory in the tar ball!"
    exit 1
  fi
  
  # Check if it has the correct version:
  VER=`tar xfzO ${TARBALL} ${ROOTTOPDIR}/build/version_number | sed 's|/|.|g'`
  RESULT=$?
  if [ "${RESULT}" != "0" ]; then
    echo "ERROR: Something went wrong unpacking the ROOT tarball!"
    exit 1
  fi
  if echo ${VER} | grep -E '[ "]' >/dev/null; then
    echo "ERROR: Something terrible is wrong with your version string..."
    exit 1
  fi
  echo "Version of ROOT is: ${VER}"
  
  bash ${MEGALIB}/config/check-rootversion.sh --good-version=${VER}
  if [ "$?" != "0" ]; then
    echo "ERROR: The ROOT tarball you supplied does not contain an acceptable ROOT version!"
    exit 1
  fi
else
  # Download it
  
  # Get desired version:
  WANTEDVERSION=`bash ${MEGALIB}/config/check-rootversion.sh --get-max`
  if [ "$?" != "0" ]; then
    echo "ERROR: Unable to determine required ROOT version!"
    exit 1
  fi
  echo "Looking for ROOT version ${WANTEDVERSION} with latest patch on the ROOT website --- sometimes this takes a few minutes..."
  
  # Now check root repository for the given version:
  TARBALL=`curl ftp://root.cern.ch/root/ -sl | grep "^root_v${WANTEDVERSION}" | grep "source.tar.gz$" | sort | tail -n 1`
  if [ "${TARBALL}" == "" ]; then
    echo "ERROR: Unable to find suitable ROOT tar ball at the ROOT website"
    exit 1
  fi
  echo "Using ROOT tar ball ${TARBALL}"
  
  # Check if it already exists locally
  REQUIREDOWNLOAD="true"
  if [ -f ${TARBALL} ]; then
    # ... and has the same size
    LOCALSIZE=`wc -c < ${TARBALL} | tr -d ' '`
    SAMESIZE=`curl --head ftp://root.cern.ch/root/${TARBALL}`
    if [ "$?" != "0" ]; then
      echo "ERROR: Unable to determine remote tarball size"
      exit 1
    fi
    SAMESIZE=`echo ${SAMESIZE} | grep ${LOCALSIZE}`
    if [ "${SAMESIZE}" != "" ]; then
      REQUIREDOWNLOAD="false"
      echo "File is already present and has same size, thus no download required!"
    fi
  fi
  
  if [ "${REQUIREDOWNLOAD}" == "true" ]; then
    curl -O ftp://root.cern.ch/root/${TARBALL}
    if [ "$?" != "0" ]; then
      echo "ERROR: Unable to download the tarball from the ROOT website!"
      exit 1
    fi
  fi

  # Determine the name of the top level directory in the tar ball
  ROOTTOPDIR=`tar tzf ${TARBALL} | sed -e 's@/.*@@' | uniq`
  RESULT=$?
  if [ "${RESULT}" != "0" ]; then
    echo "ERROR: Cannot find top level directory in the tar ball!"
    exit 1
  fi
  
  VER=`tar xfzO ${TARBALL} ${ROOTTOPDIR}/build/version_number | sed 's|/|.|g'`
  if [ "$?" != "0" ]; then
    echo "ERROR: Something went wrong unpacking the ROOT tarball!"
    exit 1
  fi
  if echo ${VER} | grep -E '[ "]' >/dev/null; then
    echo "ERROR: Something terrible is wrong with your version string..."
    exit 1
  fi
  echo "Version of ROOT is: ${VER}"
fi

ROOTDIR=root_v${VER}${DEBUGSTRING}

echo "Checking for old installation..."
if [ -d ${ROOTDIR} ]; then
  cd ${ROOTDIR}
  if [ -f COMPILE_SUCCESSFUL ]; then
    SAMEOPTIONS=`cat COMPILE_SUCCESSFUL | grep -- "${CONFIGUREOPTIONS}"`
    if [ "${SAMEOPTIONS}" == "" ]; then
      echo "The old installation used different compilation options..."
    fi
    SAMECOMPILER=`cat COMPILE_SUCCESSFUL | grep -- "${COMPILEROPTIONS}"`
    if [ "${SAMECOMPILER}" == "" ]; then
      echo "The old installation used a different compiler..."
    fi
    if ( [ "${SAMEOPTIONS}" != "" ] && [ "${SAMECOMPILER}" != "" ] ); then
      echo "Your already have a usable ROOT version installed!"
      if [ "${ENVFILE}" != "" ]; then
        echo "Storing the ROOT directory in the MEGAlib source script..."
        echo "ROOTDIR=`pwd`" >> ${ENVFILE}
      fi
      exit 0
    fi
  fi
    
  echo "Old installation is either incompatible or incomplete. Removing ${ROOTDIR}"
  cd ..
  if echo "${ROOTDIR}" | grep -E '[ "]' >/dev/null; then
    echo "ERROR: Feeding my paranoia of having a \"rm -r\" in a script:"
    echo "       There should not be any spaces in the ROOT version..."
    exit 1
  fi
  rm -r "${ROOTDIR}"
fi



echo "Unpacking..."
mkdir ${ROOTDIR}
cd ${ROOTDIR}
tar xvfz ../${TARBALL} > /dev/null
if [ "$?" != "0" ]; then
  echo "ERROR: Something went wrong unpacking the ROOT tarball!"
  exit 1
fi
mv ${ROOTTOPDIR}/* .
mv ${ROOTTOPDIR}/.??* .
rmdir ${ROOTTOPDIR}



echo "Configuring..."
export ROOTSYS=${ROOTDIR}
export LD_LIBRARY_PATH=""
sh configure ${CONFIGUREOPTIONS} ${DEBUGOPTIONS}
if [ "$?" != "0" ]; then
  echo "ERROR: Something went wrong configuring ROOT!"
  exit 1
fi



CORES=1;
if ( `test -f /usr/sbin/sysctl` ); then
  CORES=`sysctl -n hw.logicalcpu_max`
elif ( `test -f /proc/cpuinfo` ); then 
  CORES=`grep processor /proc/cpuinfo | wc -l`
fi
if [ "$?" != "0" ]; then
  CORES=1
fi
if [ "${CORES}" -gt "${MAXTHREADS}" ]; then
  CORES=${MAXTHREADS}
fi
echo "Using this number of cores for compilation: ${CORES}"



echo "Compiling..."
make -j${CORES}
if [ "$?" != "0" ]; then
  echo "ERROR: Something went wrong while compiling ROOT!"
  exit 1
fi



echo "Store our success story..."
rm -f COMPILE_SUCCESSFUL
echo "${CONFIGUREOPTIONS}" >> COMPILE_SUCCESSFUL
echo "${COMPILEROPTIONS}" >> COMPILE_SUCCESSFUL



echo "Setting permissions..."
cd ..
chown -R ${USER}:${GROUP} ${ROOTDIR}
chmod -R go+rX ${ROOTDIR}


if [ "${ENVFILE}" != "" ]; then
  echo "Storing the ROOT directory in the MEGAlib source script..."
  echo "ROOTDIR=`pwd`/${ROOTDIR}" >> ${ENVFILE}
fi


echo "Done!"
exit 0
