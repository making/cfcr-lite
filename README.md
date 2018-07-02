# Deploy CFCR on BOSH Lite

## Initialize a project

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

## Install BOSH Lite on VirtualBox

```yaml
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
cat <<'EOF' > deploy-bosh.sh
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
    -v internal_ip=192.168.150.6 \
    -v internal_gw=192.168.150.1 \
    -v internal_cidr=192.168.150.0/24 \
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
export BOSH_CA_CERT="$(bosh int ./bosh-lite-creds.yml --path /director_ssl/ca)"
export BOSH_ENVIRONMENT=192.168.150.6
EOF
chmod +x bosh-lite-env.sh
```

```
source bosh-lite-env.sh
```

```
STEMCELL_VERSION=$(bosh int kubo-deployment/manifests/cfcr.yml --path /stemcells/0/version)
bosh upload-stemcell https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent?v=${STEMCELL_VERSION}
```

```
curl -sL https://github.com/cloudfoundry/cf-deployment/raw/master/iaas-support/bosh-lite/cloud-config.yml | bosh -n update-cloud-config -
```

## Deploy Kubernetes

```yaml
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

```yaml
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

```yaml
cat <<EOF > ops-files/kubernetes-single-worker.yml
- type: replace
  path: /instance_groups/name=worker/instances
  value: 1
EOF
```

```
mkdir -p specs
```

```
curl -Ls -o specs/storage-provisioner.yml https://github.com/kubernetes/minikube/raw/479ca10c75f6d73a71543627fd1fbe627600f5ec/deploy/addons/storage-provisioner/storage-provisioner.yaml
curl -Ls -o specs/storageclass.yml https://github.com/kubernetes/minikube/raw/479ca10c75f6d73a71543627fd1fbe627600f5ec/deploy/addons/storageclass/storageclass.yaml
```

```
cat <<'EOF' > deploy-kubernetes.sh
#!/bin/bash
bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o kubo-deployment/manifests/ops-files/addons-spec.yml \
    -o ops-files/kubernetes-kubo-0.16.0.yml \
    -o ops-files/kubernetes-static-ips.yml \
    -o ops-files/kubernetes-single-worker.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
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
sudo route add -net 10.244.0.0/16 192.168.150.6
# in case of Linux
sudo route add -net 10.244.0.0/16 gw 192.168.150.6
```

## Access Kubernetes

```
cat <<EOF > credhub-login.sh
#!/bin/bash
credhub login \
        -s 192.168.150.6:8844 \
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
admin_password=$(credhub get -n /bosh-lite/cfcr/kubo-admin-password | bosh int - --path=/value)
master_host=$(bosh vms -d cfcr | grep master | awk 'NR==1 {print $4}')

tmp_ca_file="$(mktemp)"
credhub get -n /bosh-lite/cfcr/tls-kubernetes | bosh int - --path=/value/ca > "${tmp_ca_file}"

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

## Access Dashboard


```
kubectl proxy
```

[http://localhost:8001/ui](http://localhost:8001/ui)

![image](https://user-images.githubusercontent.com/106908/39967884-8aeb29d0-56fe-11e8-86df-982150c5f58f.png)

Get a token

```
kubectl get secrets "$(kubectl get secrets -n kube-system | grep clusterrole-aggregation-controller | awk '{print $1}')" -n kube-system -o json | jq -r .data.token | base64 -D
```

![image](https://user-images.githubusercontent.com/106908/39967872-48cbffd4-56fe-11e8-9460-e0a38acbe665.png)

## Commit project

```
cat <<EOF > .gitignore
*-state.json
*-creds.yml
EOF
git add -A
git commit -m "deploy CFCR v0.16.0"
```

## Enable UAA

```yaml
cat <<EOF > ops-files/kubernetes-uaa.yml
- type: replace
  path: /releases/-
  value:
    name: uaa
    version: "57.1"
    url: https://bosh.io/d/github.com/cloudfoundry/uaa-release?v=57.1
    sha1: b96e5965e890d9cdd6ad96890cdaad719c368c31
