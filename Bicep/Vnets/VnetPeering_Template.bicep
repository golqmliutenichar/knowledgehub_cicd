param hubVnetName string = 'KH-Hub-Vnet'
param spokeVnetName string = 'KH-Spoke-Vnet'
param spokeVnetId string

// Hub to Spoke peering
resource hubToSpokePeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-02-01' = {
  name: '${hubVnetName}/Hub-to-Spoke'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
  }
}
