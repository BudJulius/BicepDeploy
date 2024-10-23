// command to deploy:

// az deployment group create --resource-group rg-se-biceptest-ne --template-file DeployAzureResources.bicep 
// --parameters customerName=biceptest environment=dev spaClientId=any-guid-here apiClientId=any-guid-here usersGroupId=any-guid-here 
// adminsGroupId=any-guid-here sqlAdminPassword=YourPassword123! apiClientSecret=YourApiSecret123!

param location string = resourceGroup().location
param customerName string
param environment string
param spaClientId string
param apiClientId string
param usersGroupId string
param adminsGroupId string

@secure()
param sqlAdminPassword string
@secure()
param apiClientSecret string

var suffix = '001'
var keyVaultSecretsUserRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var kvName = 'kv-${customerName}-se-${environment}-${suffix}'
var swaName = 'swa-${customerName}-se-${environment}-${suffix}'
var logaName = 'loga-${customerName}-se-${environment}-${suffix}'
var appiName = 'appi-${customerName}-se-${environment}-${suffix}'
var storageName = 'st${customerName}se${environment}${suffix}'
var sqlServerName = 'sql-${customerName}-se-${environment}-${suffix}'
var sqlDbName = 'sqldb-${customerName}-se-${environment}-${suffix}'
var emailLogicAppName = 'la-${customerName}-se-${environment}-email-${suffix}'
var receiptLogicAppName = 'la-${customerName}-se-${environment}-receipt-${suffix}'
var functionAppName = 'func-${customerName}-se-${environment}-${suffix}'
var appServicePlanName = 'asp-${customerName}-se-${environment}-${suffix}'
var containerNameBlob = 'blobcont'
var containerNameImages = 'images'


// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logaName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appiName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowSharedKeyAccess: true
    allowBlobPublicAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

// Blob Container for confidential files
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: '${storageAccount.name}/default/${containerNameBlob}'
  properties: {
    publicAccess: 'None'
  }
}

// Images Container
resource containerImages 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: '${storageAccount.name}/default/${containerNameImages}'
  properties: {
    publicAccess: 'Blob'
  }
}

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: 'SurveyDBAdmin'
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Enabled'
  }
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2022-05-01-preview' = {
  parent: sqlServer
  name: sqlDbName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 10
  }
  properties: {
    requestedBackupStorageRedundancy: 'Local'
  }
}

// Allow Azure Services
resource sqlServerFirewallRule 'Microsoft.Sql/servers/firewallRules@2022-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
}

// Static Web App
resource staticWebApp 'Microsoft.Web/staticSites@2022-03-01' = {
  name: swaName
  location: 'West Europe'
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {}
}

// Logic Apps (Consumption)
resource emailLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: emailLogicAppName
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_a_HTTP_request_is_received': {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                accessCode: {
                  type: 'integer'
                }
                content: {
                  type: 'string'
                }
                customer: {
                  type: 'string'
                }
                customerEmail: {
                  type: 'string'
                }
                deadline: {
                  type: 'string'
                }
                header: {
                  type: 'string'
                }
                link: {
                  type: 'string'
                }
                logoURL: {
                  type: 'string'
                }
                sendFrom: {
                  type: 'string'
                }
                sendTo: {
                  type: 'string'
                }
                surveyName: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
      }
      actions: {
        'Send_an_email_(V2)': {
          type: 'ApiConnection'
          runAfter: {}
          inputs: {
            method: 'post'
            path: '/v2/Mail'
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            body: {
              To: '@triggerBody()?[\'sendTo\']'
              Subject: '@triggerBody()?[\'header\']'
              Body: '''
                <p>@{triggerBody()?['content']}</p>
                <br>
                <p>@{triggerBody()?['surveyName']}</p>
                <p>Deadline: @{triggerBody()?['deadline']}</p>
                <p>Link to survey: <a href="@{triggerBody()?['link']}">@{triggerBody()?['surveyName']}</a></p>
                <p>Access code to survey: @{triggerBody()?['accessCode']}</p>
                <p></p>
                <br>
                <p class="editor-paragraph">@{triggerBody()?['customer']}</p>
                <p class="editor-paragraph"></p>
                <img style="max-width: 100%; height: 150px;" alt="Logo" src="@{triggerBody()?['logoURL']}">
              '''
              Importance: 'Normal'
            }
          }
        }
      }
      outputs: {}
    }
  }
}

