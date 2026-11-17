// Hub <-> spoke peering. The spoke uses the hub's VPN gateway when it exists,
// so on-premises networks can reach the spoke through the tunnel.

param hubVnetName string
param spokeVnetName string
param hubVnetId string
param spokeVnetId string

@description('true only while the VPN gateway exists (Azure refuses it otherwise).')
param useRemoteGateway bool

resource hub 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: hubVnetName
}

resource spoke 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: spokeVnetName
}

resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: hub
  name: 'Hub-to-Spoke'
  properties: {
    remoteVirtualNetwork: { id: spokeVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: useRemoteGateway
    useRemoteGateways: false
  }
}

resource spokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: spoke
  name: 'Spoke-to-Hub'
  properties: {
    remoteVirtualNetwork: { id: hubVnetId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: useRemoteGateway
  }
  dependsOn: [ hubToSpoke ]
}
