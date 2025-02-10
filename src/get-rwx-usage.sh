#!/bin/sh
for I in $(oc get pvc -o name); do
    ACCESSMODE=$(oc get $I -o jsonpath='{.spec.accessModes[0]}')
    if [ "$ACCESSMODE" = "ReadWriteMany" ]; then
        NAME=$(oc get $I -o jsonpath='{.metadata.name}')
	PV=$(oc get $I -o jsonpath='{.spec.volumeName}')
	VOLUMEMODE=$(oc get $I -o jsonpath='{.spec.volumeMode}')
        NUM=$(oc get volumeattachment | grep $PV | wc -l)
        echo $NAME with PV $PV has got $NUM attachments with VolumeMode $VOLUMEMODE
    fi
done
