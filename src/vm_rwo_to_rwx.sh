#!/bin/bash
#
# Copyright 2024- IBM Inc. All rights reserved
# SPDX-License-Identifier: MIT
#

# Script to convert VMs from using RWO Block based volumes to RWX Block based volumes
# For debugging, uncomment the following line
#set -x

# Function to display usage
usage() {
  echo "Usage: $0 -h vm_name"
  echo "  -h: VM name"
  echo "Examples: "
  echo "vm_rwo_to_rwx.sh -h nr-tinytool-test-01"
  echo "vm_rwo_to_rwx.sh -h nr-build-01"
  exit 1
}

# Parse input arguments
while getopts "h:" opt; do
  case $opt in
    h) VM=$OPTARG ;;
    *) usage ;;
  esac
done

# Check if all arguments are provided
if [ -z "$VM" ]; then
  usage
fi

# Redirect all output to tee and log to a file
exec > >(tee -a vm_rwo_to_rwx-${VM}.log) 2>&1

echo "ATTENTION: this is a script provided by IBM that will delete the VM, DataVolume and PVC CRs for $VM"
echo "WARNING: Proceeding may have consequences."
echo "Press any key to continue or Ctrl+C to exit."
read -n 1 -s -r
echo "Continuing..."

# The namespace needs to exist
NAMESPACE="rwo-to-rwx"

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

# Check the VM status
VM_STATUS=$(oc get vm "$VM" -n "$NAMESPACE" -o jsonpath='{.status.printableStatus}')

# Check if the VM is not in the "Stopped" state
if [[ "$VM_STATUS" != "Stopped" ]]; then
  echo "WARNING: VM '$VM' is in state '$VM_STATUS'."
  echo "The VM must be in a 'Stopped' state to proceed. Exiting."
  exit 1
fi

# Proceed with the rest of the script
echo "VM '$VM' is in 'Stopped' state. Proceeding..."

# Check if VM definition contains PVC instead of DataVolume
# Seems to be used by earlier OCP-V versions after performing VM restores from snapshots.
# Current OCP-V releases seem to always use DataVolumes.
PVCS=$(get vm $VM -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim}')
if [ -n "$PVCS" ]; then
    echo "Your VM definition contains PVC without a DataVolume. This is not supported with this script."
    echo "You need to manually patch the PV to ReclaimPolicy Retain, save the PVC definition, then"
    echo "follow the flow of this script. After deleting the VM, patch the PVC definition to RWX access"
    echo "mode and re-create the PVC, then follow the flow of rest of this script. Exiting"
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

# jq filter, third step: deletion of macAddress from all interfaces
cat <<EOF>>jq_filter_vm
| (.spec.template.spec.domain.devices.interfaces[] |= del(.macAddress))
EOF

# Get VM definition, clean up entries and patch new access mode
oc get vm $VM -o json > vm_${VM}_old.json
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

    # jq filter, third step: patch old OS image PVC name, if applicable
    OS_PVC_NAME=$(oc get dv "$DV" -o jsonpath='{.spec.source.pvc.name}')
    if [ -n "$OS_PVC_NAME" ]; then
        echo "OS image PVC name found: $OS_PVC_NAME"
        OS_FLAVOUR=$(echo $OS_PVC_NAME | awk -F'-' '{print $1}')
        NEW_OS_PVC_NAME=$(oc get pvc -n openshift-virtualization-os-images | grep $OS_FLAVOUR | sort -n -k8,8 | tail -n 1 | awk '{print $1}')
        echo "will patch with latest $OS_FLAVOUR PVC $NEW_OS_PVC_NAME to avoid errors"
        cat <<EOF>>jq_filter_dv_$DV
| .spec.source.pvc.name = "${NEW_OS_PVC_NAME}"
EOF
    else
        echo "No OS image PVC name found in DataVolume: $DV"
    fi
done

# Get DataVolume definition, clean up entries and patch new name and access mode
for DV in $DATAVOLUMES; do
    oc get dv $DV -o json > dv_${DV}_old.json
    oc get dv $DV -o json | jq -f jq_filter_dv_$DV > dv_${DV}_new.json
done

PVS=()
PVCS=()
RECLAIMPOLICIES=()
for DV in $DATAVOLUMES; do
    PVC=$(oc get dv $DV -o jsonpath='{.status.claimName}')
    oc get pvc $PVC -o json > pvc_${PVC}_old.json
    PVCS+=($PVC)
    # Retrieve PV for PVC
    PV=$(oc get pvc $PVC -o jsonpath='{.spec.volumeName}')
    oc get pv $PV -o json > pv_${PV}_old.json
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
