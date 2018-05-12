#!/bin/bash
credhub login \
        -s 192.168.150.6:8844 \
        --client-name=credhub-admin \
        --client-secret=$(bosh int ./bosh-lite-creds.yml --path /credhub_admin_client_secret) \
        --ca-cert <(bosh int ./bosh-lite-creds.yml --path /uaa_ssl/ca) \
        --ca-cert <(bosh int ./bosh-lite-creds.yml --path /credhub_ca/ca)