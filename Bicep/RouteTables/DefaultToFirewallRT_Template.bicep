param firewallPrivateIP string = '10.10.0.68'

resource defaultRouteTable 'Microsoft.Network/routeTables@2021-02-01' = {
  name: 'KH-Default-RouteTable'
  location: 'swedencentral'
  tags: {
    Project: 'KnowledgeHub'
    ManagedBy: 'IaC'
  }
  properties: {
    routes: [
      {
        name: 'Default-To-Firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIP
        }
      }
      {
        name: 'OnPrem-SrvVLAN'
        properties: {
          addressPrefix: '10.49.0.0/24'
          nextHopType: 'VirtualNetworkGateway'
        }
      }
      {
        name: 'OnPrem-MgmtVLAN'
        properties: {
          addressPrefix: '10.74.0.0/24'
          nextHopType: 'VirtualNetworkGateway'
        }
      }
    ]
    disableBgpRoutePropagation: false
  }
}
