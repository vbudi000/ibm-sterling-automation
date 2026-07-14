#!/bin/bash

fullexec=$(readlink -f "${BASH_SOURCE[0]}")
fullpath=$(dirname ${fullexec})
filepath=${fullpath}/../roles/ssp_deploy/files/clusterAdministration
tmplpath=${fullpath}/../roles/ssp_deploy/templates/namespaceAdministration

if [ -z "$SSP_INSTANCEID" ]; then
    echo "Error=SSP_INSTANCEID is not defined or is empty."
    exit 1
fi

if [ -z "$ENTITLED_REGISTRY_KEY" ]; then
    echo "Error=ENTITLED_REGISTRY_KEY is not defined or is empty."
    exit 1
fi

# check using oc whoami 
oc whoami &> /dev/null

# Capture the return code
return_code=$?

if [ $return_code -ne 0 ]; then
    echo "Must login to OpenShift ,oc whoami failed with return code $return_code=You are not authenticated or the server is unreachable."
    exit 1
fi 

ssp_instanceid="${SSP_INSTANCEID}"
entitled_registry_key="${ENTITLED_REGISTRY_KEY}"

ssp_version="6.1.0.0.03plus"
ssp_license_type="non-prod" # prod or no-prod

ssp_sys_passphrase="Passw0rd@"
ssp_keycert_store_passphrase="changeit"
ssp_keycert_encrypt_passphrase="Change1t@"
ssp_custom_keycert_passphrase="Change1t@"

ssp_timezone="UTC"
# lookup('ansible.builtin.password', '/dev/null', chars=['ascii_letters', 'digits'], length=8)

# Storage configuration
ssp_storage_class="ocs-external-storagecluster-ceph-rbd"
ssp_storage_capacity="1Gi"

# CPU and memory limits configuration on the container
ssp_cpu_limits="1000m"
ssp_mem_limits="3Gi"
ssp_ephemeral_storage_limits="6Gi"

# CPU and memory request configuration on the container
ssp_cpu_requests="1000m"
ssp_mem_requests="3Gi"
ssp_ephemeral_storage_requests="4Gi"

# Configure instance
# -----------------------------------------------------------------------------
ssp_namespace="ibm-ssp-${ssp_instanceid}-engine"
ssp_cm_namespace="ibm-ssp-${ssp_instanceid}-cm"

entitled_registry="cp.icr.io"
entitled_registry_user=cp

# Role Internal
# -----------------------------------------------------------------------------
my_workdir=/tmp

ssp_registry_secret=ibm-registry-secret
ssp_secret=ibm-ssp-secret
ssp_keycert_secret=ssp-cm-keycert
ssp_use_dynamic_provisioning=false
ssp_nameoverride=ssp-${ssp_instanceid}

ssp_generate_certificates=false

# https://github.com/IBM/charts/tree/master/repo/ibm-helm
# compatibility_matrix:
#   6.1.0.0.03plus:
#     helm_version="1.3.5"
#     image_repository="cp.icr.io/cp/ibm-ssp-engine/ssp-engine-docker-image"
#     image_tag="6.1.0.0.03plus"

oc new-project ${ssp_namespace}

# Create Secrets on Kubernetes
# -----------------------------------------------------------------------------
oc create secret docker-registry ${ssp_registry_secret} -n ${ssp_namespace} \
    --docker-server=${entitled_registry} \
    --docker-username=${entitled_registry_user} \
    --docker-password=${entitled_registry_key}


oc create secret generic ${ssp_secret} -n ${ssp_namespace} \
  --from-literal=sysPassphrase=${ssp_sys_passphrase} \
  --from-literal=keyCertStorePassphrase=${ssp_keycert_store_passphrase} \
  --from-literal=keyCertEncryptPassphrase=${ssp_keycert_encrypt_passphrase} \
  --from-literal=customKeyCertPassphrase=${ssp_custom_keycert_passphrase}

oc apply -n ${ssp_namespace}  -f ${filepath}
cat ${tmplpath}/ibm-ssp-engine-rb.yaml.j2 | sed "s#{{ ssp_namespace }}#${ssp_namespace}#g" | oc apply -f -
cat ${tmplpath}/ibm-ssp-engine-rb-scc.yaml.j2 | sed "s#{{ ssp_namespace }}#${ssp_namespace}#g" | oc apply -f -

rm -rf ${my_workdir}/ibm-ssp-engine
helm repo add ibm-helm https://raw.githubusercontent.com/IBM/charts/master/repo/ibm-helm --force-update
helm pull --untar ibm-helm/ibm-ssp-engine --version 1.3.5 --untardir ${my_workdir}

cd ${my_workdir}
helm install --timeout 10m0s -f ${fullpath}/values-ssp.yaml -n ${ssp_namespace} ssp0 ibm-ssp-engine
