// Site-to-site VPN to pfSense (CS1). Route-based, IKEv2, static routes.
// Expensive while it exists: remove it with the teardown pipeline when not testing.

param location string
param tags object
param gatewaySubnetId string

@description('Public IP of the network where pfSense runs (your home/school router).')
param onPremPublicIp string

@description('On-premises networks reached through the tunnel.')
param onPremPrefixes array

@secure()
param sharedKey string

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'KH-VPNGateway-PublicIP'
  location: location
  tags: union(tags, { Service: 'VPN' })
  sku: { name: 'Standard', tier: 'Regional' }
  zones: [ '1', '2', '3' ] // AZ gateway SKUs need a zone-redundant IP
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource gateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
  name: 'KH-VPN-Gateway'
  location: location
  tags: union(tags, { Service: 'VPN' })
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation1'
    sku: { name: 'VpnGw1AZ', tier: 'VpnGw1AZ' }
    enableBgp: false
    activeActive: false
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: gatewaySubnetId }
          publicIPAddress: { id: pip.id }
        }
      }
    ]
  }
}

resource localGateway 'Microsoft.Network/localNetworkGateways@2024-05-01' = {
  name: 'KH-Local-Gateway'
  location: location
  tags: union(tags, { Service: 'VPN' })
  properties: {
    gatewayIpAddress: onPremPublicIp
    localNetworkAddressSpace: { addressPrefixes: onPremPrefixes }
  }
}

resource connection 'Microsoft.Network/connections@2024-05-01' = {
  name: 'KH-VPN-Connection'
  location: location
  tags: union(tags, { Service: 'VPN' })
  properties: {
    connectionType: 'IPsec'
    connectionProtocol: 'IKEv2'
    virtualNetworkGateway1: { id: gateway.id, properties: {} }
    localNetworkGateway2: { id: localGateway.id, properties: {} }
    sharedKey: sharedKey
    enableBgp: false
    usePolicyBasedTrafficSelectors: false
    ipsecPolicies: [
      {
        ikeEncryption: 'AES256'
        ikeIntegrity: 'SHA256'
        dhGroup: 'DHGroup14'
        ipsecEncryption: 'AES256'
        ipsecIntegrity: 'SHA256'
        pfsGroup: 'PFS2048'
        saLifeTimeSeconds: 3600
        saDataSizeKilobytes: 102400000
      }
    ]
  }
}

output gatewayPublicIp string = pip.properties.ipAddress
