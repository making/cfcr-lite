export BOSH_CLIENT=admin  
export BOSH_CLIENT_SECRET=$(bosh int ./bosh-lite-creds.yml --path /admin_password)
export BOSH_CA_CERT=$(bosh int ./bosh-lite-creds.yml --path /director_ssl/ca)
export BOSH_ENVIRONMENT=192.168.150.6

