#!/bin/bash
credhub login         -s 192.168.50.6:8844         --client-name=credhub-admin         --client-secret=d2y2f374ee5ozpzf82h0         --ca-cert <(bosh int ./bosh-lite-creds.yml --path /uaa_ssl/ca)         --ca-cert <(bosh int ./bosh-lite-creds.yml --path /credhub_ca/ca)
