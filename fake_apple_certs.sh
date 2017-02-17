#!/bin/bash

### ==========================================================================
### Copyright 2016 Silent Circle
###
### Licensed under the Apache License, Version 2.0 (the "License");
### you may not use this file except in compliance with the License.
### You may obtain a copy of the License at
###
###     http://www.apache.org/licenses/LICENSE-2.0
###
### Unless required by applicable law or agreed to in writing, software
### distributed under the License is distributed on an "AS IS" BASIS,
### WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
### See the License for the specific language governing permissions and
### limitations under the License.
### ==========================================================================

set -e

# VERBOSE=-verbose

# Choose a date for the start date that is before "now",
# to avoid issues with certificates that won't work
# *right now*.

# Format is YYYYMMDDHHMMSSZ

yesterday() {
    local os=$(uname -s)

    case $os in
        Darwin)
            date -j -u -v-24H +'%Y%m%d%H%M%SZ'
            ;;
        Linux)
            date --utc --date=yesterday +'%Y%m%d%H%M%SZ'
            ;;
        *)
            echo "Unsupported OS: $os"
            exit 1
            ;;
    esac
}


START_DATE=$(yesterday)

echo "Start date will be set to $START_DATE"

CA_SERIAL=2
CA_CONFIG=FakeAppleCA.cfg
CA_PRIVATE_KEY=FakeAppleCA.key.unencrypted.pem
CA_ROOT_CERT=FakeAppleCA.cert.pem

WWDR_CA_CONFIG=FakeAppleWWDRCA.cfg
WWDR_CA_PRIVATE_KEY=FakeAppleWWDRCA.key.unencrypted.pem
WWDR_CA_ROOT_CERT=FakeAppleWWDRCA.cert.pem
WWDR_CA_CHAIN_CERT=FakeAppleWWDRCA.chain.cert.pem
WWDR_CA_ROOT_CSR=FakeAppleWWDRCA.csr

ISTCA2G1_CONFIG=FakeAppleISTCA2G1.cfg
ISTCA2G1_PRIVATE_KEY=FakeAppleISTCA2G1.key.unencrypted.pem
ISTCA2G1_ROOT_CERT=FakeAppleISTCA2G1.cert.pem
ISTCA2G1_CHAIN_CERT=FakeAppleISTCA2G1.chain.cert.pem
ISTCA2G1_ROOT_CSR=FakeAppleISTCA2G1.csr

DEV_PUSH_SERVER_PRIVATE_KEY=FakeAppleDevPushServer.key.unencrypted.pem
DEV_PUSH_SERVER_CERT=FakeAppleDevPushServer.cert.pem
DEV_PUSH_SERVER_CSR=FakeAppleDevPushServer.csr

PROD_PUSH_SERVER_PRIVATE_KEY=FakeAppleProdPushServer.key.unencrypted.pem
PROD_PUSH_SERVER_CERT=FakeAppleProdPushServer.cert.pem
PROD_PUSH_SERVER_CSR=FakeAppleProdPushServer.csr

TEAM_ID=6F44JJ9SDF

VOIP_PUSH_CLIENT_BUNDLE_ID=com.example.FakeApp
VOIP_PUSH_CLIENT_TOPIC=${VOIP_PUSH_CLIENT_BUNDLE_ID}.voip
VOIP_PUSH_CLIENT_PRIVATE_KEY=${VOIP_PUSH_CLIENT_TOPIC}.key.unencrypted.pem
VOIP_PUSH_CLIENT_CERT=${VOIP_PUSH_CLIENT_TOPIC}.cert.pem
VOIP_PUSH_CLIENT_CSR=${VOIP_PUSH_CLIENT_TOPIC}.csr

UNIVERSAL_PUSH_CLIENT_BUNDLE_ID=com.example.FakeApp
UNIVERSAL_PUSH_CLIENT_TOPIC=${UNIVERSAL_PUSH_CLIENT_BUNDLE_ID}
UNIVERSAL_PUSH_CLIENT_PRIVATE_KEY=${UNIVERSAL_PUSH_CLIENT_TOPIC}.universal.key.unencrypted.pem
UNIVERSAL_PUSH_CLIENT_CERT=${UNIVERSAL_PUSH_CLIENT_TOPIC}.universal.cert.pem
UNIVERSAL_PUSH_CLIENT_CSR=${UNIVERSAL_PUSH_CLIENT_TOPIC}.universal.csr