resource receiptLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: receiptLogicAppName
  location: location
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        'When_a_HTTP_request_is_received': {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              properties: {
                attachment: {
                  type: 'string'
                }
                content: {
                  type: 'string'
                }
                header: {
                  type: 'string'
                }
                sendTo: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
      }
      actions: {
        'Send_an_email_(V2)-copy': {
          type: 'ApiConnection'
          runAfter: {}
          inputs: {
            method: 'post'
            path: '/v2/Mail'
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            body: {
              To: '@triggerBody()?[\'sendTo\']'
              Subject: '@triggerBody()?[\'header\']'
              Importance: 'Normal'
              Body: 'Hello!<br><br>@{triggerBody()?[\'content\']}'
              Attachments: [
                {
                  ContentBytes: '@{triggerBody()?[\'attachment\']}'
                  Name: '@{concat(\'Survey Receipt - \', triggerBody()?[\'header\'], \'.pdf\')}'
                }
              ]
            }
          }
        }
      }
      outputs: {}
    }
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableRbacAuthorization: true
    accessPolicies: []
  }

    // Insert secrets
  resource connectionStringBlob 'secrets' = {
    name: 'BLOB-STORAGE-SurveyEngine-CONNECTIONSTRING'
    properties: {
      contentType: 'text/plain'
      value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
    }
  }
  resource connectionStringDatabase 'secrets' = {
    name: 'SQL-DB-SurveyEngine-CONNECTIONSTRING'
    properties: {
      contentType: 'text/plain'
      value: 'Server=tcp:${sqlServer.name},1433;Initial Catalog=${sqlDatabase.name};Persist Security Info=False;User ID=SurveyDBAdmin;Password=${sqlAdminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    }
  }

  resource secretSpaClientId 'secrets' = {
    name: 'ENTRA-SurveyEngine-SPA-CLIENT-ID'
    properties: {
      contentType: 'text/plain'
      value: spaClientId
    }
  }

  resource secretApiClientId 'secrets' = {
    name: 'ENTRA-SurveyEngine-CLIENT-ID'
    properties: {
      contentType: 'text/plain'
      value: apiClientId
    }
  }
  
  resource secretApiSecret 'secrets' = {
    name: 'ENTRA-SurveyEngine-API-SECRET'
    properties: {
      contentType: 'text/plain'
      value: apiClientSecret
    }
  }
  
  resource secretUsersGroupId 'secrets' = {
    name: 'ENTRA-SG-APP-SurveyEngine-Users'
    properties: {
      contentType: 'text/plain'
      value: usersGroupId
    }
  }
  
  resource secretAdminsGroupId 'secrets' = {
    name: 'ENTRA-SG-APP-SurveyEngine-Admins'
    properties: {
      contentType: 'text/plain'
      value: adminsGroupId
    }
  }
  
  resource blobAccessKey 'secrets' = {
    name: 'BLOB-STORAGE-SurveyEngine-ACCESS-KEY'
    properties: {
      contentType: 'text/plain'
      value: storageAccount.listKeys().keys[0].value
    }
  }
}


// Function App
resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      netFrameworkVersion: 'v8.0'
      cors: {
        allowedOrigins: [
          'https://localhost:4200'
          staticWebApp.properties.defaultHostname
        ]
      }
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'FRONTEND_URL'
          value: staticWebApp.properties.defaultHostname
        }
        {
          name: 'ENTRA_TENANT_ID'
          value: subscription().tenantId
        }
        {
          name: 'ENTRA_SurveyEngine_SPA_CLIENT_ID'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::secretSpaClientId.name})'
        }
        {
          name: 'ENTRA_SurveyEngine_CLIENT_ID'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::secretApiClientId.name})'
        }
        {
          name: 'ENTRA_SurveyEngine_API_SECRET'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::secretApiSecret.name})'
        }
        {
          name: 'ENTRA_SG_APP_SurveyEngine_Users'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::secretUsersGroupId.name})'
        }
        {
          name: 'ENTRA_SG_APP_SurveyEngine_Admins'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::secretAdminsGroupId.name})'
        }
        {
          name: 'SQL_DB_SurveyEngine_CONNECTIONSTRING'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::connectionStringDatabase.name})'
        }
        {
          name: 'BLOB_STORAGE_SurveyEngine_CONNECTIONSTRING'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::connectionStringBlob.name})'
        }
        {
          name: 'BLOB_STORAGE_SurveyEngine_CONTAINER_NAME'
          value: containerNameBlob
        }
        {
          name: 'BLOB_STORAGE_SurveyEngine_CONTAINER_IMAGES'
          value: containerNameImages
        }
        {
          name: 'BLOB_STORAGE_SurveyEngine_ACCESS_KEY'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::blobAccessKey.name})'
        }
        {
          name: 'EMAIL_LOGIC_APP_ENDPOINT'
          value: listCallbackUrl('${emailLogicApp.id}/triggers/When_a_HTTP_request_is_received', emailLogicApp.apiVersion).value
        }
        {
          name: 'RECEIPT_LOGIC_APP_ENDPOINT'
          value: listCallbackUrl('${receiptLogicApp.id}/triggers/When_a_HTTP_request_is_received', emailLogicApp.apiVersion).value
        }
      ]
      connectionStrings: [
        {
          name: 'SQL_DB_SurveyEngine_CONNECTIONSTRING'
          type: 'SQLAzure'
          connectionString: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::connectionStringDatabase.name})'
        }
        {
          name: 'BLOB_STORAGE_SurveyEngine_CONNECTIONSTRING'
          type: 'Custom'
          connectionString: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::connectionStringBlob.name})'
        }
      ]
    }
  }
}

resource kvFunctionAppPermissions 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, functionAppName, keyVaultSecretsUserRole)
  scope: keyVault
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRole
  }
}

output keyVaultName string = keyVault.name
output storageAccountName string = storageAccount.name
output functionAppName string = functionApp.name
output staticWebAppName string = staticWebApp.name
output sqlServerName string = sqlServer.name
output sqlDatabaseName string = sqlDatabase.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
