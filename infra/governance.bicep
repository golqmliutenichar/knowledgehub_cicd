// The Knowledge Hub - governance (run ONCE by the subscription owner, not by the pipeline).
// Policies and role assignments need Owner rights; the pipeline identity only has
// Contributor on the resource group (least privilege).
//
//   az deployment group create -g KostovRG -f infra/governance.bicep \
//     -p pipelinePrincipalId=<object id of the GitHub app> budgetEmail=<you>

param location string = resourceGroup().location

@description('Object ID of the service principal that GitHub Actions logs in with.')
param pipelinePrincipalId string

@description('Allowed regions for every resource in this resource group.')
param allowedLocations array = [ 'swedencentral' ]

@description('Tags copied from the resource group to resources that lack them.')
param inheritedTags array = [ 'Project', 'Environment', 'CostCenter' ]

@description('Extra RBAC assignments, e.g. [{ principalId, role: "Reader", principalType: "Group" }].')
param extraRoleAssignments array = []

@description('Monthly budget in EUR for this resource group (0 = no budget).')
param budgetAmount int = 50
param budgetEmail string = ''
param budgetStartDate string = utcNow('yyyy-MM-01')

var roles = {
  Owner: '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
  Contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
  Reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  AcrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  TagContributor: '4a9ae827-6dc8-4573-8ac7-8239d42aa03f'
  CostManagementReader: '72fafb9e-0641-4937-9268-a91bfd8191a3'
}

// ── RBAC ────────────────────────────────────────────────────────────────

// GitHub Actions: Contributor on this resource group only
resource pipelineRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, pipelinePrincipalId, roles.Contributor)
  properties: {
    principalId: pipelinePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.Contributor)
  }
}

// The API's identity: may only pull images
resource apiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'KH-API-Identity'
  location: location
  tags: {
    Project: 'KnowledgeHub'
    Environment: 'Production'
    CostCenter: 'Library-IT'
    ManagedBy: 'IaC'
    Service: 'API'
  }
}

resource apiAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, apiIdentity.id, roles.AcrPull)
  properties: {
    principalId: apiIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.AcrPull)
  }
}

resource extraRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for a in extraRoleAssignments: {
  name: guid(resourceGroup().id, a.principalId, roles[a.role])
  properties: {
    principalId: a.principalId
    principalType: a.principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles[a.role])
  }
}]

// ── Azure Policy ────────────────────────────────────────────────────────

resource allowedLocationsPolicy 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: 'kh-allowed-locations'
  properties: {
    displayName: 'KH - Allowed locations'
    description: 'Resources may only be created in the approved region (data stays in the EU).'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', 'e56962a6-4747-49cd-b67b-bf8b01975c4c')
    parameters: {
      listOfAllowedLocations: { value: allowedLocations }
    }
    enforcementMode: 'Default'
  }
}

resource inheritTag 'Microsoft.Authorization/policyAssignments@2024-04-01' = [for tag in inheritedTags: {
  name: 'kh-inherit-tag-${toLower(tag)}'
  location: location
  identity: { type: 'SystemAssigned' } // needed for the Modify effect
  properties: {
    displayName: 'KH - Inherit tag ${tag} from the resource group'
    policyDefinitionId: tenantResourceId('Microsoft.Authorization/policyDefinitions', 'ea3f2387-9b95-492a-a190-fcdc54f7b070')
    parameters: {
      tagName: { value: tag }
    }
    enforcementMode: 'Default'
  }
}]

resource inheritTagRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for (tag, i) in inheritedTags: {
  name: guid(resourceGroup().id, 'kh-inherit-tag-${toLower(tag)}', roles.TagContributor)
  properties: {
    principalId: inheritTag[i].identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.TagContributor)
  }
}]

// ── Cost management ─────────────────────────────────────────────────────

resource budget 'Microsoft.Consumption/budgets@2023-05-01' = if (budgetAmount > 0 && !empty(budgetEmail)) {
  name: 'KH-Monthly-Budget'
  properties: {
    category: 'Cost'
    amount: budgetAmount
    timeGrain: 'Monthly'
    timePeriod: { startDate: budgetStartDate }
    notifications: {
      Actual80: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: [ budgetEmail ]
      }
      Forecast100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: [ budgetEmail ]
      }
    }
  }
}

output apiIdentityId string = apiIdentity.id
output apiIdentityPrincipalId string = apiIdentity.properties.principalId
