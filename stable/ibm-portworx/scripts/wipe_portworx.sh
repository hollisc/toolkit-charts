#!/usr/bin/env bash

# Docs for cleaning up Portworx installation at: https://cloud.ibm.com/docs/containers?topic=containers-portworx#portworx_cleanup
# Additional utilities for cleaning up Portworx installation available at https://github.com/IBM/ibmcloud-storage-utilities/blob/master/px-utils/px_cleanup/px-wipe.sh

if [[ -z "${NAMESPACE}" ]] || [[ -z "${SERVICE_NAME}" ]]; then
  echo "NAMESPACE and SERVICE_NAME must be provided as environment variables" >&2
  exit 1
fi

if ! command -v jq 1> /dev/null 2> /dev/null; then
  echo "jq cli not found" >&2
  exit 1
fi

if ! command -v helm 1> /dev/null 2> /dev/null; then
  echo "helm cli not found" >&2
  exit 1
fi

if ! command -v kubectl 1> /dev/null 2> /dev/null; then
  echo "kubectl cli not found" >&2
  exit 1
fi

if ! command -v oc 1> /dev/null 2> /dev/null; then
  echo "oc cli not found" >&2
  exit 1
fi

echo "Sleeping for 30 seconds to let things settle"
sleep 30

if oc get services.ibmcloud "${SERVICE_NAME}" -n "${NAMESPACE}" 1> /dev/null 2> /dev/null; then
  echo "IBM Cloud Portworx service found: ${NAMESPACE}/${SERVICE_NAME}"
  oc get services.ibmcloud "${SERVICE_NAME}" -n "${NAMESPACE}" -o yaml
  SERVICE_STATE=$(oc get services.ibmcloud "${SERVICE_NAME}" -n "${NAMESPACE}" -o json | jq '.status.state // empty')

  echo "Current state of ${NAMESPACE}/${SERVICE_NAME}: ${SERVICE_STATE}"
  if [[ -z "${SERVICE_STATE}" ]] || [[ "${SERVICE_STATE}" =~ [Oo]nline ]] || [[ "${SERVICE_STATE}" == "in progress" ]] || [[ "${SERVICE_STATE}" == "provisioning" ]]; then
    echo "The ${NAMESPACE}/${SERVICE_NAME} IBM Cloud service instance exists. This is a PostSync create event."
    exit 0
  fi
else
  echo "IBM Cloud Portworx service not found: ${NAMESPACE}/${SERVICE_NAME}. Cleaning up..."
  oc get services.ibmcloud -n "${NAMESPACE}"
fi

echo "Wiping Portworx from cluster"

curl -fSsL https://raw.githubusercontent.com/IBM/ibmcloud-storage-utilities/master/px-utils/px_cleanup/px-wipe.sh | bash -s -- --talismanimage icr.io/ext/portworx/talisman --talismantag 1.1.0 --wiperimage icr.io/ext/portworx/px-node-wiper --wipertag 2.5.0 --force

echo "Removing the portworx helm deployment from the cluster"

helm_releases=$(helm ls -A --output json)

helm_release=$(echo "${helm_releases}" | jq -r '.[] | select(.name=="portworx") | .name // empty')
helm_namespace=$(echo "${helm_releases}" | jq -r '.[] | select(.name=="portworx") | .namespace // empty')

if [[ -z "${helm_release}" ]]; then
  echo "Unable to find helm release for portworx.  Ensure your helm client is at version 3 and has access to the cluster.";
else
  if ! helm uninstall "${helm_release}" -n "${helm_namespace}"; then
    echo "error removing the helm release"
    #exit 1;
  fi
fi

echo "removing all portworx storage classes"
kubectl get sc -A | grep portworx | awk '{ print $1 }' | while read in; do
  kubectl delete sc "$in"
done

echo "removing portworx artifacts"
kubectl delete serviceaccount -n kube-system portworx-hook --ignore-not-found=true
kubectl delete clusterrole portworx-hook --ignore-not-found=true
kubectl delete clusterrolebinding portworx-hook --ignore-not-found=true

kubectl delete service portworx-service -n kube-system --ignore-not-found=true
kubectl delete service portworx-api -n kube-system --ignore-not-found=true

kubectl delete serviceaccount -n kube-system portworx-hook --ignore-not-found=true 
kubectl delete clusterrole portworx-hook --ignore-not-found=true
kubectl delete clusterrolebinding portworx-hook --ignore-not-found=true

kubectl delete job -n kube-system talisman --ignore-not-found=true
kubectl delete serviceaccount -n kube-system talisman-account --ignore-not-found=true 
kubectl delete clusterrolebinding talisman-role-binding --ignore-not-found=true 
kubectl delete crd volumeplacementstrategies.portworx.io --ignore-not-found=true
kubectl delete configmap -n kube-system portworx-pvc-controller --ignore-not-found=true

kubectl delete daemonset -n kube-system portworx --ignore-not-found=true
kubectl delete daemonset -n kube-system portworx-api --ignore-not-found=true
kubectl delete deployment -n kube-system portworx-pvc-controller --ignore-not-found=true

kubectl delete job -n kube-system px-hook-etcd-preinstall --ignore-not-found=true
kubectl delete job -n kube-system px-hook-predelete-nodelabel --ignore-not-found=true

kubectl delete secret -n default sh.helm.release.v1.portworx.v1 --ignore-not-found=true

# use the following command to verify all portworks resources are gone.  If you see a result here, it didn't work
# kubectl get all -A | grep portworx
