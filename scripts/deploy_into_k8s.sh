set -e 
. ./params.sh
AAG_ID=$(az network application-gateway show -n $AAG_NAME -g $NET_RG_NAME --query id -o tsv)
AAG_SUBID=$(echo $AAG_ID | cut -d'/' -f 3)
AKS_API=$(az aks show -n $CLUSTER_NAME -g $RG_NAME --query fqdn -o tsv)
AAG_RGID=$(az group show -n $NET_RG_NAME --query id -o tsv)
AKS_MC_RG="MC_${RG_NAME}_${CLUSTER_NAME}_${LOCATION}"
SERVICE_PRINCIPAL=$(az aks show -n $CLUSTER_NAME -g $RG_NAME --query servicePrincipalProfile.clientId -o tsv)
AKS_MC_RG_ID=$(az group show -n $AKS_MC_RG --query id -o tsv)

## Create MAnaged Identity into AKS MC Resource Group
echo "creating MSI $MSI_NAME"
az identity create \
--resource-group $AKS_MC_RG \
--name $MSI_NAME

MSI_C_ID=$(az identity show -n $MSI_NAME -g $AKS_MC_RG --query clientId -o tsv)
MSI_R_ID=$(az identity show -n $MSI_NAME -g $AKS_MC_RG --query id -o tsv)

## Give the identity Contributor access to you App Gateway
echo "Granting managed identity Contributor access to App Gateway"
az role assignment create \
    --role Contributor \
    --assignee $MSI_C_ID \
    --scope $AAG_ID

## Give the identity Reader access to the App Gateway resource group
echo ""
echo "Granting managed identity Reader access to the App Gateway resource group"
az role assignment create \
    --role Reader \
    --assignee $MSI_C_ID \
    --scope $AAG_RGID

## Deploy the Managed Idenity Controller and Node Managed Identity
echo ""
echo "Deploying the Managed Idenity Controller and Node Managed Identity"
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/v1.5.5/deploy/infra/deployment-rbac.yaml

## Add the AGIC Helm repository
echo ""
echo "Adding the AGIC Helm repository"
helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update

## Deploy application gateway ingress controller
echo ""
echo "Deploying application gateway ingress controller"

helm upgrade -i ingress-agic application-gateway-kubernetes-ingress/ingress-azure \
     --version 1.2.0-rc1 \
     --namespace default \
     --debug \
     --set appgw.name=$AAG_NAME \
     --set appgw.resourceGroup=$NET_RG_NAME \
     --set appgw.subscriptionId=$AAG_SUBID \
     --set appgw.shared=false \
     --set appgw.usePrivateIP=false \
     --set armAuth.type=aadPodIdentity \
     --set armAuth.identityResourceID=$MSI_R_ID \
     --set armAuth.identityClientID=$MSI_C_ID \
     --set rbac.enabled=true \
     --set verbosityLevel=3 \
     --set kubernetes.watchNamespace=default \
     --set aksClusterConfiguration.apiServerAddress=$AKS_API

