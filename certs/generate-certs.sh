#!/bin/bash
set -euo pipefail

CERTS_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$CERTS_DIR"

echo "=== Generating self-signed TLS certificates ==="

# Skip if certs already exist
if [ -f server.crt ] && [ -f server.key ]; then
  echo "Certificates already exist. Delete them to regenerate."
  echo "  rm $CERTS_DIR/server.{crt,key} $CERTS_DIR/ca.{crt,key}"
  exit 0
fi

# Generate CA key + cert
echo "1/3  Creating Certificate Authority..."
openssl genrsa -out ca.key 4096 2>/dev/null
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt \
  -subj "/C=CZ/ST=Prague/O=LoadBalancingLab/CN=Lab CA" 2>/dev/null

# Generate server key + CSR
echo "2/3  Creating server certificate..."
openssl genrsa -out server.key 2048 2>/dev/null

# Create SAN config
cat > san.cnf << EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

openssl req -new -key server.key \
  -subj "/C=CZ/ST=Prague/O=LoadBalancingLab/CN=localhost" \
  -out server.csr -config san.cnf 2>/dev/null

# Sign with CA
echo "3/3  Signing certificate with CA..."
openssl x509 -req -days 365 \
  -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out server.crt -extensions v3_req -extfile san.cnf 2>/dev/null

# Cleanup
rm -f server.csr san.cnf ca.srl

echo ""
echo "Done! Generated files in $CERTS_DIR:"
ls -la *.{crt,key} 2>/dev/null
echo ""
echo "To trust the CA on your system (optional):"
echo "  sudo cp $CERTS_DIR/ca.crt /usr/local/share/ca-certificates/lab-ca.crt"
echo "  sudo update-ca-certificates"
