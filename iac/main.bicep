// main.bicep

// Parameters for customization
@description('The prefix for all resource names.')
param namePrefix string = 'bicepdemo'

@description('The location for all resources.')
param location string = resourceGroup().location

// Variable to create a unique storage account name
var storageAccountName = '${namePrefix}${uniqueString(resourceGroup().id)}'

// Resource definition for an Azure Storage Account
resource stg 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
  }
}

// Resource definition for an Azure App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: '${namePrefix}-asp'
  location: location
  sku: {
    name: 'F1'
    tier: 'Free'
  }
  properties: {}
}

// Output the storage account's primary endpoint URL
output storageEndpoint string = stg.properties.primaryEndpoints.blob
