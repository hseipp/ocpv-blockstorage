#!/bin/sh
for I in $(oc get pv -o name); do
    VOLUMEMODE=$(oc get $I -o jsonpath='{.spec.volumeMode}')
    CLAIMREF=$(oc get $I -o jsonpath='{.spec.claimRef.name}')
    if [ "$VOLUMEMODE" = "Block" ]; then
        echo PV $I is VolumeMode $VOLUMEMODE with PVC $CLAIMREF
    fi
done
