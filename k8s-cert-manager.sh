#!/bin/bash

MAIL="root@"$(hostname -f)

kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.1.0/cert-manager.yaml

cat <<EOF > le-staging.yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
   # The ACME server URL
   server: https://acme-staging-v02.api.letsencrypt.org/directory
   # Email address used for ACME registration
   email: $MAIL
   # Name of a secret used to store the ACME account private key
   privateKeySecretRef:
      name: letsencrypt-staging
   # Enable the HTTP-01 challenge provider
   solvers:
      - http01:
           ingress:
             serviceType: ClusterIP
             class:  nginx
EOF

cat <<EOF > le-prod.yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
   # The ACME server URL
   server: https://acme-v02.api.letsencrypt.org/directory
   # Email address used for ACME registration
   email: $MAIL
   # Name of a secret used to store the ACME account private key
   privateKeySecretRef:
      name: letsencrypt-prod
   # Enable the HTTP-01 challenge provider
   solvers:
      - http01:
           ingress:
             serviceType: ClusterIP
             class:  nginx
EOF

echo "Waiting 30 seconds for cert-manager to start..."
sleep 30

kubectl apply -f le-staging.yaml
kubectl apply -f le-prod.yaml
