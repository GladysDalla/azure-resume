// Bicep template for a secure, serverless Azure Resume solution.
// This template creates a Storage Account for the frontend, a Function App for the backend,
// Application Insights for monitoring, and a Key Vault for secrets management.
// It leverages Managed Identities for secure, passwordless access.

// === PARAMETERS ===
@description('The Azure region where all resources will be deployed.')
param location string = resourceGroup().location

@description('A unique name for the project, used as a prefix for all resources.')
param projectName string = 'resume${uniqueString(resourceGroup().id)}'

@description('The object ID of the Service Principal used by GitHub Actions for deployment.')
param githubSpObjectId string


// === VARIABLES ===
var logAnalyticsWorkspaceName = '${projectName}-logs'
var applicationInsightsName = '${projectName}-insights'
var storageAccountName = '${projectName}sa'
var keyVaultName = '${projectName}-kv'
var appServicePlanName = '${projectName}-plan'
var functionAppName = '${projectName}-func'


// === RESOURCES ===

// --- 1. Monitoring Resources ---
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}


// --- 2. Storage Account ---
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    staticWebsite: {
      enabled: true
      indexDocument: 'index.html'
      error404Document: 'index.html'
    }
  }
}


// --- 3. Key Vault ---
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
  }
}


// --- 4. Backend Compute (Function App) ---
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1' // Consumption plan
    tier: 'Dynamic'
  }
  properties: {
    reserved: true // Required for Linux
  }
}

resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned' // Enable Managed Identity
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.9'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        // Reference to the Key Vault for the Cosmos DB connection string
        {
          name: 'CosmosDbConnectionString'
          value: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=CosmosDbConnectionString)'
        }
      ]
    }
  }
}


// --- 5. Security and Access Control (RBAC) ---

// Grant the Function App's Managed Identity permission to read secrets from Key Vault
resource functionAppKvAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, functionApp.id, 'Key Vault Secrets User')
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Role ID for "Key Vault Secrets User"
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant the GitHub Actions Service Principal permission to set secrets in Key Vault
resource githubSpKvAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, githubSpObjectId, 'Key Vault Secrets Officer')
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c1AD280') // Role ID for "Key Vault Secrets Officer"
    principalId: githubSpObjectId
    principalType: 'ServicePrincipal'
  }
}


// === OUTPUTS ===
@description('The name of the deployed Function App.')
output functionAppName string = functionApp.name

@description('The public URL of the frontend website.')
output websiteUrl string = storageAccount.properties.primaryEndpoints.web
