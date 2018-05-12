#!/bin/bash

bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o kubo-deployment/manifests/ops-files/add-oidc-endpoint.yml \
    -o kubo-deployment/manifests/ops-files/addons-spec.yml \
    -o ops-files/kubernetes-kubo-0.16.0.yml \
    -o ops-files/kubernetes-static-ips.yml \
    -o ops-files/kubernetes-single-worker.yml \
    -o ops-files/kubernetes-add-alternative-name.yml \
    -o ops-files/kubernetes-remove-unused-oidc-properties.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -l <(cat <<EOF
kubernetes_master_host: 10.244.1.92
kubernetes_worker_hosts:
- 10.244.1.93
add_alternative_name: "*.sslip.io"
oidc_issuer_url: https://35-200-70-121.sslip.io:30823/oauth/token
oidc_client_id: kubernetes
oidc_username_claim: email
EOF) \
    --no-redact