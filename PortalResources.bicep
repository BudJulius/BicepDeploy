// command to deploy:

// az deployment group create --resource-group {RG_GROUP} --template-file PortalResources.bicep 
// --parameters localtion=${{ secrets.BICEPS_LOCATION }} etc...
// check bicepParams.json for needed parameters, and add them to Github Secrets

param location string = resourceGroup().location
param customerName string 
param existingKeyVaultName string
// param environment string

// Entra groups
param customerPortal_Users string 
param customerPortal_Admins string
param customerPortal_PowerBIAdmins string
param customerPortal_PowerBIEditors string
param customerPortal_GroupOwners string

// Entra apps
@secure()
param portal_WEB_SP_ClientId string
@secure()
param portal_WEB_SP_ClientSecret string
@secure()
param portal_SPA_SP_ClientId string
@secure()
param portal_PowerBI_SP_ClientId string
@secure()
param portal_PowerBI_SP_ClientSecret string
@secure()
param powerBICapacityLicenseId string


// SQL server
@secure()
param sqlAdminUsername string
@secure()
param sqlAdminPassword string
@secure()
param sqlAdminName string
@secure()
param sqlAdminEntraObjectId string

// param fabricAdmins array

var keyVaultSecretsUserRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

var logaName = 'loga-${customerName}-cp'
var appiName = 'appi-${customerName}-cp'
var storageName = 'st${customerName}cp'
var kvName = 'kv-${customerName}-cp'
var containerRegistryName = 'acr${customerName}cp'
var containerEnvironmentName = 'cae-${customerName}-cp'
var containerAppFrontendName = 'capp-${customerName}-cp-frontend'
var containerAppBackendName = 'capp-${customerName}-cp-backend'
var logicAppName = 'la-${customerName}-cp'
var stContainerName_GroupIcons = 'group-icons'
var stContainerName_HelpPagesImages = 'help-pages-images'
var stContainerName_IllustrationPhotos = 'illustration-photos'
var sqlServerName = 'sql-${customerName}-cp'
var sqlDbName = 'sqldb-${customerName}-cp'
var fabricCapacityName = 'fabric-${customerName}-cp'


// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
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
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
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

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name:'default'
}

// Blob Container for group-icons
resource containerGroupIcons 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: stContainerName_GroupIcons
  properties: {
    publicAccess: 'Blob'
  }
}

// Blob Container for help-pages-images
resource containerHelpPagesImages 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: stContainerName_HelpPagesImages
  properties: {
    publicAccess: 'Blob'
  }
}

// Blob Container for illustration-photos
resource containerIllustrationPhotos 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: stContainerName_IllustrationPhotos
  properties: {
    publicAccess: 'Blob'
  }
}

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Enabled'
  }
}

resource sqlServerEntraAdmin 'Microsoft.Sql/servers/administrators@2023-08-01-preview' = {
  parent: sqlServer
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: sqlAdminName
    sid: sqlAdminEntraObjectId
    tenantId: subscription().tenantId
  }
}

resource azureEntraOnly 'Microsoft.Sql/servers/azureADOnlyAuthentications@2023-08-01-preview' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    azureADOnlyAuthentication: false
  }
  dependsOn: [
    sqlServerEntraAdmin
  ]
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
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
resource sqlServerFirewallRule 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

