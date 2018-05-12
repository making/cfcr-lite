```
git init
git submodule add git@github.com:cloudfoundry/bosh-deployment.git
git submodule add git@github.com:cloudfoundry-incubator/kubo-deployment.git
cd kubo-deployment
git checkout v0.16.0
cd ..
git add -A
git commit -m "import CFCR v0.16.0"
```

```
mkdir -p ops-files
cat <<EOF > ops-files/director-size-lite.yml
- type: replace
  path: /resource_pools/name=vms/cloud_properties/cpus
  value: 2
- type: replace
  path: /resource_pools/name=vms/cloud_properties/memory
  value:  4_096
EOF
```

```
cat <<EOF > deploy-bosh.sh
#!/bin/bash
bosh create-env bosh-deployment/bosh.yml \
    -o bosh-deployment/virtualbox/cpi.yml \
    -o bosh-deployment/virtualbox/outbound-network.yml \
    -o bosh-deployment/bosh-lite.yml \
    -o bosh-deployment/bosh-lite-runc.yml \
    -o bosh-deployment/uaa.yml \
    -o bosh-deployment/credhub.yml \
    -o bosh-deployment/jumpbox-user.yml \
    -o ops-files/director-size-lite.yml \
    --vars-store bosh-lite-creds.yml \
    -v director_name=bosh-lite \
    -v internal_ip=192.168.50.6 \
    -v internal_gw=192.168.50.1 \
    -v internal_cidr=192.168.50.0/24 \
    -v outbound_network_name=NatNetwork \
    --state bosh-lite-state.json
EOF
chmod +x deploy-bosh.sh
```

```
./deploy-bosh.sh
```

```
cat <<EOF > bosh-lite-env.sh
export BOSH_CLIENT=admin  
export BOSH_CLIENT_SECRET=$(bosh int ./bosh-lite-creds.yml --path /admin_password)
export BOSH_CA_CERT=$(bosh int ./bosh-lite-creds.yml --path /director_ssl/ca)
export BOSH_ENVIRONMENT=192.168.50.6
EOF
chmod +x bosh-lite-env.sh
```

```
source bosh-lite-env.sh
```

```
bosh upload-stemcell https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent?v=3541.10
```

```
curl -sL https://github.com/cloudfoundry/cf-deployment/raw/master/iaas-support/bosh-lite/cloud-config.yml | bosh -n update-cloud-config -
```


```
cat <<EOF > ops-files/kubernetes-kubo-0.16.0.yml
- type: replace
  path: /releases/name=kubo?
  value:
    name: kubo
    version: 0.16.0
    url: https://bosh.io/d/github.com/cloudfoundry-incubator/kubo-release?v=0.16.0
    sha1: 8a513e48cccdea224c17a92ce73edbda04acee91
EOF
```

```
cat <<EOF > ops-files/kubernetes-static-ips.yml
- type: replace
  path: /instance_groups/name=master/networks/0/static_ips?
  value: [((kubernetes_master_host))]
- type: replace
  path: /instance_groups/name=worker/networks/0/static_ips?
  value: ((kubernetes_worker_hosts))
- type: replace
  path: /variables/name=tls-kubernetes/options/alternative_names/-
  value: ((kubernetes_master_host))
EOF
```

```
cat <<EOF > ops-files/kubernetes-single-worker.yml
- type: replace
  path: /instance_groups/name=worker/instances
  value: 1
EOF
```

```
cat <<EOF > deploy-kubernetes.sh
#!/bin/bash
bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o ops-files/kubernetes-kubo-0.16.0.yml \
    -o ops-files/kubernetes-static-ips.yml \
    -o ops-files/kubernetes-single-worker.yml \
    -v kubernetes_master_host=10.244.1.92 \
    -v kubernetes_worker_hosts='["10.244.1.93"]' \
    --no-redact
EOF
chmod +x deploy-kubernetes.sh
```

```
./deploy-kubernetes.sh
```

```
bosh -d cfcr run-errand apply-addons
```

```
# in case of Mac
sudo route add -net 10.244.0.0/16 192.168.50.6
# in case of Linux
sudo route add -net 10.244.0.0/16 gw 192.168.50.6
```

```
cat <<EOF > credhub-login.sh
#!/bin/bash
credhub login \
        -s 192.168.50.6:8844 \
        --client-name=credhub-admin \
        --client-secret=$(bosh int ./bosh-lite-creds.yml --path /credhub_admin_client_secret) \
        --ca-cert <(bosh int ./bosh-lite-creds.yml --path /uaa_ssl/ca) \
        --ca-cert <(bosh int ./bosh-lite-creds.yml --path /credhub_ca/ca)
EOF
chmod +x credhub-login.sh
```

```
./credhub-login.sh
```


```
admin_password=$(bosh int <(credhub get -n "/bosh-lite/cfcr/kubo-admin-password" --output-json) --path=/value)
master_host=$(bosh vms -d cfcr | grep master | awk 'NR==1 {print $4}')

tmp_ca_file="$(mktemp)"
bosh int <(credhub get -n "/bosh-lite/cfcr/tls-kubernetes" --output-json) --path=/value/ca > "${tmp_ca_file}"

cluster_name="cfcr"
user_name="admin"
context_name="cfcr"
kubectl config set-cluster "${cluster_name}" \
  --server="https://${master_host}:8443" \
  --certificate-authority="${tmp_ca_file}" \
  --embed-certs=true
kubectl config set-credentials "${user_name}" --token="${admin_password}"
kubectl config set-context "${context_name}" --cluster="${cluster_name}" --user="${user_name}"
kubectl config use-context "${context_name}"
```


```
kubectl cluster-info
Kubernetes master is running at https://10.244.1.92:8443
Heapster is running at https://10.244.1.92:8443/api/v1/namespaces/kube-system/services/heapster/proxy
KubeDNS is running at https://10.244.1.92:8443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
monitoring-influxdb is running at https://10.244.1.92:8443/api/v1/namespaces/kube-system/services/monitoring-influxdb/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

```
cat <<EOF > .gitignore
*-state.json
*-creds.yml
EOF
git add -A
git commit -m "deploy CFCR v0.16.0"
```
