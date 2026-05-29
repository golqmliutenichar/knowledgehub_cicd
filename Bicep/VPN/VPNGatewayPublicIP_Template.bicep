resource vpnGatewayPublicIP 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: 'KH-VPNGateway-PublicIP'
  location: 'swedencentral'
  tags: {
    Project: 'KnowledgeHub'
    Service: 'VPN'
    ManagedBy: 'IaC'
  }
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}
