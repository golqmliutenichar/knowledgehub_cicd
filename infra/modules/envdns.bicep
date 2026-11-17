// Private DNS for the Container Apps environment: *.<defaultDomain> -> the environment's static IP.

param zoneName string
param staticIp string
param tags object
param vnetIds array

module zone 'privatedns.bicep' = {
  name: 'dns-containerapps-zone'
  params: {
    zoneName: zoneName
    tags: tags
    vnetIds: vnetIds
  }
}

resource existingZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: zoneName
}

resource records 'Microsoft.Network/privateDnsZones/A@2020-06-01' = [for name in [ '*', '@' ]: {
  parent: existingZone
  name: name
  properties: {
    ttl: 300
    aRecords: [ { ipv4Address: staticIp } ]
  }
  dependsOn: [ zone ]
}]
