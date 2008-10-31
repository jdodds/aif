#!/bin/sh
SRC_DIR=`dirname $0` # the src directory in the git clone 
mkdir /home/arch/fifa/
cp -ax $SRC_DIR/fifa.sh      /arch/fifa.sh
cp -ax $SRC_DIR/profiles/*   /home/arch/fifa/
cp -ax $SRC_DIR/lib          /home/arch/fifa/lib