// Container Apps Environment
resource containerEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// Container apps - frontend
resource containerAppFrontend 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppFrontendName
  location: location
  properties: {
    environmentId: containerEnvironment.id
    configuration: {
      activeRevisionsMode: 'single'
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'helloworld'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: 2
            memory: '4Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}


// Logic Apps (Consumption)
resource emailLogicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
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
        When_a_HTTP_request_is_received: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            method: 'POST'
            schema: {
              'Content-Type': 'application/json'
              properties: {
                InvitationURL: {
                  type: 'string'
                }
                InvitedEmail: {
                  type: 'string'
                }
              }
            }
          }
        }
      }
      actions: {
        Parse_JSON: {
          runAfter: {}
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()'
            schema: {
              properties: {
                InvitationURL: {
                  type: 'string'
                }
                InvitedEmail: {
                  type: 'string'
                }
              }
              type: 'object'
            }
          }
        }
        'Send_an_email_(V2)': {
          runAfter: {
            Parse_JSON: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'office365\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              To: '@body(\'Parse_JSON\')?[\'InvitedEmail\']'
              Subject: 'You\'ve been invited to the Ingraphic Kundeportal'
              Body: '''

              <center style="max-width:1000px;">
              <img src="https://${storageAccount.name}.blob.${environment().suffixes.storage}/${stContainerName_IllustrationPhotos}/StandardLogo.png" style="text-align: center; max-width:50%">
              <h2 style="text-align: center; width:80%;"><br>Welcome to Ingraphic Kunde Portal<br>&nbsp;</h2>
              <p style="font-size:17px; width:60%;">The link below will take you to the site for you to enroll into the Ingraphic Portal which will grant you access to your reports:</p>
              <p></p>
              <a href="@{body('Parse_JSON')?['InvitationURL']}" style="background-color: #262735; border: none; color: white; padding: 10px 14px; text-align: center; text-decoration: none; display: inline-block; font-size: 20px; margin: 4px 2px; cursor: pointer; border-radius: 5px;">Accept Invitation</a>
              <p></p>
              <p style="font-size:14px; text-align: center; width:80%;"><br><br>If you believe this email was sent to you by mistake please contact us at <a href="mailto:info@ingraphic.no">Info@Ingraphic.no</a>.<br>&nbsp;</p>
              </center>

              '''
              Importance: 'Normal'
            }
            path: '/v2/Mail'
          }
        }
        Success_Response: {
          runAfter: {
            'Send_an_email_(V2)': [
              'Succeeded'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            body: {
              Input: '@{triggerBody()}'
              Message: 'Email was sent Successfully to @{body(\'Parse_JSON\')?[\'InvitedEmail\']}'
            }
          }
        }
        Failure_Response: {
          runAfter: {
            'Send_an_email_(V2)': [
              'TimedOut'
              'Skipped'
              'Failed'
            ]
          }
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 500
            body: {
              'Custom Message': 'Something isn\'t quite right, Please go to your logic app at https://portal.azure.com for further information: '
              'Inner Message': '@body(\'Send_an_email_(V2)\')'
            }
          }
        }
      }
      outputs: {}
    }
  }
}

// Fabric Capacity
// resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
//   name: fabricCapacityName
//   location: location
//   sku: {
//     name: 'F2'
//     tier: 'Free'
//   }
//   properties: {
//     administration: {
//       members: fabricAdmins
//     }
//   }
// }

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
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
    resource azureTenantId 'secrets' = {
      name: 'AZURETENANTID'
      properties: {
        value: subscription().tenantId
      }
    }

    resource azureWebClientId 'secrets' = {
      name: 'AZURECLIENTID'
      properties: {
        value: portal_WEB_SP_ClientId
      }
    }
    
    resource azureWebClientSecret 'secrets' = {
      name: 'AZURECLIENTSECRET'
      properties: {
        value: portal_WEB_SP_ClientSecret
      }
    }

    resource azureSpaClientId 'secrets' = {
      name: 'AZURESPACLIENTID'
      properties: {
        value: portal_SPA_SP_ClientId
      }
    }
    
    resource blobConnectionString 'secrets' = {
      name: 'BlobConnectionString'
      properties: {
        value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value}'
      }
    }
    
    resource blobGroupLogoContainer 'secrets' = {
      name: 'BlobGroupLogoContainer'
      properties: {
        value: stContainerName_GroupIcons
      }
    }
    
    resource blobHelpPagesImageContainer 'secrets' = {
      name: 'BlobHelpPagesImageContainer'
      properties: {
        value: stContainerName_HelpPagesImages
      }
    }
    
    resource blobStorageURL 'secrets' = {
      name: 'BlobStorageURL'
      properties: {
        value: storageAccount.properties.primaryEndpoints.blob
      }
    }
    
    resource dbConnectionString 'secrets' = {
      name: 'DBConnectionString'
      properties: {
        value: 'Server=tcp:${sqlServerName}.${environment().suffixes.sqlServerHostname},1433;Initial Catalog=${sqlDbName};Persist Security Info=False;User ID=${sqlAdminUsername};Password=${sqlAdminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
      }
    }
    
    resource groupAdminUsers 'secrets' = {
      name: 'GROUPAdminUsers'
      properties: {
        value: customerPortal_Admins
      }
    }
    
    resource groupAllUsers 'secrets' = {
      name: 'GROUPAllUsers'
      properties: {
        value: customerPortal_Users
      }
    }
    
    resource groupLogoAdminURL 'secrets' = {
      name: 'GroupLogoAdminURL'
      properties: {
        value: '${storageAccount.properties.primaryEndpoints.blob}${stContainerName_IllustrationPhotos}/AdminLogo.png'
      }
    }
    
    resource groupLogoPrefix 'secrets' = {
      name: 'GroupLogoPrefix'
      properties: {
        value: 'GroupLogo_'
      }
    }
    
    resource groupLogoStandardURL 'secrets' = {
      name: 'GroupLogoStandardURL'
      properties: {
        value: '${storageAccount.properties.primaryEndpoints.blob}${stContainerName_IllustrationPhotos}/StandardLogo.png'
      }
    }
    
    resource groupOwnerUsers 'secrets' = {
      name: 'GROUPOwnerUsers'
      properties: {
        value: customerPortal_GroupOwners
      }
    }
    
    resource groupPowerBIAdmins 'secrets' = {
      name: 'GROUPPowerBIAdmins'
      properties: {
        value: customerPortal_PowerBIAdmins
      }
    }
    
    resource groupReportEditors 'secrets' = {
      name: 'GROUPReportEditors'
      properties: {
        value: customerPortal_PowerBIEditors
      }
    }
    
    resource helpPagesImagePrefix 'secrets' = {
      name: 'HelpPagesImagePrefix'
      properties: {
        value: 'HelpPageImage_'
      }
    }
    
    resource helpPagesStandardImage 'secrets' = {
      name: 'HELPPAGEDEFAULTHEADERIMAGEURL'
      properties: {
        value: '${storageAccount.properties.primaryEndpoints.blob}${stContainerName_HelpPagesImages}/HelpPage_StandardImage.png'
      }
    }
    
    resource invitationRedirectURL 'secrets' = {
      name: 'InvitationRedirectURL'
      properties: {
        value: containerAppFrontend.id
      }
    }
    
    resource pbiClientId 'secrets' = {
      name: 'PBICLIENTID'
      properties: {
        value: portal_PowerBI_SP_ClientId
      }
    }
    
    resource pbiClientSecret 'secrets' = {
      name: 'PBICLIENTSECRET'
      properties: {
        value: portal_PowerBI_SP_ClientSecret
      }
    }
    
    resource pbiTenantId 'secrets' = {
      name: 'PBITENANTID'
      properties: {
        value: subscription().tenantId
      }
    }

    resource pbiCapacityLicense 'secrets' = {
      name: 'PBICAPACITYLICENSEID'
      properties: {
        value: powerBICapacityLicenseId
      }
    }
    
    resource sendInviteEmailURL 'secrets' = {
      name: 'SendInviteEmailURL'
      properties: {
        value: 'INSERT URL HERE'
      }
    }
    
    resource verifiedDomainOfDirectory 'secrets' = {
      name: 'VerifiedDomainOfDirectory'
      properties: {
        value: 'INSERT DOMAIN HERE'
      }
    }
}


