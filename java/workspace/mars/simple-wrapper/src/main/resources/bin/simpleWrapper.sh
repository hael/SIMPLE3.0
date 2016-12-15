#!/bin/bash -l

# Wrapper for running simple job on local UNICORE client-server installation
# --------------------------------------------------------------------------
WORKING_DIR=`pwd`
PREFIX=/opt/Application_folder/lib/; export PREFIX

C1=$PREFIX/simpleApplicationWrapper-0.1-SNAPSHOT.jar
C2=$PREFIX/mmm-openmolgrid-common-1.0-SNAPSHOT.jar
C3=$PREFIX/log4j-1.2.14.jar

export CLASSPATH=$C1:$C2:$C3

java -cp $CLASSPATH edu.kit.mmm.wrapper.simple.simpleLauncher \
--workingDirectory=`pwd`
