#!/bin/sh
#
# Copyright 2024- IBM Inc. All rights reserved
# SPDX-License-Identifier: MIT
#

# Script to convert VMs from using RWO Block based volumes to RWX Block based volumes
# For debugging, uncomment the following line
#set -x

# --- ADJUST THESE VARIABLES ACCORDING TO YOUR NEEDS
# Original VM name, this VM needs to exist
VM="rhel9-rwo"
# The namespace needs to exist
NAMESPACE="rwo-to-rwx"
# ---

# Check for prereqs: oc CLI, jq installed
which oc
if [ $? -eq 1 ]; then
    echo "Please install the oc CLI before running this script"
    exit 1
fi
which jq
if [ $? -eq 1 ]; then
    echo "Please install jq before running this script"
    exit 1
fi

wait_for_pvc_bound() {
    PHASE=$(oc get pvc $1 -o 'jsonpath={.status.phase}')
    while [ "$PHASE" != "Bound" ]; do
	sleep 1
	PHASE=$(oc get pvc $1 -o 'jsonpath={.status.phase}')
    done
}

# Change to namespace
oc project $NAMESPACE
if [ $? -eq 1 ]; then
    echo "Namespace $NAMESPACE does not exist."
    exit 1
fi

# Get all relevant data volumes for the VM
DATAVOLUMES=$(oc get vm $VM -o jsonpath='{.spec.template.spec.volumes[*].dataVolume}' | jq -r .name)

# Build jq filter - cleanup
cat <<EOF>jq_filter_vm
del(.status, .metadata.annotations, .metadata.creationTimestamp,
.metadata.finalizers, .metadata.generation, .metadata.uid,
.metadata.resourceVersion, .spec.dataVolumeTemplates[].metadata.creationTimestamp,
.spec.dataVolumeTemplates[].spec.sourceRef, .spec.template.metadata.labels)
EOF

# jq filter, second step: patch all Datavolume entries to RWX
i=0
for DV in $DATAVOLUMES; do
cat <<EOF>>jq_filter_vm
| .spec.dataVolumeTemplates[$i].spec.storage.accessModes[0] = "ReadWriteMany"
EOF
    ((i++))
done

# Get VM definition, clean up entries and patch new access mode
oc get vm $VM -o json | jq -f jq_filter_vm > vm_${VM}_new.json

for DV in $DATAVOLUMES; do
    # Build jq filter - cleanup
    cat <<EOF>jq_filter_dv_$DV
del(.status, .metadata.annotations, .metadata.creationTimestamp, .metadata.generation,
.metadata.labels, .metadata.ownerReferences, .metadata.resourceVersion, .metadata.uid)
EOF

    # jq filter, second step: patch all Datavolume entries to RWX
    cat <<EOF>>jq_filter_dv_$DV
| .spec.storage.accessModes[0] = "ReadWriteMany"
EOF
done

# Get DataVolume definition, clean up entries and patch new name and access mode
for DV in $DATAVOLUMES; do
    oc get dv $DV -o json | jq -f jq_filter_dv_$DV > dv_${DV}_new.json
done

PVS=()
PVCS=()
RECLAIMPOLICIES=()
for DV in $DATAVOLUMES; do
    PVC=$(oc get dv $DV -o jsonpath='{.status.claimName}')
    PVCS+=($PVC)
    # Retrieve PV for PVC
    PV=$(oc get pvc $PVC -o jsonpath='{.spec.volumeName}')
    PVS+=($PV)
    # Get original reclaim policy
    RECLAIMPOLICIES+=($(oc get pv $PV -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'))

    # Ensure that the PV will be retained after PVC deletion
    oc patch pv $PV --type=merge -p '{"spec": {"persistentVolumeReclaimPolicy": "Retain"}}'
done

# Deleting VM will also delete DataVolume and PVC
oc delete vm $VM

for PV in ${PVS[@]}; do
    # (optional verification) Check that PV status is "Released"
    #oc get pv $PV -o jsonpath='{.status.phase}{"\n"}'

    # Cleanup PV uid reference that prevents PV reclamation
    oc patch pv $PV --type='json' -p='[{"op": "remove", "path": "/spec/claimRef/uid"}]'

    # (optional verification) Check that status is "Available"
    #oc get pv $PV -o jsonpath='{.status.phase}{"\n"}'

    # Change PV access mode to RWX
    oc patch pv $PV --type='json' -p='[{"op": "replace", "path": "/spec/accessModes/0", "value": "ReadWriteMany"}]'
done

# Re-create the DataVolumes, this will re-create the PVC as well
for DV in $DATAVOLUMES; do
    oc apply -f dv_${DV}_new.json
done

for PVC in ${PVCS[@]}; do
    wait_for_pvc_bound $PVC
done

i=0
# Re-apply the original reclaim policy if required
for PV in ${PVS[@]}; do
    if [ ${RECLAIMPOLICIES[i]} != "Retain" ]; then
        oc patch pv $PV --type=merge -p '{"spec": {"persistentVolumeReclaimPolicy": "'${RECLAIMPOLICIES[i]}'"}}'
    fi
    ((i++))
done

# Re-create Virtual machine
oc apply -f vm_${VM}_new.json
