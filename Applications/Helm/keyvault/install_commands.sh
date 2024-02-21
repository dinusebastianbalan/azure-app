if ! kubectl get pods -o json | jq -r ".items[].metadata.name" | grep csi-secrets-store-provider;then
  helm repo add csi-secrets-store-provider-azure https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts
  helm repo update
  helm install csi-secrets-store-provider-azure/csi-secrets-store-provider-azure --generate-name
  kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/master/deploy/infra/deployment-rbac.yaml
fi
