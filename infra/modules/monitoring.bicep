// Log Analytics, an action group and a CPU alert on the database.

param location string
param tags object
param alertEmail string
param mysqlServerId string

@description('Lower it (e.g. 5) for a test, so the alert fires.')
param dbCpuThreshold int = 80

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'KH-LogAnalytics'
  location: location
  tags: union(tags, { Service: 'Monitoring' })
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30 // GDPR: keep logs no longer than needed
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'KH-IT-Alerts'
  location: 'global'
  tags: union(tags, { Service: 'Monitoring' })
  properties: {
    groupShortName: 'KH-IT'
    enabled: true
    emailReceivers: empty(alertEmail) ? [] : [
      {
        name: 'IT-Admin'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource mysql 'Microsoft.DBforMySQL/flexibleServers@2023-12-30' existing = {
  name: last(split(mysqlServerId, '/'))
}

resource mysqlDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: mysql
  properties: {
    workspaceId: workspace.id
    logs: [ { categoryGroup: 'allLogs', enabled: true } ]
    metrics: [ { category: 'AllMetrics', enabled: true } ]
  }
}

resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'KH-Database-CPU-High'
  location: 'global'
  tags: union(tags, { Service: 'Monitoring' })
  properties: {
    description: 'Database CPU above ${dbCpuThreshold}% for 5 minutes'
    severity: 2
    enabled: true
    scopes: [ mysqlServerId ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'cpu'
          metricNamespace: 'Microsoft.DBforMySQL/flexibleServers'
          metricName: 'cpu_percent'
          operator: 'GreaterThan'
          threshold: dbCpuThreshold
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [ { actionGroupId: actionGroup.id } ]
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output actionGroupId string = actionGroup.id
