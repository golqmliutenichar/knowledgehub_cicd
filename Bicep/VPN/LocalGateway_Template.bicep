param localNetworkGatewayName string = 'KH-Local-Gateway'
param location string = 'swedencentral'

// On-premises address spaces to route through the VPN
param addressPrefixes array = [
  '10.49.0.0/24'   // SrvVLAN
  '10.74.0.0/24'   // MgmtVLAN
  '10.123.0.0/24'  // GuestVLAN
  '10.146.0.0/24'  // DmzVLAN
]

// pfSense WAN IP address
param gatewayIpAddress string = '192.168.122.9'

resource localNetworkGateway 'Microsoft.Network/localNetworkGateways@2019-02-01' = {
  name: localNetworkGatewayName
  location: location
  tags: {
    Project: 'KnowledgeHub'
    Service: 'VPN'
    ManagedBy: 'IaC'
  }
  properties: {
    localNetworkAddressSpace: {
      addressPrefixes: addressPrefixes
    }
    gatewayIpAddress: gatewayIpAddress
  }
}