// // For existing Key Vault
// resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = {
//   name: existingKeyVaultName
// }

// // Insert secrets
// resource azureTenantId 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'AZURETENANTID'
//   properties: {
//     value: subscription().tenantId
//   }
// }

// resource azureWebClientId 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'AZURECLIENTID'
//   properties: {
//     value: portal_WEB_SP_ClientId
//   }
// }

// resource azureWebClientSecret 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'AZURECLIENTSECRET'
//   properties: {
//     value: portal_WEB_SP_ClientSecret
//   }
// }

// resource azureSpaClientId 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'AZURESPACLIENTID'
//   properties: {
//     value: portal_SPA_SP_ClientId
//   }
// }

// resource blobConnectionString 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'BlobConnectionString'
//   properties: {
//     value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value}'
//   }
// }

// resource blobGroupLogoContainer 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'BlobGroupLogoContainer'
//   properties: {
//     value: stContainerName_GroupIcons
//   }
// }

// resource blobHelpPagesImageContainer 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'BlobHelpPagesImageContainer'
//   properties: {
//     value: stContainerName_HelpPagesImages
//   }
// }

// resource blobStorageURL 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'BlobStorageURL'
//   properties: {
//     value: storageAccount.properties.primaryEndpoints.blob
//   }
// }

// resource dbConnectionString 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'DBConnectionString'
//   properties: {
//     value: 'Server=tcp:${sqlServerName}.${environment().suffixes.sqlServerHostname},1433;Initial Catalog=${sqlDbName};Persist Security Info=False;User ID=${sqlAdminUsername};Password=${sqlAdminPassword};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
//   }
// }

// resource groupAdminUsers 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'GROUPAdminUsers'
//   properties: {
//     value: customerPortal_Admins
//   }
// }

// resource groupAllUsers 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'GROUPAllUsers'
//   properties: {
//     value: customerPortal_Users
//   }
// }

