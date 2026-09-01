# VPP IP Forwarder (from the CNF Testbed)

Upstream: https://github.com/cncf/cnf-testbed/tree/master/examples/network_functions/vpp-ip-forwarder

Description: Basic VPP container attached to host bridge through Multus

Description:
- Based on the fd.io VPP project
- Interface attached to host bridge

### Requirements

To run this example CNF, note the following requirements:
- [Multus](https://github.com/intel/multus-cni) must be installed and available in the cluster. This is available by default if using the [CNF Testbed](https://github.com/cncf/cnf-testbed)
- The example CNF should be installed on a bare-metal K8s cluster. The VPP core assignments have not yet been tested with a Kind cluster, and might cause the example deployment to fail.

# Prerequistes
### Install helm version 3

### Automated installation
Run cnti-testsuite setup 
```
export KUBECONFIG=$(pwd)/<YourKubeConf> ; ./cnti-testsuite setup
```

Setup and deploy  service chain
```
export KUBECONFIG=$(pwd)/admin.conf ; ./cnti-testsuite cnf_install cnf-path=example-cnfs/ip-forwarder/cnti-testsuite.yaml deploy_with_chart=false
```

### Testing
Run the test suite: `export KUBECONFIG=$(pwd)/admin.conf ; ./cnti-testsuite all`

### Automated uninstallation
```
export KUBECONFIG=$(pwd)/admin.conf ; ./cnti-testsuite cnf_uninstall
```


  
