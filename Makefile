compile:
	if [ -e controller-config.json.tmpl ]; then rm controller-config.json.tmpl; fi
	if [ -e container-linux-config.json ]; then rm container-linux-config.json; fi
	~/go/src/github.com/coreos/container-linux-config-transpiler/bin/ct --in-file controller-config.yaml > controller-config.json.tmpl
