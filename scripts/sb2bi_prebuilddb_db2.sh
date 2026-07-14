#!/bin/bash
if [ -z "$SI_INSTANCEID" ]; then
    echo "Error: SI_INSTANCEID is not defined or is empty."
    exit 1
fi
oc whoami &> /dev/null

# Capture the return code
return_code=$?

if [ $return_code -ne 0 ]; then
    echo "Must login to OpenShift ,oc whoami failed with return code $return_code: You are not authenticated or the server is unreachable."
    exit 1
fi 

si_instanceid=${SI_INSTANCEID}

curpath=$(dirname $0)
echo $curpath

si_prebuiltdb_file="$curpath/../roles/sb2bi_prebuiltdb_db2/files/b2bi6202.tar.gz"

db2_namespace="sterling-b2bi-${si_instanceid}-db2"

db2_instance_name="db2inst1"
db2_user="db2inst1"
db2_dbname="B2BI"
db2_container="mydb2"
db2_id="mydb2"
export db2_user db2_dbname db2_id db2_instance_name

# Others
# -----------------------------------------------------------------------------
my_workdir="/tmp"
export LC_CTYPE=C

db2_pod_name=$(oc get pods -n "${db2_namespace}" -l "app=${db2_id}" | grep -v NAME | awk '{print $1}' )

echo $db2_pod_name

# Copy files to the pod and execute them

oc cp $si_prebuiltdb_file $db2_pod_name:/tmp/b2bi6202.tar.gz -n $db2_namespace

rand_id=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c 5)
envsubst '$db2_user $db2_dbname $db2_id $db2_instance_name' < ${curpath}/createdb.sh.j2 > createdb-${rand_id}.sh
envsubst '$db2_user $db2_dbname $db2_id $db2_instance_name' < ${curpath}/restoredb.sh.j2 > restoredb-${rand_id}.sh
set -x

oc cp createdb-${rand_id}.sh $db2_pod_name:/tmp/createdb-${rand_id}.sh -n $db2_namespace
oc cp restoredb-${rand_id}.sh $db2_pod_name:/tmp/restoredb-${rand_id}.sh -n $db2_namespace

rm -f createdb-${rand_id}.sh
rm -f restoredb-${rand_id}.sh

cmdcrt="chmod a+x /tmp/*.sh; su - ${db2_user} -c /tmp/createdb-${rand_id}.sh"
cmdrst="chmod a+x /tmp/*.sh; su - ${db2_user} -c /tmp/restoredb-${rand_id}.sh"
oc exec -n "$db2_namespace" "$db2_pod_name" -- bash -c "${cmdcrt}"
sleep 60
oc exec -n "$db2_namespace" "$db2_pod_name" -- bash -c "${cmdrst}"
