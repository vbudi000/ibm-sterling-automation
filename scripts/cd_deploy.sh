#!/bin/bash
fullexec=$(readlink -f "${BASH_SOURCE[0]}")
fullpath=$(dirname ${fullexec})
# 6.3.0.3_ifix003:
#     helm_version: "1.3.8"
#     image_repository: "cp.icr.io/cp/ibm-connectdirect/cdu6.3_certified_container_6.3.0.3"
#     image_tag: "6.3.0.3_ifix003"

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

cd_namespace="sterling-cdnode01-dev"
cd_nodename="CDNODE01" # Specify the node of C:D application

cd_version="6.3.0.7-iFix022-2026-07-02"

cd_admin_password="passw0rd"
cd_appuser_pwd="passw0rd"
cd_local_cert_passphrase="changeit"
cd_keystore_password="changeit"

cd_license_type="non-prod" # prod or no-prod

# Storage configuration
cd_storage_class="ocs-external-storagecluster-ceph-rbd"
cd_storage_capacity="1Gi"

# CPU and memory limits configuration on the container
cd_cpu_limits="500m"
cd_mem_limits="2000Mi"
cd_ephemeral_storage_limits="5Gi"

# CPU and memory request configuration on the container
cd_cpu_requests="500m"
cd_mem_requests="2000Mi"
cd_ephemeral_storage_requests="3Gi"

# Entitlement
# -----------------------------------------------------------------------------
entitled_registry="cp.icr.io"
entitled_registry_user="cp"
entitled_registry_key="${ENTITLED_REGISTRY_KEY}"

# Others
# -----------------------------------------------------------------------------
my_workdir="/tmp"

cd_deploy_sum_enabled=1 # sumEnabled value could either 0 or 1 to disable/enable Standard User Mode (SUM)  feature
cd_deploy_registry_secret=mycd-ibm-registry-secret
cd_deploy_secret=mycd-secret
cd_deploy_cert_secret=mycd-cert-secret
cd_cert_crt="${my_workdir}/cdcert.crt"  # CD install script only support extensions .crt, .pem and .cer
cd_cert_key="${my_workdir}/cdkey.pem"
cd_cert_pem="${my_workdir}/cdcert.pem"
cd_use_dynamic_provisioning=false

# Create Kubernetes namespace
# -----------------------------------------------------------------------------
oc new-project ${cd_namespace}

# Create Secrets on Kubernetes
# -----------------------------------------------------------------------------
oc create secret docker-registry ${cd_deploy_registry_secret} -n ${cd_namespace} \
    --docker-server=${entitled_registry} \
    --docker-username=${entitled_registry_user} \
    --docker-password=${entitled_registry_key}


oc create secret generic ${cd_deploy_secret} -n ${cd_namespace} \
  --from-literal=admPwd=${cd_admin_password} \
  --from-literal=appUserPwd=${cd_appuser_pwd} \
  --from-literal=crtPwd=${cd_local_cert_passphrase} \
  --from-literal=keyPwd=${cd_keystore_password}

# Install SCC and PSP
oc apply -n ${cd_namespace} -f ${fullpath}/../roles/cd_deploy/files/clusterAdministration

openssl req -x509 -sha512 -days 3650 -newkey rsa:2048 -new -nodes -keyout ${cd_cert_key} -out ${cd_cert_crt} -subj '/CN=${cd_nodename}'
cat ${cd_cert_key} ${cd_cert_crt} > ${cd_cert_pem}

oc create secret generic ${cd_deploy_cert_secret} -n ${cd_namespace} \
  --from-file=cdcert.pem=${cd_cert_pem}

rm -rf ${my_workdir}/ibm-connect-direct
helm repo add ibm-helm https://raw.githubusercontent.com/IBM/charts/master/repo/ibm-helm --force-update
helm pull --untar ibm-helm/ibm-connect-direct --version 1.3.34 --untardir ${my_workdir}

cd ${my_workdir}
helm install --timeout 10m0s -f ${fullpath}/values-cd.yaml -n ${cd_namespace} cd0 ibm-connect-direct
