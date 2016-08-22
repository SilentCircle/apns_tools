# APNS Tools

This repository contains scripts to assist with testing APNS clients.

The tools currently provided are described below.

## Fake Apple Certificates

`fake_apple_certs.sh` will generate

- A fake Apple Root CA certificate and private key
- A fake Apple Apple Worldwide Developer Relations CA certificate and private
  key

These attempt to duplicate the real Apple certificates as closely as possible,
obviously with different serial numbers, public keys, and Subject Key
Identifiers and Authority Key Identifiers.

The purpose of these certs is to create fake Apple Push certificates for use in
an APNS simulation environment. The simulation environment would need to
provide the fake Apple root certificate to any test clients, and serve the root
and WWDR certificates along with the server cert on the simulation server.

## TODO

- Add generation of fake APNS server certificate
- Add generation of fake APNS client certificates of different types:
  - Regular, or enterprise development/production
  - VoIP (VoIP certificates support both development and production)
  - Single topic or multi-topic

<!--
ex: set ts=4 sts=4 sw=4 filetype=md tw=68:
-->
