// Container registry + internal Container Apps environment in the spoke.
// Internal = the environment only has a private IP, there is no public ingress at all.

param location string
param tags object
param appsSubnetId string
param workspaceName string
param vnetIds array

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'khacr${uniqueString(resourceGroup().id)}'
  location: location
  tags: union(tags, { Service: 'Registry' })
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false // pulls use the app's managed identity
  }
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'KH-ContainerApps-Env'
  location: location
  tags: union(tags, { Service: 'API' })
  properties: {
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
    vnetConfiguration: {
      infrastructureSubnetId: appsSubnetId
      internal: true
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

// Private DNS for the environment's own domain (runtime name, so in its own module)
module dns 'envdns.bicep' = {
  name: 'dns-containerapps'
  params: {
    zoneName: env.properties.defaultDomain
    staticIp: env.properties.staticIp
    tags: tags
    vnetIds: vnetIds
  }
}

output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output environmentId string = env.id
output environmentName string = env.name
output defaultDomain string = env.properties.defaultDomain
output staticIp string = env.properties.staticIp