ALL_CA_CHAIN_CERT=FakeAppleAllCAChain.cert.pem

make_ca_dir_struct() {
    local dir=$1; shift

    mkdir -p ${dir}/private ${dir}/certs ${dir}/crl ${dir}/newcerts
    chmod 0700 ${dir}
    [[ -f ${dir}/serial ]] || echo '01' > ${dir}/serial
    [[ -f ${dir}/index.txt ]] || touch ${dir}/index.txt
    echo 'unique_subject = no' > ${dir}/index.txt.attr
}

display_section() {
    echo ==================================================
    echo $*
    echo ==================================================
}

make_signing_key_filename() {
    local team_id="$1"; shift
    local bundle_id="$1"; shift
    local key_id="$1"; shift

    echo "APNsAuthKey_${team_id}_${bundle_id}_${key_id}.p8"
}

gen_auth_signing_key() {
    local team_id="$1"; shift
    local bundle_id="$1"; shift
    local key_id="$1"; shift
    local filename=$(make_signing_key_filename "$team_id" "$bundle_id" "$key_id")

    openssl ecparam -name prime256v1 -genkey -noout | \
        openssl pkcs8 -topk8 -nocrypt -out $filename && \
        chmod 0600 $filename
}

make_ca_dir_struct CA
pushd CA

ln -sf ../${CA_CONFIG} ./

#####################################################################
# Apple Root CA
#####################################################################

# Generate CA private key (this could take a long time)
if [[ ! -f private/${CA_PRIVATE_KEY} ]]; then
    display_section Generating CA private key
    openssl genrsa -out private/${CA_PRIVATE_KEY} 2048
    chmod 0400 private/${CA_PRIVATE_KEY}
fi

# Generate the CA root cert
display_section Generating CA root cert

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

openssl ca \
    ${VERBOSE} \
    -notext \
    -batch \
    -startdate ${START_DATE} \
    -extensions v3_ca \
    -config ${CA_CONFIG} \
    -ss_cert certs/${CA_ROOT_CERT} \
    -out certs/Signed-${CA_ROOT_CERT}

    mv certs/Signed-${CA_ROOT_CERT} certs/${CA_ROOT_CERT}


# For this all to work, the intermediate CA must be within the root CA

#####################################################################
# Apple ISTCA2G1 Intermediate certificate
# This is actually issued by GeoTrust, but for obvious reasons
# we can't do that, so we will use Apple Root CA as the issuer.
#####################################################################

make_ca_dir_struct ISTCA2G1
[[ -f ./ISTCA2G1/crlnumber ]] || echo 1000 > ISTCA2G1/crlnumber

ln -sf ../../${ISTCA2G1_CONFIG} ISTCA2G1/

# Generate ISTCA2G1 CA private key
if [[ ! -f ISTCA2G1/private/${ISTCA2G1_PRIVATE_KEY} ]]; then
    display_section Generating ISTCA2G1 CA private key
    openssl genrsa -out ISTCA2G1/private/${ISTCA2G1_PRIVATE_KEY} 2048
    chmod 0400 ISTCA2G1/private/${ISTCA2G1_PRIVATE_KEY}
fi

# Generate the CSR for the ISTCA2G1 CA cert
display_section Generating CSR for ISTCA2G1 CA cert
openssl req \
    ${VERBOSE} \
    -new \
    -sha1 \
    -key ISTCA2G1/private/${ISTCA2G1_PRIVATE_KEY} \
    -out ISTCA2G1/${ISTCA2G1_ROOT_CSR} \
    -days 3650 \
    -config ISTCA2G1/${ISTCA2G1_CONFIG}

