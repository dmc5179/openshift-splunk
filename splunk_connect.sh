#!/bin/bash
# From blog post here:
#
# https://blog.openshift.com/splunk-connect-for-openshift-logging-part/
#
# When you go to splunk search page use
# index="ocp_logging"

export NAMESPACE=splunk-connect

# Create the project
oc adm new-project ${NAMESPACE} --node-selector=""
oc project ${NAMESPACE}
oc adm policy add-scc-to-user anyuid -z default

# rbac-config defaults to using the kube-system namespace so we have to use sed first
wget  https://gitlab.com/charts/gitlab/raw/master/doc/installation/examples/rbac-config.yaml
sed -i "s/kube-system/${NAMESPACE}/g" ./rbac-config.yaml
oc create -f ./rbac-config.yaml

########################
# Install helm in a custom config


# Download and unpack help
#mkdir helm
#cd helm
wget https://storage.googleapis.com/kubernetes-helm/helm-v2.14.1-linux-amd64.tar.gz
tar -xzf helm-v2.14.1-linux-amd64.tar.gz
pushd linux-amd64

./helm init --override 'spec.template.spec.containers[0].command'='{/tiller,--storage=secret,--listen=localhost:44134}' --service-account=tiller --tiller-namespace=${NAMESPACE}

popd

##########################################
# Download splunk connect helm chart

wget https://github.com/splunk/splunk-connect-for-kubernetes/releases/download/1.1.0/splunk-kubernetes-logging-1.1.0.tgz
tar -xzf splunk-kubernetes-logging-1.1.0.tgz
#rm -f splunk-kubernetes-logging-1.1.0.tgz
#cd splunk-kubernetes-logging

#######################
# Splunk OCP logging

# Create service account for logging
oc create sa splunk-kubernetes-logging

# Assign privileged permission
oc adm policy add-scc-to-user privileged -z splunk-kubernetes-logging

# Install Helm package
#./linux-amd64/helm install --tiller-namespace=${NAMESPACE} --name splunk-kubernetes-logging -f logging-value.yml splunk-kubernetes-logging-1.1.0.tgz
./linux-amd64/helm install --tiller-namespace=${NAMESPACE} --name splunk-kubernetes-logging -f values.yaml ./splunk-kubernetes-logging

# There probably needs to be a sleep in here since the patch below is operating on things
# being created by the helm chart above
sleep 30

# Patch to add privileged=true securityContext and service account splunk-kubernetes-logging.
# There is a typo in the blog post this comes from
oc patch ds splunk-kubernetes-logging -p '{
         "spec":{
            "template":{
               "spec":{
                  "serviceAccountName": "splunk-kubernetes-logging",
                  "containers":[
                     {
                        "name":"splunk-fluentd-k8s-logs",
                        "securityContext":{
                           "privileged":true
                        }
                     }
                  ]
               }
            }
         }
      }'


# Delete the pods to apply the latest patch.
oc delete pods -lapp=splunk-kubernetes-logging  


##########################################################################################
# OCP Splunk Web Console Extension

oc project openshift-web-console
oc new-app https://github.com/openlab-red/ext-openshift-web-console --name=ext -lapp=ext --context-dir=/app
oc patch dc ext -p '{
                 "spec": {
                     "template": {
                         "spec": {
                             "nodeSelector": {
                                 "node-role.kubernetes.io/master": "true"
                             }
                         }
                     }
                 }
             }'
oc scale --replicas=3 dc/ext
oc create route edge --service=ext

#############################
# Manual Step!!!!

# Update the extensions section of the webconsole-config configmap based on your settings.
# extensions:
#      properties:
#        splunkURL: "http://ec2-54-175-28-109.compute-1.amazonaws.com:8000"
#        splunkQueryPrefix: "/en-US/app/search/search?q=search%20"
#        splunkApplicationIndex: 'ocp_logging'
#        splunkSystemIndex: 'ocp_system'
#        splunkSystemNamespacePattern: '^(openshift|kube|splunk|istio|default)\-?.*'


# Rollout the openshift-web-console deployment.
oc delete pod -lapp=openshift-web-console




