#!/bin/bash

minio_provider="standard"
minio_action="install"

minio_namespace="sterling-minio"

minio_root_user="root"
minio_root_password="passw0rd"
minio_storage_size="10Gi"

minio_storageclass="ocs-external-storagecluster-ceph-rbd"

oc new-project ${minio_namespace}

# Create Secrets on Kubernetes
# -----------------------------------------------------------------------------
oc create secret generic minio-secret -n ${minio_namespace} \
  --from-literal=MINIO_ROOT_USER=${minio_root_user} \
  --from-literal=MINIO_ROOT_PASSWORD=${minio_root_password}
oc label secret minio-secret app=minio

oc create sa minio-sa -n ${minio_namespace}

oc adm policy add-scc-to-user -n ${minio_namespace} -z minio-sa anyuid

cat << EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-data-pvc
  namespace: "${minio_namespace}"
  labels:
    app: minio
    app.kubernetes.io/name: minio
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: "${minio_storageclass}"
  # volumeMode: Filesystem
  resources:
    requests:
      storage: "${minio_storage_size}"
EOF

oc create configmap minio-env -n ${minio_namespace} \
  --from-literal=MINIO_ROOT_USER=${minio_root_user} \
  --from-literal=MINIO_ROOT_PASSWORD=${minio_root_password}
oc label configmap minio-env app=minio


# Apply Deployment
# -----------------------------------------------------------------------------
cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: "${minio_namespace}"
  labels:
    app: minio
    app.kubernetes.io/name: minio
spec:
  selector:
    matchLabels:
      app: minio
  replicas: 1
  template:
    metadata:
      labels:
        app: minio
    spec:
      serviceAccountName: minio-sa
      containers:
        - name: minio
          image: "quay.io/minio/minio:latest"
          args:
            - server
            - /data
            - --console-address
            - ":9001"
          ports:
            - name: api-port
              containerPort: 9000
              protocol: TCP
            - name: console-port
              containerPort: 9001
              protocol: TCP
          envFrom:
            - configMapRef:
                name: minio-env
            - secretRef:
                name: minio-secret
          volumeMounts:
            - name: minio-data
              mountPath: /data
            # - name: custom-conf-data
            #   mountPath: /custom-conf/
      volumes:
        - name: minio-data
          persistentVolumeClaim:
            claimName: minio-data-pvc
EOF

# Create Service and Route
# -----------------------------------------------------------------------------
cat << EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: minio-svc
  namespace: "${minio_namespace}"
  labels:
    app: minio
spec:
  selector:
    app: minio
  ports:
    - name: api-port
      port: 9000
      protocol: TCP
      targetPort: 9000
    - name: console-port
      port: 9001
      protocol: TCP
      targetPort: 9001
  type: ClusterIP
EOF

cat << EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: minio-api
  namespace: "${minio_namespace}"
  labels:
    app.kubernetes.io/name: minio
    release: s0
spec:
  to:
    kind: Service
    name: minio-svc
  port:
    targetPort: api-port
  tls:
    termination: edge
  wildcardPolicy: None
EOF

cat << EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: minio-console
  namespace: "${minio_namespace}"
  labels:
    app.kubernetes.io/name: minio
    release: s0
spec:
  to:
    kind: Service
    name: minio-svc
  port:
    targetPort: console-port
  tls:
    termination: edge
  wildcardPolicy: None
EOF
