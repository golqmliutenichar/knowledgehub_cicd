resource firewallPolicy 'Microsoft.Network/firewallPolicies@2021-02-01' = {
  name: 'KH-Firewall-Policy'
  location: 'swedencentral'
  tags: {
    Project: 'KnowledgeHub'
    Service: 'Firewall'
    ManagedBy: 'IaC'
  }
  properties: {
    sku: {
      tier: 'Basic'
    }
    threatIntelMode: 'Alert'
  }
}
