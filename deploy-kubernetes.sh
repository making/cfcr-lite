#!/bin/bash
bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o ops-files/kubernetes-kubo-0.16.0.yml \
    -o ops-files/kubernetes-static-ips.yml \
    -o ops-files/kubernetes-single-worker.yml \
    -o ops-files/kubernetes-add-alternative-name.yml \
    -l <(cat <<EOF
kubernetes_master_host: 10.244.1.92
kubernetes_worker_hosts:
- 10.244.1.93
add_alternative_name: "*.sslip.io"
EOF) \
    --no-redact