// resource groupLogoAdminURL 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'GroupLogoAdminURL'
//   properties: {
//     value: '${storageAccount.properties.primaryEndpoints.blob}${stContainerName_IllustrationPhotos}/AdminLogo.png'
//   }
// }

// resource groupLogoPrefix 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'GroupLogoPrefix'
//   properties: {
//     value: 'GroupLogo_'
//   }
// }

// resource groupLogoStandardURL 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'GroupLogoStandardURL'
//   properties: {
//     value: '${storageAccount.properties.primaryEndpoints.blob}${stContainerName_IllustrationPhotos}/StandardLogo.png'
//   }
// }

// resource groupOwnerUsers 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'GROUPOwnerUsers'
//   properties: {
//     value: customerPortal_GroupOwners
//   }
// }

// resource groupPowerBIAdmins 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'GROUPPowerBIAdmins'
//   properties: {
//     value: customerPortal_PowerBIAdmins
//   }
// }

// resource groupReportEditors 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'GROUPReportEditors'
//   properties: {
//     value: customerPortal_PowerBIEditors
//   }
// }

// resource helpPagesImagePrefix 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'HelpPagesImagePrefix'
//   properties: {
//     value: 'HelpPageImage_'
//   }
// }

// resource helpPagesStandardImage 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'HELPPAGEDEFAULTHEADERIMAGEURL'
//   properties: {
//     value: '${storageAccount.properties.primaryEndpoints.blob}${stContainerName_HelpPagesImages}/HelpPage_StandardImage.png'
//   }
// }

// resource invitationRedirectURL 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'InvitationRedirectURL'
//   properties: {
//     value: containerAppFrontend.id
//   }
// }

// resource pbiClientId 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'PBICLIENTID'
//   properties: {
//     value: portal_PowerBI_SP_ClientId
//   }
// }

// resource pbiClientSecret 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'PBICLIENTSECRET'
//   properties: {
//     value: portal_PowerBI_SP_ClientSecret
//   }
// }

// resource pbiTenantId 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'PBITENANTID'
//   properties: {
//     value: subscription().tenantId
//   }
// }

// resource powerBICapacityLicense 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'PBICAPACITYLICENSEID'
//   properties: {
//     value: powerBICapacityLicenseId
//   }
// }

// resource sendInviteEmailURL 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'SendInviteEmailURL'
//   properties: {
//     value: 'INSERT URL HERE'
//   }
// }

// resource verifiedDomainOfDirectory 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: keyVault
//   name: 'VerifiedDomainOfDirectory'
//   properties: {
//     value: 'INSERT DOMAIN HERE'
//   }
// }


