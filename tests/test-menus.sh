basedir=$(dirname "`dirname $0`")
source $basedir/src/core/libs/lib-ui.sh
ANSWER="/tmp/.dialog-answer"


var_UI_TYPE=dia
ask_option no 'menu title is this yes yes' 'extra explanation is here mkay OPTIONAL' optional tagA itemA "tag B" 'item B' tag-c item\ C
echo "return code was $?"

ask_option no 'menu title is this yes yes' 'extra explanation is here mkay REQUIRED' required tagA itemA "tag B" 'item B' tag-c item\ C
echo "return code was $?"

var_UI_TYPE=cli
ask_option tag-c 'menu title is this yes yes' 'extra explanation is here mkay OPTIONAL' optional tagA itemA "tag B" 'item B' tag-c item\ C
echo "return code was $?"

ask_option tag-c 'menu title is this yes yes' 'extra explanation is here mkay REQUIRED' required tagA itemA "tag B" 'item B' tag-c item\ C
echo "return code was $?"
