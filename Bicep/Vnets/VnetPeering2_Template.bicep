param hubVnetName string = 'KH-Hub-Vnet'
param spokeVnetName string = 'KH-Spoke-Vnet'
param hubVnetId string

// Spoke to Hub peering
resource spokeToHubPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = {
  name: '${spokeVnetName}/Spoke-to-Hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: true
    remoteVirtualNetwork: {
      id: hubVnetId
    }
  }
}
