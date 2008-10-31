#!/bin/sh
SRC_DIR=`dirname $0` # the src directory in the git clone 
cp -ax $SRC_DIR/fifa.sh      /arch/fifa.sh
cp -ax $SRC_DIR/lib-archboot /arch/lib-archboot
mkdir /home/arch/fifa/
cp -ax $SRC_DIR/profiles/*   /home/arch/fifa/