# Generate the ISTCA2G1 CA cert
display_section Generating ISTCA2G1 CA cert
openssl ca \
    ${VERBOSE} \
    -notext \
    -batch \
    -subj '/CN=Apple IST CA 2 - G1/OU=Certification Authority/O=Apple Inc./C=US' \
    -preserveDN \
    -extensions v3_istca2g1_intermediate_ca \
    -startdate ${START_DATE} \
    -config ${CA_CONFIG} \
    -in ISTCA2G1/${ISTCA2G1_ROOT_CSR} \
    -out ISTCA2G1/certs/${ISTCA2G1_ROOT_CERT}

# Generate a chain cert
display_section Generating ISTCA2G1 chain cert
[[ -f ISTCA2G1/certs/${ISTCA2G1_CHAIN_CERT} ]] && chmod 744 ISTCA2G1/certs/${ISTCA2G1_CHAIN_CERT}
cat ISTCA2G1/certs/${ISTCA2G1_ROOT_CERT} certs/${CA_ROOT_CERT} > ISTCA2G1/certs/${ISTCA2G1_CHAIN_CERT}
chmod 444 ISTCA2G1/certs/${ISTCA2G1_CHAIN_CERT}

#####################################################################
# Apple WWDR CA
#####################################################################

make_ca_dir_struct WWDRCA
[[ -f ./WWDRCA/crlnumber ]] || echo 1000 > WWDRCA/crlnumber

ln -sf ../../${WWDR_CA_CONFIG} WWDRCA/

# Generate WWDR CA private key
if [[ ! -f WWDRCA/private/${WWDR_CA_PRIVATE_KEY} ]]; then
    display_section Generating WWDR CA private key
    openssl genrsa -out WWDRCA/private/${WWDR_CA_PRIVATE_KEY} 2048
    chmod 0400 WWDRCA/private/${WWDR_CA_PRIVATE_KEY}
fi

# Generate the CSR for the WWDR CA cert
display_section Generating CSR for WWDR CA cert
openssl req \
    ${VERBOSE} \
    -new \
    -sha1 \
    -key WWDRCA/private/${WWDR_CA_PRIVATE_KEY} \
    -out WWDRCA/${WWDR_CA_ROOT_CSR} \
    -days 3650 \
    -config WWDRCA/${WWDR_CA_CONFIG}

# Generate the WWDR CA cert
display_section Generating WWDR CA cert
openssl ca \
    ${VERBOSE} \
    -notext \
    -batch \
    -startdate ${START_DATE} \
    -extensions v3_intermediate_ca \
    -config ${CA_CONFIG} \
    -in WWDRCA/${WWDR_CA_ROOT_CSR} \
    -out WWDRCA/certs/${WWDR_CA_ROOT_CERT}


#####################################################################
# WWDR Chain Cert
#####################################################################

# Generate a chain cert
display_section Generating WWDR chain cert
[[ -f WWDRCA/certs/${WWDR_CA_CHAIN_CERT} ]] && chmod 744 WWDRCA/certs/${WWDR_CA_CHAIN_CERT}
cat WWDRCA/certs/${WWDR_CA_ROOT_CERT} certs/${CA_ROOT_CERT} > WWDRCA/certs/${WWDR_CA_CHAIN_CERT}
chmod 444 WWDRCA/certs/${WWDR_CA_CHAIN_CERT}

#####################################################################
# Development Push Server
#####################################################################

# Generate the Dev Push Server key
if [[ ! -f ./ISTCA2G1/private/${DEV_PUSH_SERVER_PRIVATE_KEY} ]]; then
    display_section Generating Development Push Server key
    openssl genrsa -out ISTCA2G1/private/${DEV_PUSH_SERVER_PRIVATE_KEY} 2048
    chmod 400 ISTCA2G1/private/${DEV_PUSH_SERVER_PRIVATE_KEY}
fi

# Generate the Development Push Server CSR
display_section Generating CSR for Development Push Server cert
openssl req \
    ${VERBOSE} \
    -new \
    -sha256 \
    -key ISTCA2G1/private/${DEV_PUSH_SERVER_PRIVATE_KEY} \
    -out ISTCA2G1/${DEV_PUSH_SERVER_CSR} \
    -days 365 \
    -config ISTCA2G1/${ISTCA2G1_CONFIG}

