# OpenShift Virtualization Block Storage Tools

## Scope

The purpose of this project is to provide tools to improve usage of IBM Block Storage for OpenShift Virtualization use cases.

## Usage

The [script](src/vm_rwo_to_rwx.sh) provided with this repository changes the
access mode of Block Storage volumes used by OpenShift Virtualization virtual
machines from RearWriteOnce (RWO) to ReadWriteMany (RWX).

Before using that script, double-check that your Block Storage CSI driver
supports RWX Block access mode. [IBM Block Storage CSI 1.12.0](https://www.ibm.com/docs/en/stg-block-csi-driver/1.12.0)
and later versions provide support for RWX Block access mode.

To convert the VM to use RWX Block access mode, all CRs for the given VM that are

- VirtualMachine
- DataVolume
- PersistentVolumeClaim(s)
- PersistentVolume(s)

will be modified to ReadWriteMany access mode.

Before using the script, please check the contents and modify the `NAMESPACE`
variable according to your needs.

The source PVC used to create the VM might be no longer present - check with:

```shell
oc get pvc -n openshift-virtualization-os-images $(oc get dv $VM -o jsonpath='{.spec.source.pvc.name}')
```

(Replace `$VM` with the name of your VM.)
In that case, the script with pick the oldest available source PVC that matches
the template pattern of the original source PVC.

> [!WARNING]
> The script will save the above mentioned CRs, but it is still highly
> recommended to keep a backup of the Persistent Volumes as there is a
> possibility that PVs get deleted in storage attachment scenarios that were
> not discovered / tested while developing this script.

if all the prerequisites are met, you can convert your VM to RWX access mode by
specifying the VM name as parameter to the script:

```shell
./vw_rwo_to_rwx.sh -h my_vm
```

## Disclaimer

Please note: This project is released for use "AS IS" without any warranties of
any kind, including, but not limited to installation, use, or performance of
the resources in this repository. We are not responsible for any damage, data
loss or charges incurred with their use. This project is outside the scope of
the IBM PMR process. If you have any issues, questions or suggestions you can
create a new [issue here](issues). Issues will be addressed as team
availability permits.

## Notes

If you have any questions or issues you can create a new [issue here](issues).

Pull requests are very welcome! Make sure your patches are well tested.
Ideally create a topic branch for every separate change you make. For
example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

See [Contributing](CONTRIBUTING.md) for additional details on contributions.

## License

All source files must include a Copyright and License header. The SPDX license
header is preferred because it can be easily scanned.

If you would like to see the detailed LICENSE click [here](LICENSE).

```text
#
# Copyright IBM Corp. 2024-
# SPDX-License-Identifier: MIT
#
```
