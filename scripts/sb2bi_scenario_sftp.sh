#!/bin/bash

fullexec=$(readlink -f "${BASH_SOURCE[0]}")
fullpath=$(dirname ${fullexec})
if [ -z "$SI_INSTANCEID" ]; then
    echo "Error: SI_INSTANCEID is not defined or is empty."
    exit 1
fi

oc whoami &> /dev/null
return_code=$?

if [ $return_code -ne 0 ]; then
    echo "Must login to OpenShift ,oc whoami failed with return code $return_code: You are not authenticated or the server is unreachable."
    exit 1
fi 

si_instanceid="${SI_INSTANCEID}"
si_namespace="sterling-b2bi-${si_instanceid}-app"

si_container="asi" 
# Others
# -----------------------------------------------------------------------------
my_workdir=/tmp

asi_pod=$(oc get pod -n ${si_namespace} -l app.kubernetes.io/component=asi-server -o name | cut -d'/' -f2)

oc exec ${asi_pod} -n ${si_namespace} -- /ibm/b2bi/install/bin/securityContext.sh set DemoContext demoIdentity passw0rd 
oc exec ${asi_pod} -n ${si_namespace} -- mkdir /tmp/resourceImport

oc cp ${fullpath}/../roles/sb2bi_scenario_sftp/files/sfgSFTPDemoScenario.xml ${asi_pod}:/tmp/resourceImport/b2bi_resources.xml
oc cp ${fullpath}/../roles/sb2bi_scenario_sftp/files/PGP_DEMO_export.xml ${asi_pod}:/tmp/resourceImport/b2bi_resources2.xml
