#!/bin/bash
UAA_URL=https://$(bosh -d cfcr vms | grep uaa | awk '{print $4}'):8443

uaac target ${UAA_URL} --ca-cert <(credhub get -n /bosh-lite/cfcr/uaa_ssl -j | jq -r .value.ca)
uaac token client get admin -s $(credhub get -n /bosh-lite/cfcr/uaa_admin_client_secret -j | jq -r .value)