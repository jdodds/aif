#!/bin/sh


# run_mkinitcpio() taken from setup. adapted a bit. TODO: GET ALL THE UI CODE OUT OF HERE !!
# runs mkinitcpio on the target system, displays output
#
run_mkinitcpio()  
{
	target_special_fs on
    # all mkinitcpio output goes to /tmp/mkinitcpio.log, which we tail
    # into a dialog
    ( \
        touch /tmp/setup-mkinitcpio-running
        echo "mkinitcpio progress ..." > /tmp/mkinitcpio.log; \
        echo >> /tmp/mkinitcpio.log; \
        chroot "$TARGET_DIR" /sbin/mkinitcpio -p kernel26 >>/tmp/mkinitcpio.log 2>&1
        echo $? > /tmp/.mkinitcpio-retcode
        echo >> /tmp/mkinitcpio.log   
        rm -f /tmp/setup-mkinitcpio-running
    ) &

    sleep 2

    DIALOG --title "Rebuilding initcpio images ..." \
        --no-kill --tailboxbg "/tmp/mkinitcpio.log" 18 70 2>$ANSWER
    while [ -f /tmp/setup-mkinitcpio-running ]; do
        sleep 1
    done
    kill $(cat $ANSWER)

    target_special_fs off

    # alert the user to fatal errors
    if [ $(cat /tmp/.mkinitcpio-retcode) -ne 0 ]; then
        DIALOG --title "MKINITCPIO FAILED - SYSTEM MAY NOT BOOT" --exit-label \
        "Continue" --textbox "/tmp/mkinitcpio.log" 18 70
        return 1
    fi
}
