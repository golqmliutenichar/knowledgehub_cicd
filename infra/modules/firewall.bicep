// Azure Firewall Basic in the hub. Inspects hybrid traffic (on-prem <-> spoke).
// Basic needs a firewall policy (no classic rules) and a management subnet + IP.
// Expensive while it exists: remove it with the teardown pipeline when not testing.

param location string
param tags object
param firewallSubnetId string
param firewallMgmtSubnetId string
param onPremPrefixes array

var appsSubnetPrefix = '10.20.4.0/23'
var peSubnetPrefix = '10.20.3.0/24'

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'KH-Firewall-PublicIP'
  location: location
  tags: union(tags, { Service: 'Firewall' })
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource mgmtPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'KH-Firewall-ManagementPublicIP'
  location: location
  tags: union(tags, { Service: 'Firewall' })
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource policy 'Microsoft.Network/firewallPolicies@2024-05-01' = {
  name: 'KH-Firewall-Policy'
  location: location
  tags: union(tags, { Service: 'Firewall' })
  properties: {
    sku: { tier: 'Basic' }
    threatIntelMode: 'Alert'
  }
}

resource rules 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-05-01' = {
  parent: policy
  name: 'KH-Hybrid-Rules'
  properties: {
    priority: 100
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'Allow-OnPrem-to-Cloud'
        priority: 100
        action: { type: 'Allow' }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'OnPrem-to-API'
            ipProtocols: [ 'TCP' ]
            sourceAddresses: onPremPrefixes
            destinationAddresses: [ appsSubnetPrefix ]
            destinationPorts: [ '80', '443' ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'OnPrem-Servers-to-Database'
            ipProtocols: [ 'TCP' ]
            sourceAddresses: [ onPremPrefixes[0] ]
            destinationAddresses: [ peSubnetPrefix ]
            destinationPorts: [ '3306' ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'OnPrem-ICMP-for-Testing'
            ipProtocols: [ 'ICMP' ]
            sourceAddresses: onPremPrefixes
            destinationAddresses: [ '10.20.0.0/16' ]
            destinationPorts: [ '*' ]
          }
        ]
      }
    ]
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-05-01' = {
  name: 'KH-Hub-Firewall'
  location: location
  tags: union(tags, { Service: 'Firewall' })
  properties: {
    sku: { name: 'AZFW_VNet', tier: 'Basic' }
    firewallPolicy: { id: policy.id }
    ipConfigurations: [
      {
        name: 'KH-Firewall-IpConfig'
        properties: {
          subnet: { id: firewallSubnetId }
          publicIPAddress: { id: pip.id }
        }
      }
    ]
    managementIpConfiguration: {
      name: 'KH-Firewall-MgmtIpConfig'
      properties: {
        subnet: { id: firewallMgmtSubnetId }
        publicIPAddress: { id: mgmtPip.id }
      }
    }
  }
  dependsOn: [ rules ]
}

output privateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