# Generate the development push server cert
display_section Generating Development Push Server cert
openssl ca \
    ${VERBOSE} \
    -notext \
    -batch \
    -days $(( 365 * 2 )) \
    -subj '/CN=api.development.push.apple.com/OU=management:idms.group.533599/O=Apple Inc./ST=California/C=US' \
    -preserveDN \
    -policy policy_loose \
    -extensions dev_server_cert \
    -startdate ${START_DATE} \
    -config ISTCA2G1/${ISTCA2G1_CONFIG} \
    -in ISTCA2G1/${DEV_PUSH_SERVER_CSR} \
    -out ISTCA2G1/certs/${DEV_PUSH_SERVER_CERT}

display_section Verifying Development Push Server cert
openssl verify \
    -CAfile ISTCA2G1/certs/${ISTCA2G1_CHAIN_CERT} \
    ISTCA2G1/certs/${DEV_PUSH_SERVER_CERT}

#####################################################################
# Production Push Server
#####################################################################

# Generate the Prod Push Server key
if [[ ! -f ./ISTCA2G1/private/${PROD_PUSH_SERVER_PRIVATE_KEY} ]]; then
    display_section Generating Production Push Server key
    openssl genrsa -out ISTCA2G1/private/${PROD_PUSH_SERVER_PRIVATE_KEY} 2048
    chmod 400 ISTCA2G1/private/${PROD_PUSH_SERVER_PRIVATE_KEY}
fi

# Generate the Production Push Server CSR
display_section Generating CSR for Production Push Server cert
openssl req \
    ${VERBOSE} \
    -new \
    -sha256 \
    -key ISTCA2G1/private/${PROD_PUSH_SERVER_PRIVATE_KEY} \
    -out ISTCA2G1/${PROD_PUSH_SERVER_CSR} \
    -days 365 \
    -config ISTCA2G1/${ISTCA2G1_CONFIG}

# Generate the production push server cert
display_section Generating Production Push Server cert
openssl ca \
    ${VERBOSE} \
    -notext \
    -batch \
    -subj '/CN=api.push.apple.com/OU=management:idms.group.533599/O=Apple Inc./ST=California/C=US' \
    -days $(( 365 * 2 )) \
    -preserveDN \
    -policy policy_loose \
    -extensions prod_server_cert \
    -startdate ${START_DATE} \
    -config ISTCA2G1/${ISTCA2G1_CONFIG} \
    -in ISTCA2G1/${PROD_PUSH_SERVER_CSR} \
    -out ISTCA2G1/certs/${PROD_PUSH_SERVER_CERT}

display_section Verifying Production Push Server cert
openssl verify \
    -CAfile ISTCA2G1/certs/${ISTCA2G1_CHAIN_CERT} \
    ISTCA2G1/certs/${PROD_PUSH_SERVER_CERT}

#####################################################################
# APNS VoIP Push Client Cert
#####################################################################

# Generate the VoIP Push Client Certificate key
if [[ ! -f ./WWDRCA/private/${VOIP_PUSH_CLIENT_PRIVATE_KEY} ]]; then
    display_section Generating Production Push Client key
    openssl genrsa -out WWDRCA/private/${VOIP_PUSH_CLIENT_PRIVATE_KEY} 2048
    chmod 400 WWDRCA/private/${VOIP_PUSH_CLIENT_PRIVATE_KEY}
fi

# Generate the Production Push Client CSR
display_section Generating CSR for VoIP Push Client cert
openssl req \
    ${VERBOSE} \
    -new \
    -sha256 \
    -key WWDRCA/private/${VOIP_PUSH_CLIENT_PRIVATE_KEY} \
    -out WWDRCA/${VOIP_PUSH_CLIENT_CSR} \
    -days 365 \
    -config WWDRCA/${WWDR_CA_CONFIG}

