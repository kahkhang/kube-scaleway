# Kubernetes on Scaleway

Work in progress.

`./kube-scalway.sh` to run the script.

What has been done:
* Installing a K8S master node running using CoreOS

Known Issues:
* Restarting the server results in the kernel being overriden
  (Temporary workaround using ipxe.expect: https://community.online.net/t/starting-coreos-on-vc1/2466/2)
* Wrap bootstrap.sh as a systemd service dependent on environment variables' initialization

Todos:
* Provision worker nodes
