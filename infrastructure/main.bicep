// =====================================================================================
// Bicep Template for the Streamlined DevSecOps Azure Resume Project
//
// Description: This file defines all the necessary Azure resources for the project,
// focusing on serverless, low-cost services and security best practices like
// Managed Identities.
// =====================================================================================


// === PARAMETERS ===
// These are values you can provide at deployment time to customize the deployment.

@description('The base name for all resources. A unique string will be appended to ensure global uniqueness.')
@minLength(3)
param projectName string = 'resume${uniqueString(resourceGroup().id)}'

@description('The Azure region where the resources will be deployed.')
param location string = resourceGroup().location

@description('The globally unique name for the storage account.')
param storageAccountName string 

// === VARIABLES ===
// These are internal values we construct for use within the template to keep names consistent.

var appServicePlanName = '${projectName}-plan'
var functionAppName = '${projectName}-func'
var cosmosAccountName = '${projectName}-db'
//var cdnProfileName = '${projectName}-cdn'
//var cdnEndpointName = projectName // CDN endpoints have different naming rules
var cosmosDbRoleDefinitionId = '00000000-0000-0000-0000-000000000002' // Fixed Role ID for Cosmos DB Data Contributor


// === RESOURCES ===

// Block 1: The Storage Account
@description('The storage account to host the static website content.')
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

// --- 2. Azure Cosmos DB (Serverless) ---
// The NoSQL database used to store the visitor counter.
@description('Serverless Cosmos DB account for the visitor counter.')
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: cosmosAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    // This capability enables the Serverless tier, which is crucial for keeping costs low.
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

// The database within the Cosmos DB account.
resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: 'AzureResume'
  properties: {
    resource: {
      id: 'AzureResume'
    }
  }
}

// The container within the database that will hold our counter item.
resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: cosmosDatabase
  name: 'Counter'
  properties: {
    resource: {
      id: 'Counter'
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
    }
  }
}


// --- 3. Backend Compute (Function App) ---
// The serverless compute resources for our Python backend API.
@description('The consumption-based plan for the serverless function app.')
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  sku: {
    // 'Y1' SKU signifies a Consumption plan, which is pay-per-execution.
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    // Required for Linux consumption plans.
    reserved: true
  }
}

@description('The Python Function App that will run the visitor counter code.')
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  // This block creates the System-Assigned Managed Identity for our app.
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.9'
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
        // Instead of a connection string, we provide the Cosmos DB endpoint.
        // The function will use its Managed Identity for authentication.
        
        {
          name: 'AzureResumeConnectionString'
          value: 'AccountEndpoint=${cosmosAccount.properties.documentEndpoint};'
        }
          
      ]
      ftpsState: 'FtpsOnly'
    }
    httpsOnly: true
  }
}


// --- 4. Security & Delivery (RBAC & CDN) ---
// These resources handle secure access and global content delivery.
@description('Grants the Function Apps Managed Identity access to Cosmos DB.')
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cosmosAccount // The role is scoped securely to only the Cosmos DB account.
  name: guid(functionApp.id, cosmosAccount.id, cosmosDbRoleDefinitionId)
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', cosmosDbRoleDefinitionId)
    principalId: functionApp.identity.principalId // The ID of the Function App's Managed Identity.
    principalType: 'ServicePrincipal'
  }
}

/*
@description('The CDN profile and endpoint to serve the website globally.')
resource cdnProfile 'Microsoft.Cdn/profiles@2023-05-01' = {
  name: cdnProfileName
  location: 'Global'
  sku: {
    // The low-cost, standard CDN tier.
    name: 'Standard_Microsoft'
  }
}

resource cdnEndpoint 'Microsoft.Cdn/profiles/endpoints@2023-05-01' = {
  parent: cdnProfile
  name: cdnEndpointName
  location: 'Global'
  properties: {
    // This tells the CDN where to get the content from.
    originHostHeader: storageAccount.properties.primaryEndpoints.web
    isHttpAllowed: false
    isHttpsAllowed: true
    queryStringCachingBehavior: 'IgnoreQueryString'
    origins: [
      {
        name: 'blobstorage-origin'
        properties: {
          hostName: storageAccount.properties.primaryEndpoints.web
        }
      }
    ]
  }
}

*/
// === OUTPUTS ===
// These values are returned after deployment and can be used in our pipeline or for reference.

//@description('The hostname of the CDN endpoint. This is the public URL for your website.')
//output cdnEndpointHostname string = cdnEndpoint.properties.hostName

@description('The name of the deployed Function App.')
output functionAppName string = functionApp.name
