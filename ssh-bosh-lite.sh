#!/bin/sh

target=bosh-lite
ip=192.168.50.6

bosh int ${target}-creds.yml --path /jumpbox_ssh/private_key > ${target}.pem
chmod 600 ${target}.pem

ssh jumpbox@${ip} -i ${target}.pem

rm -f ${target}.pem
