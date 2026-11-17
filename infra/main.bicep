// The Knowledge Hub - Azure landing zone (CS2)
// One deployment for the whole platform. Expensive parts (firewall, VPN) are toggles,
// so they can be left out and removed again with the teardown pipeline.
//
//   az deployment group create -g KostovRG -f infra/main.bicep \
//     -p mysqlAdminPassword=... deployFirewall=false deployVpn=false

param location string = resourceGroup().location

@description('Tags on every resource (tagging policy, see docs).')
param tags object = {
  Project: 'KnowledgeHub'
  Environment: 'Production'
  Owner: 'IT'
  CostCenter: 'Library-IT'
  ManagedBy: 'IaC'
}

@description('CS1 on-premises networks that may use cloud services: SRV first, then MGMT.')
param onPremPrefixes array = [
  '10.32.0.0/24'
  '10.64.0.0/24'
]

param deployFirewall bool = false
param deployVpn bool = false

@description('true when the firewall already exists (set by the pipeline), keeps the routes in place.')
param firewallExists bool = false

@description('true when the VPN gateway already exists (set by the pipeline), keeps gateway transit on.')
param vpnExists bool = false

@description('Public IP of the network where pfSense runs. Needed when deployVpn = true.')
param onPremPublicIp string = ''

@secure()
param vpnSharedKey string = ''

param mysqlServerName string = 'kh-monitoring-db-${uniqueString(resourceGroup().id)}'
param mysqlDatabaseName string = 'monitoring'
param mysqlAdminLogin string = 'khadmin'

@secure()
param mysqlAdminPassword string

@description('Email that receives Azure Monitor alerts.')
param alertEmail string = ''

@description('Database CPU % that triggers the alert (lower it to test).')
param dbCpuThreshold int = 80

var routeViaFirewall = deployFirewall || firewallExists
var useRemoteGateway = deployVpn || vpnExists

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    tags: tags
    onPremPrefixes: onPremPrefixes
    routeViaFirewall: routeViaFirewall
  }
}

module firewall 'modules/firewall.bicep' = if (deployFirewall) {
  name: 'firewall'
  params: {
    location: location
    tags: tags
    firewallSubnetId: network.outputs.firewallSubnetId
    firewallMgmtSubnetId: network.outputs.firewallMgmtSubnetId
    onPremPrefixes: onPremPrefixes
  }
}

module vpn 'modules/vpn.bicep' = if (deployVpn) {
  name: 'vpn'
  params: {
    location: location
    tags: tags
    gatewaySubnetId: network.outputs.gatewaySubnetId
    onPremPublicIp: onPremPublicIp
    onPremPrefixes: onPremPrefixes
    sharedKey: vpnSharedKey
  }
}

module peering 'modules/peering.bicep' = {
  name: 'peering'
  params: {
    hubVnetName: network.outputs.hubVnetName
    spokeVnetName: network.outputs.spokeVnetName
    hubVnetId: network.outputs.hubVnetId
    spokeVnetId: network.outputs.spokeVnetId
    useRemoteGateway: useRemoteGateway
  }
  dependsOn: [ vpn ] // gateway transit only works once the gateway exists
}

module database 'modules/database.bicep' = {
  name: 'database'
  params: {
    location: location
    tags: tags
    serverName: mysqlServerName
    databaseName: mysqlDatabaseName
    adminLogin: mysqlAdminLogin
    adminPassword: mysqlAdminPassword
    peSubnetId: network.outputs.peSubnetId
    vnetIds: [ network.outputs.hubVnetId, network.outputs.spokeVnetId ]
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    alertEmail: alertEmail
    mysqlServerId: database.outputs.serverId
    dbCpuThreshold: dbCpuThreshold
  }
}

module platform 'modules/containerplatform.bicep' = {
  name: 'containerplatform'
  params: {
    location: location
    tags: tags
    appsSubnetId: network.outputs.appsSubnetId
    workspaceName: monitoring.outputs.workspaceName
    vnetIds: [ network.outputs.hubVnetId, network.outputs.spokeVnetId ]
  }
}

output mysqlFqdn string = database.outputs.fqdn
output mysqlServerName string = database.outputs.serverName
output acrName string = platform.outputs.acrName
output acrLoginServer string = platform.outputs.acrLoginServer
output containerAppsEnvironment string = platform.outputs.environmentName
output containerAppsDomain string = platform.outputs.defaultDomain
output containerAppsStaticIp string = platform.outputs.staticIp
output vpnGatewayPublicIp string = deployVpn ? vpn!.outputs.gatewayPublicIp : ''
output firewallPrivateIp string = deployFirewall ? firewall!.outputs.privateIp : ''
