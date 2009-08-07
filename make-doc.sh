#!/bin/sh
which markdown &>/dev/null || echo "Need markdown utility!" >&2
# do we need to sed links?
# do we need to add section 'avail languages'? like http://wiki.archlinux.org/index.php/Official_Arch_Linux_Install_Guide
# what about summary and related articles?
# obfuscate email? wiki supports mailto dingske
# TODO: strip article section, related articles from real content

echo "generating html..."
for i in doc/official_installation_guide_??
do
	echo $i
	# convert markdown to html, convert html links to wiki ones.
	cat $i | markdown | sed 's|<a href="\([^"]*\)"[^>]*>\([^<]*\)</a>|[\1 \2]|g' > $i.html
done

echo "adding special wiki thingies..."

i=doc/official_installation_guide_en
echo $i

summary=`sed -n '/<p><strong>Article summary<\/strong><\/p>/, /<p><strong>Related articles<\/strong><\/p>/ p' $i.html | grep -v 'strong'` #TODO strip html tags from summary? (maybe parse from markdown instead). this does not render on the wiki!

echo -e "[[Category:Getting and installing Arch (English)]]\n[[Category:HOWTOs (English)]]\n
{{Article summary start}}\n{{Article summary text| 1=$summary}}\n{{Article summary heading|Available Languages}}\n
{{i18n_entry|English|Official Arch Linux Install Guide}}\n
{{Article summary heading|Related articles}}\n
{{Article summary wiki|Beginners Guide}} (If you are new to Arch)\n
{{Article summary end}}" | cat - $i.html > $i.html.tmp && mv $i.html.tmp $i.html
