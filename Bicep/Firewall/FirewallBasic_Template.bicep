param hubVnetId string = '/subscriptions/bcbf7dab-81c3-4a1c-9f22-47e90d2ea447/resourceGroups/KnowledgeHub-RG/providers/Microsoft.Network/virtualNetworks/KH-Hub-Vnet'
param firewallPublicIPId string
param firewallManagementPublicIPId string
param firewallPolicyId string

resource azureFirewall 'Microsoft.Network/azureFirewalls@2024-07-01' = {
  name: 'KH-Hub-Firewall'
  location: 'swedencentral'
  tags: {
    Project: 'KnowledgeHub'
    Vnet: 'Hub'
    Service: 'Firewall'
    ManagedBy: 'IaC'
  }
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Basic'
    }
    threatIntelMode: 'Alert'
    additionalProperties: {}
    managementIpConfiguration: {
      name: 'KH-Firewall-ManagementIP'
      properties: {
        publicIPAddress: {
          id: firewallManagementPublicIPId
        }
        subnet: {
          id: '${hubVnetId}/subnets/AzureFirewallManagementSubnet'
        }
      }
    }
    ipConfigurations: [
      {
        name: 'KH-Firewall-PublicIP'
        properties: {
          publicIPAddress: {
            id: firewallPublicIPId
          }
          subnet: {
            id: '${hubVnetId}/subnets/AzureFirewallSubnet'
          }
        }
      }
    ]
    networkRuleCollections: [
      {
        name: 'Allow-OnPrem-to-Spoke'
        properties: {
          priority: 100
          action: { type: 'Allow' }
          rules: [
            {
              name: 'OnPrem-to-API'
              protocols: [ 'TCP' ]
              sourceAddresses: [ '10.49.0.0/24', '10.74.0.0/24' ]
              destinationAddresses: [ '10.20.1.0/24' ]
              destinationPorts: [ '443' ]
            }
            {
              name: 'OnPrem-to-Database'
              protocols: [ 'TCP' ]
              sourceAddresses: [ '10.49.0.0/24' ]
              destinationAddresses: [ '10.10.2.0/24' ]
              destinationPorts: [ '3306' ]
            }
          ]
        }
      }
      {
        name: 'Deny-Guest-to-Cloud'
        properties: {
          priority: 200
          action: { type: 'Deny' }
          rules: [
            {
              name: 'Block-Guest-VLAN'
              protocols: [ 'Any' ]
              sourceAddresses: [ '10.123.0.0/24' ]
              destinationAddresses: [ '10.10.0.0/16', '10.20.0.0/16' ]
              destinationPorts: [ '*' ]
            }
          ]
        }
      }
    ]
    applicationRuleCollections: [
      {
        name: 'Allow-Azure-Updates'
        properties: {
          priority: 100
          action: { type: 'Allow' }
          rules: [
            {
              name: 'Allow-WindowsUpdate'
              protocols: [
                { protocolType: 'Https', port: 443 }
              ]
              targetFqdns: [
                '*.windowsupdate.microsoft.com'
                '*.update.microsoft.com'
                '*.azure.com'
              ]
              sourceAddresses: [ '10.10.0.0/16', '10.20.0.0/16' ]
            }
          ]
        }
      }
    ]
    natRuleCollections: []
    firewallPolicy: {
      id: firewallPolicyId
    }
  }
}
