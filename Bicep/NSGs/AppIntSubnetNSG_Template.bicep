resource appIntNSG 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: 'KH-AppInt-NSG'
  location: 'swedencentral'
  tags: {
    Project: 'KnowledgeHub'
    Subnet: 'AppService'
    ManagedBy: 'IaC'
  }
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-From-OnPrem'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.49.0.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '10.20.1.0/24'
          destinationPortRange: '443'
          description: 'Allow HTTPS from on-prem SrvVLAN'
        }
      }
      {
        name: 'Allow-HTTPS-From-Mgmt'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.74.0.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '10.20.1.0/24'
          destinationPortRange: '443'
          description: 'Allow HTTPS from MgmtVLAN'
        }
      }
      {
        name: 'Deny-Public-Internet'
        properties: {
          priority: 200
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Block all public internet access to API'
        }
      }
    ]
  }
}
