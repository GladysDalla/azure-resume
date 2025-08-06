// === PARAMETERS ===
@description('The base name for all resources. A unique string will be appended to ensure global uniqueness.')
@minLength(3)
param projectName string = 'resume${uniqueString(resourceGroup().id)}'

@description('The Azure region where the resources will be deployed.')
param location string = resourceGroup().location

// === VARIABLES ===
var storageAccountName = '${projectName}sa'
var appServicePlanName = '${projectName}-plan'
var functionAppName = '${projectName}-func'

// === RESOURCES ===

// --- 1. Storage Account ---
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
  }
}

// --- 3. Backend Compute (Function App) ---
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.9' // Ensures correct Python version
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
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
          name: 'PYTHON_ISOLATE_WORKER_DEPENDENCIES'
          value: '1'
        }
      ]
      ftpsState: 'FtpsOnly'
    }
  }
}

// === OUTPUTS ===
@description('The name of the deployed Function App.')
output functionAppName string = functionApp.name
