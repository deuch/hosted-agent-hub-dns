using 'main.bicep'

// Example values: replace every <placeholder>. Names left out use the defaults of main.bicep.
// Address spaces and subnets keep the defaults of main.bicep (10.0.0.0/16, 10.1.0.0/16, 10.2.0.0/16).

param hubResourceGroup = '<hub-resource-group>'
param dnsResourceGroup = '<dns-resource-group>'
param aiResourceGroup = '<ai-resource-group>'

param acrName = '<globally-unique-acr-name>'
param foundryName = '<globally-unique-foundry-name>'
param projectName = '<foundry-project-name>'

param vmAdminUsername = '<vm-admin-username>'
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')

// Optional
// param location = '<region>'
// param userObjectId = '<entra-user-object-id>'
// param acrAllowedIps = ['<public-ip-1>', '<public-ip-2>']
