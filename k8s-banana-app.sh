#!/bin/bash


cat <<EOF > banana-app.yaml
kind: Pod
apiVersion: v1
metadata:
  name: banana-app
  labels:
    app: banana
spec:
  containers:
    - name: banana-app
      image: hashicorp/http-echo
      args:
        - "-text=banana"

---

kind: Service
apiVersion: v1
metadata:
  name: banana-service
spec:
  selector:
    app: banana
  ports:
    - port: 5678 # Default port for image
EOF


kubectl apply -f banana-app.yaml

cat <<EOF > banana-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-banana
spec:
  rules:
  - http:
      paths:
      - path: /banana
        pathType: Prefix
        backend:
          service:
            name: banana-service
            port:
              number: 5678
 
EOF

kubectl apply -f banana-ingress.yaml