- type: replace
  path: /releases/-
  value:
    name: postgres
    version: 28
    url: https://bosh.io/d/github.com/cloudfoundry/postgres-release?v=28
    sha1: c1fcec62cb9d2e95e3b191e3c91d238e2b9d23fa

# Add UAA job
- type: replace
  path: /instance_groups/-
  value:
    name: postgres
    instances: 1
    azs: [z1]
    networks:
    - name: default
    stemcell: trusty
    vm_type: small
    persistent_disk: 1024
    jobs:
    - release: postgres
      name: postgres
      properties:
        databases:
          tls:
            ca: ((postgres_tls.ca))
            certificate: ((postgres_tls.certificate))
            private_key: ((postgres_tls.private_key))
          databases:
          - name: uaa
            tag: uaa
          db_scheme: postgres
          port: 5432
          roles:
          - name: uaa
            password: ((uaa_database_password))
            tag: admin
- type: replace
  path: /instance_groups/-
  value:
    name: uaa
    instances: 1
    networks:
    - name: default
      static_ips: [((kubernetes_uaa_host))]
    azs: [z1,z2,z3]
    stemcell: trusty
    vm_type: small
    jobs:
    - name: uaa
      release: uaa
      properties:
        encryption:
          active_key_label: default_key
          encryption_keys:
            - label: default_key
              passphrase: ((uaa_default_encryption_passphrase))
        login:
          saml:
            activeKeyId: key-1
            keys:
              key-1:
                key: "((uaa_login_saml.private_key))"
                certificate: "((uaa_login_saml.certificate))"
                passphrase: ""
        uaa:
          url: "https://((kubernetes_uaa_host)):8443"
          catalina_opts: -Djava.security.egd=file:/dev/./urandom
          sslPrivateKey: ((uaa_ssl.private_key))
          sslCertificate: ((uaa_ssl.certificate))
          jwt:
            revocable: true
            policy:
              active_key_id: key-1
              keys:
                key-1:
                  signingKey: "((uaa_jwt_signing_key.private_key))"
          logging_level: INFO
          scim:
            users:
            - name: admin
              password: ((uaa_admin_password))
              groups:
              - openid
              - scim.read
              - scim.write
          admin:
            client_secret: "((uaa_admin_client_secret))"
          login:
            client_secret: "((uaa_login_client_secret))"
          clients:
            kubernetes:
              override: true
              authorized-grant-types: password,refresh_token
              scope: openid
              authorities: uaa.none
              access-token-validity: 86400 # 1 day
              refresh-token-validity: 604800 # 7 days
              secret: ""
          zones:
            internal:
              hostnames: []
        login:
          saml:
            serviceProviderKey: ((uaa_service_provider_ssl.private_key))
            serviceProviderKeyPassword: ""
            serviceProviderCertificate: ((uaa_service_provider_ssl.certificate))
        uaadb:
          port: 5432
          db_scheme: postgresql
          tls_enabled: true
          skip_ssl_validation: true
          databases:
          - tag: uaa
            name: uaa
          roles:
          - name: uaa
            password: ((uaa_database_password))
            tag: admin

- type: replace
  path: /instance_groups/name=master/jobs/name=kube-apiserver/properties/oidc?
  value:
    issuer-url: "https://((kubernetes_uaa_host)):8443/oauth/token"
    client-id: kubernetes
    username-claim: email
    ca: ((uaa_ssl.ca))

- type: replace
  path: /variables/-
  value:
    name: uaa_default_encryption_passphrase
    type: password

- type: replace
  path: /variables/-
  value:
    name: uaa_jwt_signing_key
    type: rsa

- type: replace
  path: /variables/-
  value:
    name: uaa_admin_password
    type: password

- type: replace
  path: /variables/-
  value:
    name: uaa_admin_client_secret
    type: password

- type: replace
  path: /variables/-
  value:
    name: uaa_login_client_secret
    type: password

