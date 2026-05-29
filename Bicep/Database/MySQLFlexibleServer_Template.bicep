// Knowledge Hub - MySQL Flexible Server
// Monitoring data store for on-prem and cloud metrics

param location string = 'swedencentral'
param serverName string = 'kh-monitoring-db'

@secure()
param administratorLoginPassword string
param administratorLogin string = 'khadmin'

resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2021-12-01-preview' = {
  name: serverName
  location: location
  tags: {
    Project: 'KnowledgeHub'
    Service: 'Database'
    Environment: 'Production'
    ManagedBy: 'IaC'
  }
  sku: {
    // Burstable B1ms - cheapest tier, good for small workloads
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    version: '8.0.21'
    storage: {
      storageSizeGB: 20
      autoGrow: 'Enabled'
      autoIoScaling: 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    // No public network access - private endpoint only
    network: {
      publicNetworkAccess: 'Disabled'
    }
  }
}
