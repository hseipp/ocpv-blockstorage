<!-- This should be the location of the title of the repository, normally the short name -->
# OpenShift Virtualization Block Storage Tools

<!-- Build Status, is a great thing to have at the top of your repository, it shows that you take your CI/CD as first class citizens -->
<!-- [![Build Status](https://travis-ci.org/jjasghar/ibm-cloud-cli.svg?branch=master)](https://travis-ci.org/jjasghar/ibm-cloud-cli) -->

## Scope

The purpose of this project is to provide tools to improve usage of IBM Block Storage for OpenShift Virtualization use cases.

<!-- A more detailed Usage or detailed explaination of the repository here -->
## Usage

The [script](src/vm_rwo_to_rwx.sh) provided with this repository changes the
access mode of Block Storage volumes used by OpenShift Virtualization virtual
machines from RearWriteOnce (RWO) to ReadWriteMany (RWX).

Before using that script, double-check that your Block Storage CSI driver
supports RWX Block access mode. [IBM Block Storage CSI 1.12.0](https://www.ibm.com/docs/en/stg-block-csi-driver/1.12.0) and later
versions provide support for RWX Block access mode.


To achieve that, all CRs for the given VM that are

- VirtualMachine
- DataVolume
- PersistentVolumeClaim(s)
- PersistentVolume(s)

will be modified to ReadWriteMany access mode.

Before using the script, please check the contents and modify the `NAMESPACE`
and `VM` variables according to your needs.
Please ensure that the source PVC used to create the VM is still present:

```shell
oc get pvc -n openshift-virtualization-os-images $(oc get dv $VM -o jsonpath='{.spec.source.pvc.name}')
```

(Replace `$VM` with the name of your VM.)

It is highly recommended to save the above mentioned CRs before using the
script as these get deleted by the script before they get re-created.

## Disclaimer

Please note: This project is released for use "AS IS" without any warranties of any kind, including, but not limited to installation, use, or performance of the resources in this repository. We are not responsible for any damage, data loss or charges incurred with their use. This project is outside the scope of the IBM PMR process. If you have any issues, questions or suggestions you can create a new [issue here](issues). Issues will be addressed as team availability permits.

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

All source files must include a Copyright and License header. The SPDX license header is
preferred because it can be easily scanned.

If you would like to see the detailed LICENSE click [here](LICENSE).

```text
#
# Copyright IBM Corp. 2024-
# SPDX-License-Identifier: MIT
#
```
