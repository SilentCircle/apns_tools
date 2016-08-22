#!/bin/bash

set -e

CA_SERIAL=2
CA_CONFIG=FakeAppleCA.cfg
CA_PRIVATE_KEY=FakeAppleCA.key.unencrypted.pem
CA_ROOT_CERT=FakeAppleCA.cert.pem

WWDR_CA_CONFIG=FakeAppleWWDRCA.cfg
WWDR_CA_PRIVATE_KEY=FakeAppleWWDRCA.key.unencrypted.pem
WWDR_CA_ROOT_CERT=FakeAppleWWDRCA.cert.pem
WWDR_CA_ROOT_CSR=FakeAppleWWDRCA.csr

make_ca_dir_struct() {
    local dir=$1; shift

    mkdir -p ${dir}/private ${dir}/certs ${dir}/crl ${dir}/newcerts
    chmod 0700 ${dir}
    [[ -f ${dir}/serial ]] || echo '01' > ${dir}/serial
    [[ -f ${dir}/index.txt ]] || touch ${dir}/index.txt
    echo 'unique_subject = no' > ${dir}/index.txt.attr
}

make_ca_dir_struct CA
pushd CA

ln -sf ../${CA_CONFIG} ./

# Generate CA private key (this could take a long time)
if [[ ! -f private/${CA_PRIVATE_KEY} ]]; then
    echo Generating CA private key
    openssl genrsa -out private/${CA_PRIVATE_KEY} 2048
    chmod 0400 private/${CA_PRIVATE_KEY}
fi

# Generate the CA root cert
echo Generating CA root cert
openssl req \
    -new \
    -x509 \
    -sha1 \
    -set_serial ${CA_SERIAL} \
    -extensions v3_ca \
    -key private/${CA_PRIVATE_KEY} \
    -out certs/${CA_ROOT_CERT} \
    -days 10585 \
    -config ${CA_CONFIG}

# For this all to work, the intermediate CA must be within the root CA

make_ca_dir_struct WWDRCA
[[ -f ./WWDRCA/crlnumber ]] || echo 1000 > ./WWDRCA/crlnumber

ln -sf ../../${WWDR_CA_CONFIG} WWDRCA/

# Generate WWDR CA private key
if [[ ! -f ./WWDRCA/private/${WWDR_CA_PRIVATE_KEY} ]]; then
    echo Generating WWDR CA private key
    openssl genrsa -out ./WWDRCA/private/${WWDR_CA_PRIVATE_KEY} 2048
    chmod 0400 ./WWDRCA/private/${WWDR_CA_PRIVATE_KEY}
fi

# Generate the CSR for the WWDR CA cert
echo Generating CSR for WWDR CA cert
openssl req \
    -verbose \
    -new \
    -sha1 \
    -key WWDRCA/private/${WWDR_CA_PRIVATE_KEY} \
    -out WWDRCA/${WWDR_CA_ROOT_CSR} \
    -days 3650 \
    -config ./WWDRCA/${WWDR_CA_CONFIG}

# Generate the WWDR CA cert
echo Generating WWDR CA cert
openssl ca \
    -verbose \
    -notext \
    -batch \
    -extensions v3_intermediate_ca \
    -config ${CA_CONFIG} \
    -in ./WWDRCA/${WWDR_CA_ROOT_CSR} \
    -out ./WWDRCA/certs/${WWDR_CA_ROOT_CERT}

popd

