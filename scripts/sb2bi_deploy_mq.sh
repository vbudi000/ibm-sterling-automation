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

si_instanceid="${SI_INSTANCEID}"
mq_namespace="sterling-b2bi-${si_instanceid}-mq"
mq_name="mq"

mq_version="9.2.5.0-r3"
mq_admin_password="passw0rd"
mq_app_password="passw0rd"

# Entitlement
# -----------------------------------------------------------------------------
entitled_registry="cp.icr.io"
entitled_registry_user=cp
entitled_registry_key="${ENTITLED_REGISTRY_KEY}"

# Others
# -----------------------------------------------------------------------------
mq_registry_secret=mymq-ibm-registry-secret
mq_service_account=mymq-sa
mq_secret=mymq-secret
mq_svc_data="${mq_name}-data"
mq_svc_web="${mq_name}-web"
mq_route_web="${mq_name}-web"
mq_rwo_class="managed-nfs-storage"

# Create Kubernetes namespace
# -----------------------------------------------------------------------------
cat << EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: "${mq_namespace}"
EOF

# Create ServiceAccount for MQueue
# -----------------------------------------------------------------------------
cat << EOF | oc apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: "${mq_service_account}"
  namespace: "${mq_namespace}"
EOF


# Create Secrets on Kubernetes
# -----------------------------------------------------------------------------
oc adm policy add-scc-to-user privileged -n ${mq_namespace} -z ${mq_service_account}

oc create secret docker-registry ${mq_registry_secret} -n ${mq_namespace} \
    --docker-server=${entitled_registry} \
    --docker-username=${entitled_registry_user} \
    --docker-password=${entitled_registry_key}


oc create secret generic ${mq_secret} -n ${mq_namespace} \
  --from-literal=adminPassword=${mq_admin_password} \
  --from-literal=appPassword=${mq_app_password}

cat << EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: "${mq_svc_data}"
  namespace: "${mq_namespace}"
spec:
  selector:
    app: "${mq_name}"
  type: ClusterIP
  ports:
    - protocol: TCP
      port: 1414
      targetPort: 1414
EOF

cat << EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: "${mq_svc_web}"
  namespace: "${mq_namespace}"
spec:
  selector:
    app: "${mq_name}"
  type: ClusterIP
  ports:
    - protocol: TCP
      port: 9443
      targetPort: 9443
EOF

cat << EOF | oc apply -f -
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: "${mq_route_web}"
  namespace: "${mq_namespace}"
spec:
  tls:
    insecureEdgeTerminationPolicy: Redirect
    termination: passthrough
  to:
    kind: Service
    name: "${mq_svc_web}"
  wildcardPolicy: None
EOF

# Deploy MQ on Kubernetes
# -----------------------------------------------------------------------------
cat << EOF | tee ss.yaml | oc apply -f -
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: "${mq_name}"
  namespace: "${mq_namespace}"
spec:
  selector:
    matchLabels:
      app: "${mq_name}"
  serviceName: "${mq_name}"
  replicas: 1
  template:
    metadata:
      labels:
        app: "${mq_name}"
    spec:
      serviceAccount: "${mq_service_account}"
      containers:
        - name: "${mq_name}"
          securityContext:
            privileged: true
          image: icr.io/ibm-messaging/mq:${mq_version}
          env:
            - name: LICENSE
              value: accept
            - name: MQ_QMGR_NAME
              value: qmgr
          ports:
            - containerPort: 1414
              name: mq
            - containerPort: 9443
              name: mq-web
          imagePullPolicy: IfNotPresent
          volumeMounts:
            - name: mqvol
              mountPath: /var/mqm
          imagePullSecrets:
            - name: mq_registry_secret
  volumeClaimTemplates:
    - metadata:
        name: mqvol
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 20Gi
        storageClassName: "${mq_rwo_class}"
EOF