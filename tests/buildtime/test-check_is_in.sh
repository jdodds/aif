basedir=$(dirname "`dirname $0`")
source $basedir/src/core/libs/lib-ui.sh #dependency needed
source $basedir/src/core/libs/lib-misc.sh

vars=(A B C D E F)
check_is_in C "${vars[@]}" && echo 'ok C was in there' || echo 'wtf'
check_is_in AOEUAU "${vars[@]}" && echo wtf || echo 'ok it was not in there'
