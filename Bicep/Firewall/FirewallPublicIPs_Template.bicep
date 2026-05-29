resource firewallPublicIP 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: 'KH-Firewall-PublicIP'
  location: 'swedencentral'
  tags: {
    Project: 'KnowledgeHub'
    Service: 'Firewall'
    ManagedBy: 'IaC'
  }
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource firewallManagementPublicIP 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: 'KH-Firewall-ManagementPublicIP'
  location: 'swedencentral'
  tags: {
    Project: 'KnowledgeHub'
    Service: 'Firewall'
    ManagedBy: 'IaC'
  }
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}