// Container app backend - create and assign secrets to revision
resource containerAppBackend 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppBackendName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerEnvironment.id
    configuration: {
      activeRevisionsMode: 'single'
      ingress: {
        external: true
        targetPort: 80
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
        corsPolicy: {
          allowCredentials: true
          allowedOrigins: [
            'https://localhost:4200'
            'https://${containerAppFrontend.properties.configuration.ingress.fqdn}'
          ]
          allowedMethods: [
            'GET'
            'POST'
            'PUT'
            'DELETE'
          ]
        }
      }
      secrets: [
        {
          name: 'test-secret'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/AZURETENANTID'
          identity: 'System'
        }
        {
          name: 'azure-tenant-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/AZURETENANTID'
          identity: 'System'
        }
        {
          name: 'azure-client-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/AZURECLIENTID'
          identity: 'System'
        }
        {
          name: 'azure-client-secret'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/AZURECLIENTSECRET'
          identity: 'System'
        }
        {
          name: 'blob-connection-string'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/BlobConnectionString'
          identity: 'System'
        }
        {
          name: 'blob-group-logo-container'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/BlobGroupLogoContainer'
          identity: 'System'
        }
        {
          name: 'blob-helppages-image-container'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/BlobHelpPagesImageContainer'
          identity: 'System'
        }
        {
          name: 'blob-storage-url'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/BlobStorageURL'
          identity: 'System'
        }
        {
          name: 'db-connection-string'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/DBConnectionString'
          identity: 'System'
        }
        {
          name: 'group-admin-users'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/GROUPAdminUsers'
          identity: 'System'
        }
        {
          name: 'group-all-users'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/GROUPAllUsers'
          identity: 'System'
        }
        {
          name: 'group-logo-admin-url'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/GroupLogoAdminURL'
          identity: 'System'
        }
        {
          name: 'group-logo-prefix'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/GroupLogoPrefix'
          identity: 'System'
        }
        {
          name: 'group-logo-standard-url'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/GroupLogoStandardURL'
          identity: 'System'
        }
        {
          name: 'group-owner-users'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/GROUPOwnerUsers'
          identity: 'System'
        }
        {
          name: 'group-powerbi-admins'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/GROUPPowerBIAdmins'
          identity: 'System'
        }
        {
          name: 'group-report-editors'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/GROUPReportEditors'
          identity: 'System'
        }
        {
          name: 'helppages-image-prefix'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/HelpPagesImagePrefix'
          identity: 'System'
        }
        {
          name: 'helppage-default-headerimage-url'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/HELPPAGEDEFAULTHEADERIMAGEURL'
          identity: 'System'
        }
        {
          name: 'invitation-redirect-url'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/InvitationRedirectURL'
          identity: 'System'
        }
        {
          name: 'pbi-client-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/PBICLIENTID'
          identity: 'System'
        }
        {
          name: 'pbi-client-secret'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/PBICLIENTSECRET'
          identity: 'System'
        }
        {
          name: 'pbi-tenant-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/PBITENANTID'
          identity: 'System'
        }
        {
          name: 'pbi-capacity-license-id'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/PBICAPACITYLICENSEID'
          identity: 'System'
        }
        {
          name: 'send-invite-email-url'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/SendInviteEmailURL'
          identity: 'System'
        }
        {
          name: 'verified-domain-of-directory'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/VerifiedDomainOfDirectory'
          identity: 'System'
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'helloworld'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: 2
            memory: '4Gi'
          }
          env: [
            {
              name: 'AZURE_TENANT_ID'
              secretRef: 'azure-tenant-id'
            }
            {
              name: 'AZURE_CLIENT_ID'
              secretRef: 'azure-client-id'
            }
            {
              name: 'AZURE_CLIENT_SECRET'
              secretRef: 'azure-client-secret'
            }
            {
              name: 'BLOB_CONNECTION_STRING'
              secretRef: 'blob-connection-string'
            }
            {
              name: 'BLOB_GROUP_LOGO_CONTAINER'
              secretRef: 'blob-group-logo-container'
            }
            {
              name: 'BLOB_HELPPAGES_IMAGE_CONTAINER'
              secretRef: 'blob-helppages-image-container'
            }
            {
              name: 'BLOB_STORAGE_URL'
              secretRef: 'blob-storage-url'
            }
            {
              name: 'DB_CONNECTION_STRING'
              secretRef: 'db-connection-string'
            }
            {
              name: 'GROUP_Admin_Users'
              secretRef: 'group-admin-users'
            }
            {
              name: 'GROUP_All_Users'
              secretRef: 'group-all-users'
            }
            {
              name: 'GROUP_LOGO_ADMIN_URL'
              secretRef: 'group-logo-admin-url'
            }
            {
              name: 'GROUP_LOGO_PREFIX'
              secretRef: 'group-logo-prefix'
            }
            {
              name: 'GROUP_LOGO_STANDARD_URL'
              secretRef: 'group-logo-standard-url'
            }
            {
              name: 'GROUP_Owner_Users'
              secretRef: 'group-owner-users'
            }
            {
              name: 'GROUP_PowerBI_Admins'
              secretRef: 'group-powerbi-admins'
            }
            {
              name: 'GROUP_Report_Editors'
              secretRef: 'group-report-editors'
            }
            {
              name: 'HELPPAGES_IMAGE_PREFIX'
              secretRef: 'helppages-image-prefix'
            }
            {
              name: 'HELPPAGE_DEFAULT_HEADERIMAGE_URL'
              secretRef: 'helppage-default-headerimage-url'
            }
            {
              name: 'Invitation_Redirect_Url'
              secretRef: 'invitation-redirect-url'
            }
            {
              name: 'PBI_CLIENT_ID'
              secretRef: 'pbi-client-id'
            }
            {
              name: 'PBI_CLIENT_SECRET'
              secretRef: 'pbi-client-secret'
            }
            {
              name: 'PBI_TENANT_ID'
              secretRef: 'pbi-tenant-id'
            }
            {
              name: 'PowerBI_Capacity_License_ID'
              secretRef: 'pbi-capacity-license-id'
            }
            {
              name: 'SEND_INVITE_EMAIL_URL'
              secretRef: 'send-invite-email-url'
            }
            {
              name: 'VERIFIED_DOMAIN_OF_DIRECTORY'
              secretRef: 'verified-domain-of-directory'
            }
           ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

resource kvFunctionAppPermissions 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, containerAppBackendName, keyVaultSecretsUserRole)
  scope: keyVault
  properties: {
    principalId: containerAppBackend.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRole
  }
}
