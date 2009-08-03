#!/bin/sh
which markdown &>/dev/null || echo "Need markdown utility!" >&2

for i in doc/official_installation_guide_??
do
	echo $i
	cat  $i | markdown > $i.html
done
