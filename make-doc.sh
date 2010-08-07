#!/bin/sh
which markdown &>/dev/null || echo "Need markdown utility!" >&2

echo "generating html..."
for i in doc/official_installation_guide_??
do
	echo $i
	# convert markdown to html, convert html links to wiki ones.
	cat $i | markdown | sed 's|<a href="\([^"]*\)"[^>]*>\([^<]*\)</a>|[\1 \2]|g' > $i.html
	# turn code markup into a syntax that mediawiki understands
	sed -i 's#<pre><code>#<pre>#g' $i.html
	sed -i 's#</code></pre>#</pre>#g' $i.html

done

echo "adding special wiki thingies..."

i=doc/official_installation_guide_en
echo $i


summary_begin='<p><strong>Article summary<\/strong><\/p>'
summary_end_plus_one='<p><strong>Related articles<\/strong><\/p>'
related_begin='<p><strong>Related articles<\/strong><\/p>'
related_end_plus_one='<h1>Introduction<\/h1>'

summary=`sed -n "/$summary_begin/, /$summary_end_plus_one/p;" $i.html | sed "/$summary_begin/d; /$summary_end_plus_one/d"`
related=`sed -n "/$related_begin/, /$related_end_plus_one/p;" $i.html | sed "/$related_begin/d; /$related_end_plus_one/d"`

# prepare $related for wikiing.
# note that like this we always keep the absulolute url's even if they are on the same subdomain eg: {{Article summary wiki|http://foo/bar bar}} (note).
# wiki renders absolute url a bit uglier.  always having absolute url's is not needed if the page can be looked up on the same wiki, but like this it was simplest to implement..
related=`echo "$related"| sed -e 's#<p>\[\(.*\)\] \(.*\)<\/p>#{{Article summary wiki|\1}} \2#'`

# preare $summary for wiiking: replace email address by nice mailto links
summary=`echo "$summary" | sed 's/\([^"|, ]*@[-A-Za-z0-9_.]*\)/[mailto:\1 \1]/'`


echo -e "[[Category:Getting and installing Arch (English)]]\n[[Category:HOWTOs (English)]]
[[Category:Accessibility (English)]]
[[Category:Website Resources]]
{{Article summary start}}\n{{Article summary text| 1=$summary}}\n{{Article summary heading|Available Languages}}\n
{{i18n_entry|English|Official Arch Linux Install Guide}}\n
{{Article summary heading|Related articles}}
$related
{{Article summary end}}" | cat - $i.html > $i.html.tmp && mv $i.html.tmp $i.html

# remove summary and related articles from actual content
sed "/$summary_end_plus_one/p; /$summary_begin/, /$summary_end_plus_one/d" $i.html > $i.html.tmp && mv $i.html.tmp $i.html
sed "/$related_end_plus_one/p; /$related_begin/, /$related_end_plus_one/d" $i.html > $i.html.tmp && mv $i.html.tmp $i.html
