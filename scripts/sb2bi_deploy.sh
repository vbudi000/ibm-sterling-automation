#!/bin/bash
fullexec=$(readlink -f "${BASH_SOURCE[0]}")
fullpath=$(dirname ${fullexec})

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

si_action="install"
si_version="6.2.0.2"
si_licensetype="non-prod" # prod or no-prod

# Entitlement
# -----------------------------------------------------------------------------
entitled_registry="cp.icr.io"
entitled_registry_user=cp
entitled_registry_key="${ENTITLED_REGISTRY_KEY}"

# Defaults for B2Bi instances.
# -----------------------------------------------------------------------------
my_workdir=/tmp
si_instanceid=${SI_INSTANCEID}
si_namespace="sterling-b2bi-${si_instanceid}-app"
si_db2_namespace="sterling-b2bi-${si_instanceid}-db2"
si_mq_namespace="sterling-b2bi-${si_instanceid}-mq"
si_registry_secret=si-ibm-registry
si_system_passphrase_secret=si-system-passphrase-secret
si_db_secret=si-db-secret
si_jms_secret=si-jms-secret
si_liberty_secret=si-liberty-secret

db2_namespace=${si_db2_namespace}
db2_secret=mydb2-secret
db2_id=mydb2

mq_namespace=${si_mq_namespace}
mq_secret=mymq-secret

si_instanceid="${SI_INSTANCEID}"
si_libertykeystorepassword="changeit"
si_system_passphrase="passw0rd"

# Helm Variables
# -----------------------------------------------------------------------------
si_helmchart="${my_workdir}/ibm-b2bi-prod/"
curpath=$(dirname $0)

# Create Kubernetes namespace
# -----------------------------------------------------------------------------
oc new-project ${si_namespace}

# Create Secrets on Kubernetes
# -----------------------------------------------------------------------------
oc create secret docker-registry ${si_registry_secret} -n ${si_namespace} \
    --docker-server=${entitled_registry} \
    --docker-username=${entitled_registry_user} \
    --docker-password=${entitled_registry_key}


oc create secret generic ${si_system_passphrase_secret} -n ${si_namespace} \
  --from-literal=SYSTEM_PASSPHRASE=${si_system_passphrase} 

oc create secret generic ${si_liberty_secret} -n ${si_namespace} \
  --from-literal=LIBERTY_KEYSTORE_PASSWORD=${si_libertykeystorepassword} 

cat $curpath/../roles/sb2bi_deploy/templates/default_sa_rbac.yml.j2 | sed "s|{{ si_namespace }}|${si_namespace}|g" | oc apply -f -
 
si_dbvendor="DB2"
si_dbhost="${db2_id}-ci.${db2_namespace}.svc.cluster.local"
si_dbport="50000"
si_dbdrivers="db2jcc4.jar"
si_dbname="B2BI"
si_dbuser="db2inst1"
si_dbpassword=$(oc extract secret/${db2_secret} -n ${db2_namespace} --keys=DB2INST1_PASSWORD --to=-)

oc create secret generic ${si_db_secret} -n ${si_namespace} \
  --from-literal=DB_USER=${si_dbuser} \
  --from-literal=DB_PASSWORD=${si_dbpassword} 

si_jmsuser="app"
si_jmsvendor="IBMMQ"
si_jmsconnectionfactory="com.ibm.mq.jms.MQQueueConnectionFactory"
si_jmsqueuename="DEV.QUEUE.1"
si_jmschannel="DEV.APP.SVRCONN"
si_jmsenablessl="false"
si_jmspassword=$(oc extract secret/${mq_secret} -n ${mq_namespace} --keys=appPassword --to=-)
si_jmshost="mq-data.${mq_namespace}.svc.cluster.local"
si_jmsport="1414"
si_jmsconnectionnamelist="${si_jmshost}(${si_jmsport})"

oc create secret generic ${si_jms_secret} -n ${si_namespace} \
  --from-literal=JMS_USERNAME=${si_jmsuser} \
  --from-literal=JMS_PASSWORD=${si_jmspassword} 


OCPDOMAIN=$(oc get -n openshift-ingress-operator ingresscontroller default -o jsonpath='{.status.domain}')

rm -rf ${si_helmchart}
helm repo add ibm-helm https://raw.githubusercontent.com/IBM/charts/master/repo/ibm-helm --force-update
helm pull --untar ibm-helm/ibm-b2bi-prod --version 3.0.3 --untardir ${my_workdir}

cp ${fullpath}/../roles/sb2bi_deploy/files/dynamicclasspath.cfg.in ${si_helmchart}/config/

cd ${my_workdir}
rm -rf ibm-b2bi-prod/LICENSE*

echo "helm install s0 ibm-b2bi-prod -f ${fullpath}/values-6202.yaml -n ${si_namespace} --timeout 1h"
helm install s0 ibm-b2bi-prod -f ${fullpath}/values-6202.yaml -n ${si_namespace} --timeout 1h

exit

helm install s0 ibm-b2bi-prod -f /Users/vbudi/VBDData/programs/ibm-sterling-automation/scripts/values-6202.yaml  -n ${si_namespace} --timeout 1h

