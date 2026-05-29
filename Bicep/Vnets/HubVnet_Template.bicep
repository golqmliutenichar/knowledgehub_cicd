resource HubVnet 'Microsoft.Network/virtualNetworks@2019-09-01' = {
  name: 'KH-Hub-Vnet'
  location: 'swedencentral'
  tags: {
    Vnet: 'Hub'
    Project: 'KnowledgeHub'
    Environment: 'Production'
    ManagedBy: 'IaC'
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
    dhcpOptions: {
      dnsServers: []
    }
    subnets: [
      {
        properties: {
          addressPrefix: '10.10.0.0/27'
        }
        name: 'GatewaySubnet'
      }
      {
        properties: {
          addressPrefix: '10.10.0.128/26'
        }
        name: 'AzureBastionSubnet'
      }
      {
        properties: {
          addressPrefix: '10.10.0.64/26'
        }
        name: 'AzureFirewallSubnet'
      }
      {
        properties: {
          addressPrefix: '10.10.1.0/24'
        }
        name: 'DNS-Forwarder-Subnet'
      }
      {
        properties: {
          addressPrefix: '10.10.2.0/24'
        }
        name: 'Central-Database-Subnet'
      }
    ]
  }
}
