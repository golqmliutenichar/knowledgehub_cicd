param name string = 'KH-VPN-Gateway'
param location string = 'swedencentral'

@allowed([
  'Vpn'
  'ExpressRoute'
])
param gatewayType string = 'Vpn'

// VpnGw1 is the minimum for route-based S2S VPN
param sku string = 'VpnGw1'
param vpnGatewayGeneration string = 'Generation1'

@allowed([
  'RouteBased'
  'PolicyBased'
])
param vpnType string = 'RouteBased'
param subnetId string
param publicIpAddressId string

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: name
  location: location
  tags: {
    Project: 'KnowledgeHub'
    Vnet: 'Hub'
    Service: 'VPN'
    ManagedBy: 'IaC'
  }
  properties: {
    gatewayType: gatewayType
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: publicIpAddressId
          }
        }
      }
    ]
    vpnType: vpnType
    vpnGatewayGeneration: vpnGatewayGeneration
    sku: {
      name: sku
      tier: sku
    }
  }
}
