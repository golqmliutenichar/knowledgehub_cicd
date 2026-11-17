// Hub-spoke network: VNets, subnets, NSGs and (when the firewall exists) route tables.

param location string
param tags object

@description('On-premises networks that may use cloud services (CS1: SRV and MGMT).')
param onPremPrefixes array

@description('true = send hybrid traffic through the Azure Firewall (route tables are attached).')
param routeViaFirewall bool

@description('Private IP of the Azure Firewall (first usable address of AzureFirewallSubnet).')
param firewallPrivateIp string = '10.10.0.68'

var hubPrefix = '10.10.0.0/16'
var spokePrefix = '10.20.0.0/16'
var peSubnetPrefix = '10.20.3.0/24'
var appsSubnetPrefix = '10.20.4.0/23'

// ── NSGs ────────────────────────────────────────────────────────────────

resource peNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'KH-PrivateEndpoint-NSG'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-MySQL-From-ContainerApps'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: appsSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: peSubnetPrefix
          destinationPortRange: '3306'
          description: 'The API reaches the database'
        }
      }
      {
        name: 'Allow-MySQL-From-OnPrem-Servers'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: onPremPrefixes[0]
          sourcePortRange: '*'
          destinationAddressPrefix: peSubnetPrefix
          destinationPortRange: '3306'
          description: 'Admin and validation from the on-prem server zone'
        }
      }
      {
        name: 'Deny-All-Other-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource appsNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'KH-ContainerApps-NSG'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-From-OnPrem'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefixes: onPremPrefixes
          sourcePortRange: '*'
          destinationAddressPrefix: appsSubnetPrefix
          destinationPortRanges: [ '80', '443' ]
          description: 'Monitoring script and staff reach the API over the VPN'
        }
      }
      {
        name: 'Allow-AzureLoadBalancer'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Health probes of the Container Apps environment'
        }
      }
      {
        name: 'Allow-Inside-Environment'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: appsSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: appsSubnetPrefix
          destinationPortRange: '*'
        }
      }
      {
        name: 'Deny-Internet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'The API is never reachable from the internet'
        }
      }
    ]
  }
}

// ── Route tables (only while the firewall exists) ──────────────────────

resource spokeRt 'Microsoft.Network/routeTables@2024-05-01' = if (routeViaFirewall) {
  name: 'KH-Spoke-RouteTable'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [for (prefix, i) in onPremPrefixes: {
      name: 'OnPrem-${i}-via-Firewall'
      properties: {
        addressPrefix: prefix
        nextHopType: 'VirtualAppliance'
        nextHopIpAddress: firewallPrivateIp
      }
    }]
  }
}

resource gatewayRt 'Microsoft.Network/routeTables@2024-05-01' = if (routeViaFirewall) {
  name: 'KH-Gateway-RouteTable'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'Spoke-via-Firewall'
        properties: {
          addressPrefix: spokePrefix
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

// ── VNets ───────────────────────────────────────────────────────────────

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'KH-Hub-Vnet'
  location: location
  tags: union(tags, { Vnet: 'Hub' })
  properties: {
    addressSpace: { addressPrefixes: [ hubPrefix ] }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '10.10.0.0/27'
          routeTable: routeViaFirewall ? { id: gatewayRt.id } : null
        }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: { addressPrefix: '10.10.0.64/26' }
      }
      {
        name: 'AzureFirewallManagementSubnet'
        properties: { addressPrefix: '10.10.0.128/26' }
      }
      {
        // Reserved for an Azure DNS Private Resolver inbound endpoint (future)
        name: 'DNS-Resolver-Subnet'
        properties: { addressPrefix: '10.10.1.0/28' }
      }
    ]
  }
}

resource spoke 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'KH-Spoke-Vnet'
  location: location
  tags: union(tags, { Vnet: 'Spoke' })
  properties: {
    addressSpace: { addressPrefixes: [ spokePrefix ] }
    subnets: [
      {
        name: 'KH-PrivateEndpoint-Subnet'
        properties: {
          addressPrefix: peSubnetPrefix
          networkSecurityGroup: { id: peNsg.id }
          routeTable: routeViaFirewall ? { id: spokeRt.id } : null
          // NSG and route table also apply to private endpoints
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'KH-ContainerApps-Subnet'
        properties: {
          addressPrefix: appsSubnetPrefix
          networkSecurityGroup: { id: appsNsg.id }
          routeTable: routeViaFirewall ? { id: spokeRt.id } : null
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: { serviceName: 'Microsoft.App/environments' }
            }
          ]
        }
      }
    ]
  }
}

output hubVnetId string = hub.id
output hubVnetName string = hub.name
output spokeVnetId string = spoke.id
output spokeVnetName string = spoke.name
output gatewaySubnetId string = hub.properties.subnets[0].id
output firewallSubnetId string = hub.properties.subnets[1].id
output firewallMgmtSubnetId string = hub.properties.subnets[2].id
output peSubnetId string = spoke.properties.subnets[0].id
output appsSubnetId string = spoke.properties.subnets[1].id
