resource databaseNSG 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: 'KH-Database-NSG'
  location: 'swedencentral'
  tags: {
    Project: 'KnowledgeHub'
    Subnet: 'Database'
    ManagedBy: 'IaC'
  }
  properties: {
    securityRules: [
      {
        name: 'Allow-MySQL-From-Spoke'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.20.0.0/16'
          sourcePortRange: '*'
          destinationAddressPrefix: '10.10.2.0/24'
          destinationPortRange: '3306'
          description: 'Allow MySQL from Spoke VNet'
        }
      }
      {
        name: 'Allow-MySQL-From-OnPrem'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '10.49.0.0/24'
          sourcePortRange: '*'
          destinationAddressPrefix: '10.10.2.0/24'
          destinationPortRange: '3306'
          description: 'Allow MySQL from on-prem SrvVLAN'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny all other inbound traffic'
        }
      }
    ]
  }
}
