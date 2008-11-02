#!/bin/sh
SRC_DIR=`dirname $0` # the src directory in the git clone 
GIT_DIR=`dirname $SRC_DIR` # the git clone dir itself
mkdir -p /home/arch/fifa/docs
cp -ax $SRC_DIR/fifa.sh      /arch/fifa.sh

cp -ax $SRC_DIR/core         /home/arch/fifa/
cp -ax $SRC_DIR/user         /home/arch/fifa/
cp -ax $SRC_DIR/runtime      /home/arch/fifa/
cp -ax $GIT_DIR/dieter       /home/arch/fifa/user
cp -ax $GIT_DIR/HOWTO        /home/arch/fifa/docs/
cp -ax $GIT_DIR/README       /home/arch/fifa/docs/
