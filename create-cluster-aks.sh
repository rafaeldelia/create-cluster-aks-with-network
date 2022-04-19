echo "----------------------------------------------------------------------------------"
echo "-- Criando Virtual Network e Grupo de Recursos --"
echo "----------------------------------------------------------------------------------"

#Listar Subscription
#az account list --output table

RESOURCE_GROUP_NAME=RG-Container-DSV
RESOURCE_GROUP_VNET=RG-Network
SUBSCRIPTION=e12XXXc8-9742-4ead-b7c6-dXXX9d3d3af3
LOCATION=centralus
CLUSTER_NAME=aksClusterDelia
VM_SIZE=standard_d2as_v5
QTD_NODES=1
VNET_NAME=vnet-delia
SUBNET_NAME=subnet-delia-k8s02
REGISTRY_NAME=registrydelia

#Setando a Subscription
az account set --subscription $SUBSCRIPTION

# Create a resource group AKS
az group create --name $RESOURCE_GROUP_NAME --location $LOCATION --subscription $SUBSCRIPTION

# Create a resource group VNET
az group create --name $RESOURCE_GROUP_VNET --location $LOCATION --subscription $SUBSCRIPTION

sleep 50

#create Virtual Network + Sub net
az network vnet create -g $RESOURCE_GROUP_VNET -n $VNET_NAME --address-prefix 10.0.0.0/16 \
    --subnet-name subnet-producao --subnet-prefix 10.0.0.0/24

sleep 20

# create once subnet
az network vnet subnet create -n $SUBNET_NAME --vnet-name $VNET_NAME -g $RESOURCE_GROUP_VNET --address-prefixes 10.0.1.0/24

sleep 25

# Create a service principal and read in the application ID
SP=$(az ad sp create-for-rbac --skip-assignment --output json)
SP_ID=$(echo $SP | jq -r .appId)
SP_PASSWORD=$(echo $SP | jq -r .password)

# Wait 15 seconds to make sure that service principal has propagated
echo "Waiting for service principal to propagate..."
sleep 20

# Get the virtual network resource ID
VNET_ID=$(az network vnet show --resource-group $RESOURCE_GROUP_VNET --name $VNET_NAME --query id -o tsv)

# Get the virtual network subnet resource ID
SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP_VNET --vnet-name $VNET_NAME --name $SUBNET_NAME --query id -o tsv)

# Assign the service principal Contributor permissions to the virtual network resource
az role assignment create --assignee $SP_ID  --scope $VNET_ID --role "Network Contributor"

echo "----------------------------------------------------------------------------------"
echo "-- Criando cluster do AKS para as políticas de rede do Azure --"
echo "----------------------------------------------------------------------------------"
az aks create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $CLUSTER_NAME \
    --node-count $QTD_NODES \
    --generate-ssh-keys \
    --service-cidr 10.100.0.0/16 \
    --dns-service-ip 10.100.0.10 \
    --docker-bridge-address 172.17.0.1/16 \
    --vnet-subnet-id $SUBNET_ID \
    --service-principal $SP_ID \
    --client-secret $SP_PASSWORD \
    --network-plugin azure \
    --network-policy azure \
    --node-vm-size $VM_SIZE \
    --zones 1 2 3 \
    --max-pods 100 \
    --subscription $SUBSCRIPTION
    
sleep 30
 
#Retrieve Conection
az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name $CLUSTER_NAME  
    

echo "----------------------------------------------------------------------------------"
echo "-- Registry ACR na Azure --"
echo "----------------------------------------------------------------------------------"
az acr create --location $LOCATION --name $REGISTRY_NAME --resource-group $RESOURCE_GROUP_NAME  --sku basic  --subscription $SUBSCRIPTION
sleep 20

#Atachear Regitry to Cluster - relação de confianca
az aks update -n $CLUSTER_NAME -g $RESOURCE_GROUP_NAME  --attach-acr $REGISTRY_NAME

#URL do Registry
URL_ACR=$(az acr show --name $REGISTRY_NAME  --resource-group $RESOURCE_GROUP_NAME  | jq -r .loginServer)


echo "----------------------------------------------------------------------------------"
echo "-- Resumo do Setup --"
echo "----------------------------------------------------------------------------------"
echo "Nos do Cluster:" 
kubectl get nodes -o custom-columns=NAME:'{.metadata.name}',REGION:'{.metadata.labels.topology\.kubernetes\.io/region}',ZONE:'{metadata.labels.topology\.kubernetes\.io/zone}'

#Status Resource Group
STATUS_RG=$(az group show --resource-group $RESOURCE_GROUP_NAME | jq -r .properties.provisioningState)
echo " Status Resouce Group: $STATUS_RG"

#Status Network
STATUS_VNET=$(az network vnet show --resource-group $RESOURCE_GROUP_VNET --name $VNET_NAME | jq -r .provisioningState)
echo " Status Vnet: $STATUS_VNET"

#Status Cluster
STATUS_AKS=$(az aks show --name $CLUSTER_NAME --resource-group $RESOURCE_GROUP_NAME  | jq -r .provisioningState)
echo " Status Cluster AKS: $STATUS_AKS"

#Status Registry
STATUS_ACR=$(az acr show --name $REGISTRY_NAME  --resource-group $RESOURCE_GROUP_NAME  | jq -r .provisioningState)
echo " Status Registry ACR: $STATUS_ACR"
echo " URL Registry: $URL_ACR"
