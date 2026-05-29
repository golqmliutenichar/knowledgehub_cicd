resource SpokeVnet 'Microsoft.Network/virtualNetworks@2019-09-01' = {
  name: 'KH-Spoke-Vnet'
  location: 'swedencentral'
  tags: {
    Vnet: 'Spoke'
    Project: 'KnowledgeHub'
    Environment: 'Production'
    ManagedBy: 'IaC'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }
    dhcpOptions: {
      dnsServers: []
    }
    subnets: [
      {
        properties: {
          addressPrefix: '10.20.3.0/24'
        }
        name: 'KH-PrivateEndpoint-Subnet'
      }
      {
        properties: {
          addressPrefix: '10.20.1.0/24'
        }
        name: 'KH-AppService-Subnet'
      }
    ]
  }
}
