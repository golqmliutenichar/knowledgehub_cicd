#!/bin/bash
# ============================================================
# Knowledge Hub - Phase 2 Deployment
# VPN Connection + MySQL Database
# ============================================================

set -e

SUBSCRIPTION="bcbf7dab-81c3-4a1c-9f22-47e90d2ea447"
LOCATION="swedencentral"
RG="KnowledgeHub-RG"
BICEP_DIR="./Bicep"

az account set --subscription $SUBSCRIPTION

# ── Step 1: Deploy VPN Connection ─────────────────────────
echo ">>> Getting VPN Gateway and Local Gateway IDs..."
VPN_GW_ID=$(az network vnet-gateway show \
  --resource-group $RG \
  --name KH-VPN-Gateway \
  --query id --output tsv)

LOCAL_GW_ID=$(az network local-gateway show \
  --resource-group $RG \
  --name KH-Local-Gateway \
  --query id --output tsv)

echo ">>> Enter VPN shared key (use same key in pfSense):"
read -s SHARED_KEY

echo ">>> Deploying VPN Connection..."
az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/VPN/VPNCon_Template.bicep \
  --name "Deploy-VPNConnection" \
  --parameters \
    vpnGatewayId=$VPN_GW_ID \
    localGatewayId=$LOCAL_GW_ID \
    sharedKey=$SHARED_KEY

# ── Step 2: Deploy MySQL Flexible Server ──────────────────
echo ">>> Deploying MySQL Flexible Server..."
echo ">>> Enter MySQL admin password:"
read -s MYSQL_PASSWORD

az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/Database/MySQLFlexibleServer_Template.bicep \
  --name "Deploy-MySQL" \
  --parameters \
    administratorLoginPassword=$MYSQL_PASSWORD

# ── Step 3: Configure Private Endpoint for MySQL ──────────
echo ">>> Getting MySQL Server ID..."
MYSQL_ID=$(az mysql flexible-server show \
  --resource-group $RG \
  --name kh-monitoring-db \
  --query id --output tsv)

SPOKE_VNET_ID=$(az network vnet show \
  --resource-group $RG \
  --name KH-Spoke-Vnet \
  --query id --output tsv)

PE_SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RG \
  --vnet-name KH-Spoke-Vnet \
  --name KH-PrivateEndpoint-Subnet \
  --query id --output tsv)

echo ">>> Creating Private Endpoint for MySQL..."
az network private-endpoint create \
  --resource-group $RG \
  --name KH-MySQL-PrivateEndpoint \
  --location $LOCATION \
  --vnet-name KH-Spoke-Vnet \
  --subnet KH-PrivateEndpoint-Subnet \
  --private-connection-resource-id $MYSQL_ID \
  --group-id mysqlServer \
  --connection-name KH-MySQL-PrivateConnection \
  --tags Project=KnowledgeHub Service=Database ManagedBy=IaC

# ── Step 4: Private DNS Zone for MySQL ────────────────────
echo ">>> Creating Private DNS Zone for MySQL..."
az network private-dns zone create \
  --resource-group $RG \
  --name "privatelink.mysql.database.azure.com"

az network private-dns link vnet create \
  --resource-group $RG \
  --zone-name "privatelink.mysql.database.azure.com" \
  --name KH-MySQL-DNS-Link \
  --virtual-network KH-Spoke-Vnet \
  --registration-enabled false

az network private-dns link vnet create \
  --resource-group $RG \
  --zone-name "privatelink.mysql.database.azure.com" \
  --name KH-MySQL-DNS-Link-Hub \
  --virtual-network KH-Hub-Vnet \
  --registration-enabled false

# Create DNS record for private endpoint
PE_NIC_ID=$(az network private-endpoint show \
  --resource-group $RG \
  --name KH-MySQL-PrivateEndpoint \
  --query 'networkInterfaces[0].id' --output tsv)

PE_IP=$(az network nic show \
  --ids $PE_NIC_ID \
  --query 'ipConfigurations[0].privateIPAddress' --output tsv)

az network private-dns record-set a add-record \
  --resource-group $RG \
  --zone-name "privatelink.mysql.database.azure.com" \
  --record-set-name "kh-monitoring-db" \
  --ipv4-address $PE_IP

echo ""
echo "============================================================"
echo "Phase 2 Deployment Complete!"
echo "MySQL Private Endpoint IP: $PE_IP"
echo "MySQL hostname: kh-monitoring-db.privatelink.mysql.database.azure.com"
echo ""
echo "Next: Run deploy_phase3.sh to deploy Flask API on App Service"
echo "============================================================"