- type: replace
  path: /variables/-
  value:
    name: uaa_ssl
    type: certificate
    options:
      ca: kubo_ca
      common_name: uaa.cfcr.internal
      alternative_names:
      - ((kubernetes_uaa_host))

- type: replace
  path: /variables/-
  value:
    name: uaa_login_saml
    type: certificate
    options:
      ca: kubo_ca
      common_name: uaa_login_saml

- type: replace
  path: /variables/-
  value:
    name: uaa_service_provider_ssl
    type: certificate
    options:
      ca: kubo_ca
      common_name: uaa.cfcr.internal
      alternative_names:
      - ((kubernetes_uaa_host))

- type: replace
  path: /variables/-
  value:
    name: uaa_database_password
    type: password

- type: replace
  path: /variables/-
  value:
    name: postgres_tls
    type: certificate
    options:
      ca: kubo_ca
      common_name: postgres.cfcr.internal
      alternative_names:
      - "*.postgres.default.cfcr.bosh"
EOF
```

```yaml
cat <<EOF > specs/uaa-admin.yml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: uaa-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: User
  name: admin
EOF
```

```
cat <<EOF > deploy-kubernetes.sh
#!/bin/bash
bosh deploy -d cfcr kubo-deployment/manifests/cfcr.yml \
    -o kubo-deployment/manifests/ops-files/addons-spec.yml \
    -o ops-files/kubernetes-uaa.yml \
    -o ops-files/kubernetes-kubo-0.16.0.yml \
    -o ops-files/kubernetes-static-ips.yml \
    -o ops-files/kubernetes-single-worker.yml \
    --var-file addons-spec=<(for f in `ls specs/*.yml`;do cat $f;echo;echo "---";done) \
    -v kubernetes_master_host=10.244.1.92 \
    -v kubernetes_worker_hosts='["10.244.1.93"]' \
    -v kubernetes_uaa_host=10.244.1.94 \
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

## Access with UAA

```
./credhub-login.sh
```

```
master_host=$(bosh vms -d cfcr | grep master | awk 'NR==1 {print $4}')

tmp_ca_file="$(mktemp)"
credhub get -n /bosh-lite/cfcr/tls-kubernetes | bosh int - --path=/value/ca > "${tmp_ca_file}"

cluster_name="cfcr"
user_name="uaa-admin"
context_name="cfcr-uaa"

kubectl config set-cluster "${cluster_name}" \
  --server="https://${master_host}:8443" \
  --certificate-authority="${tmp_ca_file}" \
  --embed-certs=true

uaa_url=https://$(bosh -d cfcr vms | grep uaa | awk '{print $4}'):8443

access_token=`curl -s ${uaa_url}/oauth/token \
  --cacert <(credhub get -n /bosh-lite/cfcr/uaa_ssl | bosh int - --path=/value/ca) \
  -d grant_type=password \
  -d response_type=id_token \
  -d scope=openid \
  -d client_id=kubernetes \
  -d client_secret= \
  -d username=admin \
  -d password=$(credhub get -n /bosh-lite/cfcr/uaa_admin_password | bosh int - --path /value)`

kubectl config set-credentials "${user_name}" \
  --auth-provider=oidc \
  --auth-provider-arg=idp-issuer-url=${uaa_url}/oauth/token \
  --auth-provider-arg=client-id=kubernetes \
  --auth-provider-arg=client-secret= \
  --auth-provider-arg=id-token=$(echo $access_token | bosh int - --path /id_token) \
  --auth-provider-arg=refresh-token=$(echo $access_token | bosh int - --path /refresh_token) \
  --auth-provider-arg=idp-certificate-authority-data="$(credhub get -n /bosh-lite/cfcr/uaa_ssl | bosh int - --path=/value/ca | base64)"
  
kubectl config set-context "${context_name}" --cluster="${cluster_name}" --user="${user_name}"

kubectl config use-context "${context_name}"
```

## Commit project

```
git add -A
git commit -m "add UAA"
```
