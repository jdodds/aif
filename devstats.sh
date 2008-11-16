echo "This script doesn't do much, but this could be interesting..."
echo 'Amount of lines:'
echo -n "/arch/setup: "     && wget -q -O - 'http://projects.archlinux.org/?p=installer.git;a=blob_plain;f=setup;hb=HEAD'     | wc -l
echo -n "/arch/quickinst: " && wget -q -O - 'http://projects.archlinux.org/?p=installer.git;a=blob_plain;f=quickinst;hb=HEAD' | wc -l
echo "Aif:"
find `dirname $0`/src -type f | grep -v whatsthis | xargs wc -l