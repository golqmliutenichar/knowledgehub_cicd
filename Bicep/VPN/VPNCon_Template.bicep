param connectionName string = 'KH-VPN-Connection'
param location string = 'swedencentral'
param vpnGatewayId string
param localGatewayId string

// Shared key for the VPN connection - change this to a strong secret
@secure()
param sharedKey string

resource vpnConnection 'Microsoft.Network/connections@2021-02-01' = {
  name: connectionName
  location: location
  tags: {
    Project: 'KnowledgeHub'
    Service: 'VPN'
    ManagedBy: 'IaC'
  }
  properties: {
    connectionType: 'IPsec'
    virtualNetworkGateway1: {
      id: vpnGatewayId
      properties: {}
    }
    localNetworkGateway2: {
      id: localGatewayId
      properties: {}
    }
    sharedKey: sharedKey
    enableBgp: false
    routingWeight: 10
    ipsecPolicies: [
      {
        saLifeTimeSeconds: 3600
        saDataSizeKilobytes: 102400000
        ipsecEncryption: 'AES256'
        ipsecIntegrity: 'SHA256'
        ikeEncryption: 'AES256'
        ikeIntegrity: 'SHA256'
        dhGroup: 'DHGroup14'
        pfsGroup: 'PFS14'
      }
    ]
  }
}
