#!/bin/sh
which markdown &>/dev/null || echo "Need markdown utility!" >&2
# do we need to sed links?
# do we need to add section 'avail languages'? like http://wiki.archlinux.org/index.php/Official_Arch_Linux_Install_Guide
# what about summary and related articles?
# obfuscate email?

for i in doc/official_installation_guide_??
do
	echo $i
	cat  $i | markdown > $i.html
done
