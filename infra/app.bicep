// The monitoring API as a Container App (deployed by the pipeline after the image is built).
// Kept apart from main.bicep so an infrastructure run never resets the running image.

param location string = resourceGroup().location
param tags object = {
  Project: 'KnowledgeHub'
  Environment: 'Production'
  Owner: 'IT'
  CostCenter: 'Library-IT'
  ManagedBy: 'IaC'
  Service: 'API'
}

@description('Full image name, e.g. khacrxxxx.azurecr.io/monitoring-api:<git sha>')
param image string
param acrLoginServer string
param environmentName string = 'KH-ContainerApps-Env'
param identityName string = 'KH-API-Identity'

param dbHost string
param dbName string = 'monitoring'
param dbUser string = 'khadmin'

@secure()
param dbPassword string

@secure()
param apiKey string

@description('0 = scale to zero when idle (cheapest).')
param minReplicas int = 0

resource env 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

// Created once by governance.bicep (owner), which also gives it AcrPull
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: identityName
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'kh-monitoring-api'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true // "external" inside an internal environment = reachable from the VNet only
        targetPort: 8000
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acrLoginServer
          identity: identity.id
        }
      ]
      secrets: [
        { name: 'db-password', value: dbPassword }
        { name: 'api-key', value: apiKey }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: image
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
          env: [
            { name: 'DB_HOST', value: dbHost }
            { name: 'DB_NAME', value: dbName }
            { name: 'DB_USER', value: dbUser }
            { name: 'DB_PASSWORD', secretRef: 'db-password' }
            { name: 'API_KEY', secretRef: 'api-key' }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: { path: '/health/live', port: 8000 }
              periodSeconds: 30
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: 2
      }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
