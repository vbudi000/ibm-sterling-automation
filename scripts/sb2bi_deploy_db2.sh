#!/bin/bash

# check whether the variables SI_INSTANCEID and ENTITLED_REGISTRY_KEY exists
if [ -z "$SI_INSTANCEID" ]; then
    echo "Error: SI_INSTANCEID is not defined or is empty."
    exit 1
fi

if [ -z "$ENTITLED_REGISTRY_KEY" ]; then
    echo "Error: ENTITLED_REGISTRY_KEY is not defined or is empty."
    exit 1
fi

# check using oc whoami 
oc whoami &> /dev/null

# Capture the return code
return_code=$?

if [ $return_code -ne 0 ]; then
    echo "Must login to OpenShift ,oc whoami failed with return code $return_code: You are not authenticated or the server is unreachable."
    exit 1
fi 

si_instanceid=${SI_INSTANCEID}
db2_namespace="sterling-b2bi-${si_instanceid}-db2"
db2_password="passw0rd"
db2_version='11.5.9.0'

db2_instance_name="db2inst1"
db2_user="db2inst1"
db2_dbname="B2BI"

# Entitlement
# -----------------------------------------------------------------------------
entitled_registry="cp.icr.io"
entitled_registry_user=cp
entitled_registry_key=${ENTITLED_REGISTRY_KEY}

# Others
# -----------------------------------------------------------------------------
db2_registry_secret="mydb2-ibm-registry-secret"
db2_service_account="mydb2-sa"
db2_secret="mydb2-secret"
db2_id="mydb2"
db2_svc_ci="${db2_id}-ci"
db2_svc_lb="${db2_id}-lb"

db2_storage_size="10Gi"

cat << EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
    name: "${db2_namespace}"
EOF

# Create ServiceAccount for DB2
# -----------------------------------------------------------------------------
cat << EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
    name: "${db2_service_account}"
    namespace: "${db2_namespace}"
EOF

oc create secret docker-registry ${db2_registry_secret} -n ${db2_namespace} \
    --docker-server=${entitled_registry} \
    --docker-username=${entitled_registry_user} \
    --docker-password=${entitled_registry_key}


oc create secret generic ${db2_secret} -n ${db2_namespace} \
  --from-literal=DB2INST1_PASSWORD=${db2_password}

my_storage_class="redhat-external"
file_sc="managed-nfs-storage"
oc adm policy add-scc-to-user -z mydb2-sa privileged -n ${db2_namespace}

cat << EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: "${db2_svc_ci}"
  namespace: "${db2_namespace}"
spec:
  type: ClusterIP
  selector:
    app: "${db2_id}"
  ports:
    - name: "${db2_id}-ci-srv"
      protocol: TCP
      port: 50000
      targetPort: 50000
    - name: "${db2_id}-ci-srvs"
      protocol: TCP
      port: 50001
      targetPort: 50001
EOF

cat << EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: "${db2_svc_lb}"
  namespace: "${db2_namespace}"
spec:
  selector:
    app: "${db2_id}"
  type: LoadBalancer
  ports:
    - name: "${db2_id}-lb-srv"
      protocol: TCP
      port: 50000
      targetPort: 50000
    - name: "${db2_id}-lb-srvs"
      protocol: TCP
      port: 50001
      targetPort: 50001
EOF

# Deploy DB2 on Kubernetes
# -----------------------------------------------------------------------------
cat << EOF | oc apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: "${db2_id}"
  namespace: "${db2_namespace}"
spec:
  selector:
    matchLabels:
      app: "${db2_id}"
  serviceName: "${db2_id}"
  replicas: 1
  template:
    metadata:
      labels:
        app: "${db2_id}"
        app-instance: "${db2_instance_name}"
        app-dbname: "${db2_dbname}"
    spec:
      serviceAccount: "${db2_service_account}"
      containers:
        - name: "${db2_id}"
          securityContext:
            privileged: true
          image: "icr.io/db2_community/db2:${db2_version}"
          env:
            - name: DB2INST1_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: "${db2_secret}"
                  key: DB2INST1_PASSWORD
            - name: LICENSE
              value: accept
            - name: DB2INSTANCE
              value: "${db2_instance_name}"
          ports:
            - containerPort: 50000
              name: "${db2_id}-srv"
            - containerPort: 50001
              name: "${db2_id}-srvs"
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - mountPath: /database
              name: db2vol
          imagePullSecrets:
            - name: "${db2_registry_secret}"
  volumeClaimTemplates:
    - metadata:
        name: db2vol
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: ${db2_storage_size}
        storageClassName: "managed-nfs-storage"
EOF