openssl cms -verify \
  -in signature.p7s \
  -inform DER \
  -content manifest.raucm \
  -CAfile certificate.pem \
  -no_signer_cert_verify \
  -no_attr_verify \
  -no_content_verify