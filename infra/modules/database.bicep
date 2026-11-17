// Azure Database for MySQL Flexible Server, reachable only through a private endpoint.

param location string
param tags object
param serverName string
param databaseName string
param adminLogin string

@secure()
param adminPassword string

param peSubnetId string
param vnetIds array

@description('Burstable B1ms: the cheapest tier, enough for monitoring data.')
param skuName string = 'Standard_B1ms'

resource server 'Microsoft.DBforMySQL/flexibleServers@2023-12-30' = {
  name: serverName
  location: location
  tags: union(tags, { Service: 'Database' })
  sku: { name: skuName, tier: 'Burstable' }
  properties: {
    version: '8.0.21'
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: 20
      autoGrow: 'Enabled'
      autoIoScaling: 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: { mode: 'Disabled' }
    network: {
      publicNetworkAccess: 'Disabled' // private endpoint only (REQ-S2P2-03)
    }
  }
}

resource db 'Microsoft.DBforMySQL/flexibleServers/databases@2023-12-30' = {
  parent: server
  name: databaseName
  properties: {
    charset: 'utf8mb4'
    collation: 'utf8mb4_0900_ai_ci'
  }
}

module dns 'privatedns.bicep' = {
  name: 'dns-mysql'
  params: {
    zoneName: 'privatelink.mysql.database.azure.com'
    tags: tags
    vnetIds: vnetIds
  }
}

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'KH-MySQL-PrivateEndpoint'
  location: location
  tags: union(tags, { Service: 'Database' })
  properties: {
    subnet: { id: peSubnetId }
    customNetworkInterfaceName: 'KH-MySQL-PrivateEndpoint-nic'
    privateLinkServiceConnections: [
      {
        name: 'KH-MySQL-PrivateConnection'
        properties: {
          privateLinkServiceId: server.id
          groupIds: [ 'mysqlServer' ]
        }
      }
    ]
  }
}

// Creates and maintains the A record in the private zone automatically
resource zoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'mysql'
        properties: { privateDnsZoneId: dns.outputs.zoneId }
      }
    ]
  }
}

output serverId string = server.id
output serverName string = server.name
output fqdn string = server.properties.fullyQualifiedDomainName
