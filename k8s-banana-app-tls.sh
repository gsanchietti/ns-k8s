#!/bin/bash

hostname=$(hostname -f)

cat <<EOF > banana-ingress-tls-prod.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-banana-tls-prod
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/issuer: "letsencrypt-prod"
    cert-manager.io/issue-temporary-certificate: "true"
spec:
  tls:
  - hosts:
    - $hostname
    secretName: banana-tls-prod
  rules:
  - host: $hostname
    http:
      paths:
      - path: /banana
        pathType: Prefix
        backend:
          service:
            name: banana-service
            port:
              number: 5678
EOF

kubectl apply -f banana-ingress-tls-prod.yaml