# Generate the production Push Client cert
display_section Generating VoIP Push Client cert
openssl ca \
    ${VERBOSE} \
    -notext \
    -batch \
    -subj '/UID='${VOIP_PUSH_CLIENT_TOPIC}'/CN=VoIP Services: '${VOIP_PUSH_CLIENT_BUNDLE_ID}'/OU='${TEAM_ID}'/O=Example, LLC/C=US' \
    -preserveDN \
    -startdate ${START_DATE} \
    -days $(( 365 * 2 )) \
    -md sha256 \
    -policy policy_loose \
    -extensions v3_push_cert \
    -config WWDRCA/${WWDR_CA_CONFIG} \
    -in WWDRCA/${VOIP_PUSH_CLIENT_CSR} \
    -out WWDRCA/certs/${VOIP_PUSH_CLIENT_CERT}

display_section Verifying Production VoIP Push Client cert
openssl verify \
    -CAfile WWDRCA/certs/${WWDR_CA_CHAIN_CERT} \
    WWDRCA/certs/${VOIP_PUSH_CLIENT_CERT}

#####################################################################
# APNS Universal Multi-Topic Push Client Cert
#####################################################################

# Generate the Universal Multi-Topic Client key
if [[ ! -f ./WWDRCA/private/${UNIVERSAL_PUSH_CLIENT_PRIVATE_KEY} ]]; then
    display_section Generating Universal Push Client key
    openssl genrsa -out WWDRCA/private/${UNIVERSAL_PUSH_CLIENT_PRIVATE_KEY} 2048
    chmod 400 WWDRCA/private/${UNIVERSAL_PUSH_CLIENT_PRIVATE_KEY}
fi

# Generate the universal push Client CSR
display_section Generating CSR for Universal Push Client cert
openssl req \
    ${VERBOSE} \
    -new \
    -sha256 \
    -key WWDRCA/private/${UNIVERSAL_PUSH_CLIENT_PRIVATE_KEY} \
    -out WWDRCA/${UNIVERSAL_PUSH_CLIENT_CSR} \
    -days 365 \
    -config WWDRCA/${WWDR_CA_CONFIG}

# Generate the universal push Client cert
display_section Generating Universal Push Client cert
openssl ca \
    ${VERBOSE} \
    -notext \
    -batch \
    -subj '/UID='${UNIVERSAL_PUSH_CLIENT_TOPIC}'/CN=Apple Push Services: '${UNIVERSAL_PUSH_CLIENT_BUNDLE_ID}'/OU='${TEAM_ID}'/O=Example, LLC/C=US' \
    -preserveDN \
    -days $(( 365 * 2 )) \
    -md sha256 \
    -policy policy_loose \
    -extensions v3_universal_push_cert \
    -startdate ${START_DATE} \
    -config WWDRCA/${WWDR_CA_CONFIG} \
    -in WWDRCA/${UNIVERSAL_PUSH_CLIENT_CSR} \
    -out WWDRCA/certs/${UNIVERSAL_PUSH_CLIENT_CERT}

display_section Verifying Universal Push Client cert
openssl verify \
    -CAfile WWDRCA/certs/${WWDR_CA_CHAIN_CERT} \
    WWDRCA/certs/${UNIVERSAL_PUSH_CLIENT_CERT}

ALL_CA_CHAIN_CERT=FakeAppleAllCAChain.cert.pem
# Generate a chain cert containing all CAs
display_section Generating All CA chain cert
[[ -f ${ALL_CA_CHAIN_CERT} ]] && chmod 744 ${ALL_CA_CHAIN_CERT}
cat WWDRCA/certs/${WWDR_CA_ROOT_CERT} ISTCA2G1/certs/${ISTCA2G1_ROOT_CERT} certs/${CA_ROOT_CERT} > ${ALL_CA_CHAIN_CERT}
chmod 444 ${ALL_CA_CHAIN_CERT}

popd

# Generate EC private keys for token-based authentication
mkdir -p apns_auth_keys
chmod 0700 apns_auth_keys
pushd apns_auth_keys

# Generate the Token Signing PKCS8 private keys
display_section Generating APNS auth token signing PKCS8 private keys

gen_auth_signing_key "${TEAM_ID}" "${VOIP_PUSH_CLIENT_TOPIC}" "V782ZPDP1Z"
gen_auth_signing_key "${TEAM_ID}" "${UNIVERSAL_PUSH_CLIENT_TOPIC}" "UB40ZXKCDZ"

popd

