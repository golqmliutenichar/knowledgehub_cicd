#!/bin/bash
# ============================================================
# Knowledge Hub - Azure Infrastructure Deployment Script
# Subscription: bcbf7dab-81c3-4a1c-9f22-47e90d2ea447
# Location: swedencentral
# ============================================================

set -e  # Exit on any error

# ── Variables ──────────────────────────────────────────────
SUBSCRIPTION="bcbf7dab-81c3-4a1c-9f22-47e90d2ea447"
LOCATION="swedencentral"
RG="KnowledgeHub-RG"
BICEP_DIR="./Bicep"

# ── Login & Set Subscription ───────────────────────────────
echo ">>> Setting subscription..."
az account set --subscription $SUBSCRIPTION

# ── Resource Group ─────────────────────────────────────────
echo ">>> Creating resource group: $RG"
az group create \
  --name $RG \
  --location $LOCATION \
  --tags Project=KnowledgeHub Environment=Production ManagedBy=IaC

# ── Step 1: Deploy Hub VNet ────────────────────────────────
echo ">>> Deploying Hub VNet..."
az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/Vnets/HubVnet_Template.bicep \
  --name "Deploy-HubVnet"

# ── Step 2: Deploy Spoke VNet ──────────────────────────────
echo ">>> Deploying Spoke VNet..."
az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/Vnets/SpokeVnet_Template.bicep \
  --name "Deploy-SpokeVnet"

# ── Step 3: Get VNet IDs for peering ──────────────────────
echo ">>> Getting VNet IDs..."
HUB_VNET_ID=$(az network vnet show \
  --resource-group $RG \
  --name KH-Hub-Vnet \
  --query id --output tsv)

SPOKE_VNET_ID=$(az network vnet show \
  --resource-group $RG \
  --name KH-Spoke-Vnet \
  --query id --output tsv)

echo "Hub VNet ID: $HUB_VNET_ID"
echo "Spoke VNet ID: $SPOKE_VNET_ID"

# ── Step 4: Deploy VNet Peering ────────────────────────────
echo ">>> Deploying Hub-to-Spoke peering..."
az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/Vnets/VnetPeering_Template.bicep \
  --name "Deploy-HubToSpoke" \
  --parameters spokeVnetId=$SPOKE_VNET_ID

echo ">>> Deploying Spoke-to-Hub peering..."
az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/Vnets/VnetPeering2_Template.bicep \
  --name "Deploy-SpokeToHub" \
  --parameters hubVnetId=$HUB_VNET_ID

# ── Step 5: Deploy NSGs ────────────────────────────────────
echo ">>> Deploying NSGs..."
az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/NSGs/DatabaseSubnetNSG_Template.bicep \
  --name "Deploy-DatabaseNSG"

az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/NSGs/AppIntSubnetNSG_Template.bicep \
  --name "Deploy-AppIntNSG"

# ── Step 6: Deploy Route Table ─────────────────────────────
echo ">>> Deploying route table..."
az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/RouteTables/DefaultToFirewallRT_Template.bicep \
  --name "Deploy-RouteTable"

# ── Step 7: Deploy VPN Gateway Public IP ──────────────────
echo ">>> Deploying VPN Gateway Public IP..."
az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/VPN/VPNGatewayPublicIP_Template.bicep \
  --name "Deploy-VPNPublicIP"

# Get Gateway Subnet ID
GATEWAY_SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RG \
  --vnet-name KH-Hub-Vnet \
  --name GatewaySubnet \
  --query id --output tsv)

# Get Public IP ID
VPN_PUBLIC_IP_ID=$(az network public-ip show \
  --resource-group $RG \
  --name KH-VPNGateway-PublicIP \
  --query id --output tsv)

# ── Step 8: Deploy VPN Gateway (takes ~30 mins) ────────────
echo ">>> Deploying VPN Gateway (this takes ~30 minutes)..."
az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/VPN/VPNGateway_Template.bicep \
  --name "Deploy-VPNGateway" \
  --parameters \
    subnetId=$GATEWAY_SUBNET_ID \
    publicIpAddressId=$VPN_PUBLIC_IP_ID

# ── Step 9: Deploy Local Network Gateway ──────────────────
echo ">>> Deploying Local Network Gateway (pointing to pfSense)..."
az deployment group create \
  --resource-group $RG \
  --template-file $BICEP_DIR/VPN/LocalGateway_Template.bicep \
  --name "Deploy-LocalGateway"

echo ""
echo "============================================================"
echo "Phase 1 Deployment Complete!"
echo "Next steps:"
echo "  1. Get VPN Gateway public IP for pfSense configuration"
echo "  2. Run deploy_phase2.sh to deploy VPN connection and database"
echo "============================================================"

# Print VPN Gateway public IP
VPN_GW_IP=$(az network public-ip show \
  --resource-group $RG \
  --name KH-VPNGateway-PublicIP \
  --query ipAddress --output tsv)
echo "VPN Gateway Public IP: $VPN_GW_IP"
echo "(Configure this IP in pfSense as the Azure VPN peer)"
