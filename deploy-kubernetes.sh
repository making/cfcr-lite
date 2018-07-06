#!/bin/bash

bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o kubo-deployment/manifests/ops-files/misc/single-master.yml \
    -o kubo-deployment/manifests/ops-files/addons-spec.yml \
    -o ops-files/kubernetes-uaa.yml \
    -o ops-files/kubernetes-kubo-0.18.0.yml \
    -o ops-files/kubernetes-static-ips.yml \
    -o ops-files/kubernetes-single-worker.yml \
    -o ops-files/kubernetes-add-alternative-name.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -l <(cat <<EOF
kubernetes_master_host: 10.244.1.92
kubernetes_worker_hosts:
- 10.244.1.93
kubernetes_uaa_host: 10.244.1.94
add_alternative_name: "*.sslip.io"
EOF) \
    --no-redact
