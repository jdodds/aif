basedir=$(dirname "`dirname $0`")
source $basedir/src/core/libs/lib-ui.sh
ANSWER="/tmp/aif-test-dialog-answer"
for ui in dia cli
do
	for type in required optional
	do
		for default in no tag-c
		do
			var_UI_TYPE=$ui
			ask_option $default 'menu title ($2)' 'extra explanation ($3)'" settings: type: $type, default:$default" $type tagA itemA "tag B" 'item B' tag-c item\ C
			notify "RETURN CODE: $?\nANSWER: $ANSWER_OPTION"
		done
	done
done
