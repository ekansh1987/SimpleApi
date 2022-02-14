<#
    Microsoft.TeamFoundation.DistributedTask.Task.Deployment.Azure.psm1
#>

function Get-AzureCmdletsVersion
{
    $module = Get-Module AzureRM
    if($module)
    {
        return ($module).Version
    }
    return (Get-Module Azure).Version
}

function Get-AzureVersionComparison
{
    param
    (
        [System.Version] [Parameter(Mandatory = $true)]
        $AzureVersion,

        [System.Version] [Parameter(Mandatory = $true)]
        $CompareVersion
    )

    $result = $AzureVersion.CompareTo($CompareVersion)

    if ($result -lt 0)
    {
        #AzureVersion is before CompareVersion
        return $false 
    }
    else
    {
        return $true
    }
}

function Set-CurrentAzureSubscription
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $azureSubscriptionId,
        
        [String] [Parameter(Mandatory = $false)]  #publishing websites doesn't require a StorageAccount
        $storageAccount
    )

    if (Get-SelectNotRequiringDefault)
    {                
        Write-Host "Select-AzureSubscription -SubscriptionId $azureSubscriptionId"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureSubscription -SubscriptionId $azureSubscriptionId        
    }
    else
    {
        Write-Host "Select-AzureSubscription -SubscriptionId $azureSubscriptionId -Default"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureSubscription -SubscriptionId $azureSubscriptionId -Default
    }
    
    if ($storageAccount)
    {
        Write-Host "Set-AzureSubscription -SubscriptionId $azureSubscriptionId -CurrentStorageAccountName $storageAccount"
        Set-AzureSubscription -SubscriptionId $azureSubscriptionId -CurrentStorageAccountName $storageAccount
    }
}

function Set-CurrentAzureRMSubscription
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $azureSubscriptionId,
        
        [String]
        $tenantId
    )

    if([String]::IsNullOrWhiteSpace($tenantId))
    {
        Write-Host "Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId
    }
    else
    {
        Write-Host "Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId -tenantId $tenantId"
        # Assign return value to $newSubscription so it isn't implicitly returned by the function
        $newSubscription = Select-AzureRMSubscription -SubscriptionId $azureSubscriptionId -tenantId $tenantId
    }
}

function Get-SelectNotRequiringDefault
{
    $azureVersion = Get-AzureCmdletsVersion

    #0.8.15 make the Default parameter for Select-AzureSubscription optional
    $versionRequiring = New-Object -TypeName System.Version -ArgumentList "0.8.15"

    $result = Get-AzureVersionComparison -AzureVersion $azureVersion -CompareVersion $versionRequiring

    return $result
}

function Get-RequiresEnvironmentParameter
{
    $azureVersion = Get-AzureCmdletsVersion

    #0.8.8 requires the Environment parameter for Set-AzureSubscription
    $versionRequiring = New-Object -TypeName System.Version -ArgumentList "0.8.8"

    $result = Get-AzureVersionComparison -AzureVersion $azureVersion -CompareVersion $versionRequiring

    return $result
}

function Set-UserAgent
{
    if ($env:AZURE_HTTP_USER_AGENT)
    {
        try
        {
            [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent($UserAgent)
        }
        catch
        {
        Write-Verbose "Set-UserAgent failed with exception message: $_.Exception.Message"
        }
    }
}

function Initialize-AzureSubscription 
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $ConnectedServiceName,

        [String] [Parameter(Mandatory = $false)]  #publishing websites doesn't require a StorageAccount
        $StorageAccount
    )

    Import-Module "Microsoft.TeamFoundation.DistributedTask.Task.Internal"

    Write-Host ""
    Write-Host "Get-ServiceEndpoint -Name $ConnectedServiceName -Context $distributedTaskContext"
    $serviceEndpoint = Get-ServiceEndpoint -Name "$ConnectedServiceName" -Context $distributedTaskContext
    if ($serviceEndpoint -eq $null)
    {
        throw "A Connected Service with name '$ConnectedServiceName' could not be found.  Ensure that this Connected Service was successfully provisioned using services tab in Admin UI."
    }

    $x509Cert = $null
    if ($serviceEndpoint.Authorization.Scheme -eq 'Certificate')
    {
        $subscription = $serviceEndpoint.Data.SubscriptionName
        Write-Host "subscription= $subscription"

        Write-Host "Get-X509Certificate -CredentialsXml <xml>"
        $x509Cert = Get-X509Certificate -ManagementCertificate $serviceEndpoint.Authorization.Parameters.Certificate
        if (!$x509Cert)
        {
            throw "There was an error with the Azure management certificate used for deployment."
        }

        $azureSubscriptionId = $serviceEndpoint.Data.SubscriptionId
        $azureSubscriptionName = $serviceEndpoint.Data.SubscriptionName
        $azureServiceEndpoint = $serviceEndpoint.Url

		$EnvironmentName = "AzureCloud"
		if( $serviceEndpoint.Data.Environment )
        {
            $EnvironmentName = $serviceEndpoint.Data.Environment
        }

        Write-Host "azureSubscriptionId= $azureSubscriptionId"
        Write-Host "azureSubscriptionName= $azureSubscriptionName"
        Write-Host "azureServiceEndpoint= $azureServiceEndpoint"
    }
    elseif ($serviceEndpoint.Authorization.Scheme -eq 'UserNamePassword')
    {
        $username = $serviceEndpoint.Authorization.Parameters.UserName
        $password = $serviceEndpoint.Authorization.Parameters.Password
        $azureSubscriptionId = $serviceEndpoint.Data.SubscriptionId
        $azureSubscriptionName = $serviceEndpoint.Data.SubscriptionName

        Write-Host "Username= $username"
        Write-Host "azureSubscriptionId= $azureSubscriptionId"
        Write-Host "azureSubscriptionName= $azureSubscriptionName"

        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $psCredential = New-Object System.Management.Automation.PSCredential ($username, $securePassword)
        
        if(Get-Module Azure)
        {
             Write-Host "Add-AzureAccount -Credential `$psCredential"
             $azureAccount = Add-AzureAccount -Credential $psCredential
        }

        if(Get-module -Name Azurerm.profile -ListAvailable)
        {
             Write-Host "Add-AzureRMAccount -Credential `$psCredential"
             $azureRMAccount = Add-AzureRMAccount -Credential $psCredential
        }

        if (!$azureAccount -and !$azureRMAccount)
        {
            throw "There was an error with the Azure credentials used for deployment."
        }

        if($azureAccount)
        {
            Set-CurrentAzureSubscription -azureSubscriptionId $azureSubscriptionId -storageAccount $StorageAccount
        }

        if($azureRMAccount)
        {
            Set-CurrentAzureRMSubscription -azureSubscriptionId $azureSubscriptionId
        }
    }
    elseif ($serviceEndpoint.Authorization.Scheme -eq 'ServicePrincipal')
    {
        $servicePrincipalId = $serviceEndpoint.Authorization.Parameters.ServicePrincipalId
        $servicePrincipalKey = $serviceEndpoint.Authorization.Parameters.ServicePrincipalKey
        $tenantId = $serviceEndpoint.Authorization.Parameters.TenantId
        $azureSubscriptionId = $serviceEndpoint.Data.SubscriptionId
        $azureSubscriptionName = $serviceEndpoint.Data.SubscriptionName

        Write-Host "tenantId= $tenantId"
        Write-Host "azureSubscriptionId= $azureSubscriptionId"
        Write-Host "azureSubscriptionName= $azureSubscriptionName"

        $securePassword = ConvertTo-SecureString $servicePrincipalKey -AsPlainText -Force
        $psCredential = New-Object System.Management.Automation.PSCredential ($servicePrincipalId, $securePassword)

        $currentVersion =  Get-AzureCmdletsVersion
        $minimumAzureVersion = New-Object System.Version(0, 9, 9)
        $isPostARMCmdlet = Get-AzureVersionComparison -AzureVersion $currentVersion -CompareVersion $minimumAzureVersion

        if($isPostARMCmdlet)
        {
             if(!(Get-module -Name Azurerm.profile -ListAvailable))
             {
                  throw "AzureRM Powershell module is not found. SPN based authentication is failed."
             }

             Write-Host "Add-AzureRMAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential"
             $azureRMAccount = Add-AzureRMAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential 
        }
        else
        {
             Write-Host "Add-AzureAccount -ServicePrincipal -Tenant `$tenantId -Credential `$psCredential"
             $azureAccount = Add-AzureAccount -ServicePrincipal -Tenant $tenantId -Credential $psCredential
        }

        if (!$azureAccount -and !$azureRMAccount)
        {
            throw "There was an error with the service principal used for deployment."
        }

        if($azureAccount)
        {
            Set-CurrentAzureSubscription -azureSubscriptionId $azureSubscriptionId -storageAccount $StorageAccount
        }

        if($azureRMAccount)
        {
            Set-CurrentAzureRMSubscription -azureSubscriptionId $azureSubscriptionId -tenantId $tenantId
        }
    }
    else
    {
        throw "Unsupported authorization scheme for azure endpoint = " + $serviceEndpoint.Authorization.Scheme
    }

    if ($x509Cert)
    {
        if(!(Get-Module Azure))
        {
             throw "Azure Powershell module is not found. Certificate based authentication is failed."
        }

        if (Get-RequiresEnvironmentParameter)
        {
            if ($StorageAccount)
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -CurrentStorageAccountName $StorageAccount -Environment $EnvironmentName"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -CurrentStorageAccountName $StorageAccount -Environment $EnvironmentName
            }
            else
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -Environment $EnvironmentName"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -Environment $EnvironmentName
            }
        }
        else
        {
            if ($StorageAccount)
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -ServiceEndpoint $azureServiceEndpoint -CurrentStorageAccountName $StorageAccount"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -ServiceEndpoint $azureServiceEndpoint -CurrentStorageAccountName $StorageAccount
            }
            else
            {
                Write-Host "Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate <cert> -ServiceEndpoint $azureServiceEndpoint"
                Set-AzureSubscription -SubscriptionName $azureSubscriptionName -SubscriptionId $azureSubscriptionId -Certificate $x509Cert -ServiceEndpoint $azureServiceEndpoint
            }
        }

        Set-CurrentAzureSubscription -azureSubscriptionId $azureSubscriptionId -storageAccount $StorageAccount
    }
}

function Get-AzureModuleLocation
{
    #Locations are from Web Platform Installer
    $azureModuleFolder = ""
    $azureX86Location = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Azure.psd1"
    $azureLocation = "${env:ProgramFiles}\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Azure.psd1"

    if (Test-Path($azureX86Location))
    {
        $azureModuleFolder = $azureX86Location
    }
     
    elseif (Test-Path($azureLocation))
    {
        $azureModuleFolder = $azureLocation
    }

    $azureModuleFolder
}

function Import-AzurePowerShellModule
{
    # Try this to ensure the module is actually loaded...
    $moduleLoaded = $false
    $azureFolder = Get-AzureModuleLocation

    if(![string]::IsNullOrEmpty($azureFolder))
    {
        Write-Host "Looking for Azure PowerShell module at $azureFolder"
        Import-Module -Name $azureFolder -Global:$true
        $moduleLoaded = $true
    }
    else
    {
        if(Get-Module -Name "Azure" -ListAvailable)
        {
            Write-Host "Importing Azure Powershell module."
            Import-Module "Azure"
            $moduleLoaded = $true
        }

        if(Get-Module -Name "AzureRM" -ListAvailable)
        {
            Write-Host "Importing AzureRM Powershell module."
            Import-Module "AzureRM"
            $moduleLoaded = $true
        }
    }

    if(!$moduleLoaded)
    {
         throw "Windows Azure Powershell (Azure.psd1) and Windows AzureRM Powershell (AzureRM.psd1) modules are not found. Retry after restart of VSO Agent service, if modules are recently installed."
    }
}

function Initialize-AzurePowerShellSupport
{
    param
    (
        [String] [Parameter(Mandatory = $true)]
        $ConnectedServiceName,

        [String] [Parameter(Mandatory = $false)]  #publishing websites doesn't require a StorageAccount
        $StorageAccount
    )

    #Ensure we can call the Azure module/cmdlets
    Import-AzurePowerShellModule

    $minimumAzureVersion = "0.8.10.1"
    $minimumRequiredAzurePSCmdletVersion = New-Object -TypeName System.Version -ArgumentList $minimumAzureVersion
    $installedAzureVersion = Get-AzureCmdletsVersion
    Write-Host "AzurePSCmdletsVersion= $installedAzureVersion"

    $result = Get-AzureVersionComparison -AzureVersion $installedAzureVersion -CompareVersion $minimumRequiredAzurePSCmdletVersion
    if (!$result)
    {
        throw "The required minimum version ($minimumAzureVersion) of the Azure Powershell Cmdlets are not installed."
    }

    # Set UserAgent for Azure
    Set-UserAgent

    # Intialize the Azure subscription based on the passed in values
    Initialize-AzureSubscription -ConnectedServiceName $ConnectedServiceName -StorageAccount $StorageAccount
}
# SIG # Begin signature block
# MIInugYJKoZIhvcNAQcCoIInqzCCJ6cCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCAjLHErWkQVhiJ
# h63kfMHLxaqf1YYraTQRHNVPTTxRuqCCDYEwggX/MIID56ADAgECAhMzAAACUosz
# qviV8znbAAAAAAJSMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjEwOTAyMTgzMjU5WhcNMjIwOTAxMTgzMjU5WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQDQ5M+Ps/X7BNuv5B/0I6uoDwj0NJOo1KrVQqO7ggRXccklyTrWL4xMShjIou2I
# sbYnF67wXzVAq5Om4oe+LfzSDOzjcb6ms00gBo0OQaqwQ1BijyJ7NvDf80I1fW9O
# L76Kt0Wpc2zrGhzcHdb7upPrvxvSNNUvxK3sgw7YTt31410vpEp8yfBEl/hd8ZzA
# v47DCgJ5j1zm295s1RVZHNp6MoiQFVOECm4AwK2l28i+YER1JO4IplTH44uvzX9o
# RnJHaMvWzZEpozPy4jNO2DDqbcNs4zh7AWMhE1PWFVA+CHI/En5nASvCvLmuR/t8
# q4bc8XR8QIZJQSp+2U6m2ldNAgMBAAGjggF+MIIBejAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQUNZJaEUGL2Guwt7ZOAu4efEYXedEw
# UAYDVR0RBEkwR6RFMEMxKTAnBgNVBAsTIE1pY3Jvc29mdCBPcGVyYXRpb25zIFB1
# ZXJ0byBSaWNvMRYwFAYDVQQFEw0yMzAwMTIrNDY3NTk3MB8GA1UdIwQYMBaAFEhu
# ZOVQBdOCqhc3NyK1bajKdQKVMFQGA1UdHwRNMEswSaBHoEWGQ2h0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY0NvZFNpZ1BDQTIwMTFfMjAxMS0w
# Ny0wOC5jcmwwYQYIKwYBBQUHAQEEVTBTMFEGCCsGAQUFBzAChkVodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY0NvZFNpZ1BDQTIwMTFfMjAx
# MS0wNy0wOC5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEAFkk3
# uSxkTEBh1NtAl7BivIEsAWdgX1qZ+EdZMYbQKasY6IhSLXRMxF1B3OKdR9K/kccp
# kvNcGl8D7YyYS4mhCUMBR+VLrg3f8PUj38A9V5aiY2/Jok7WZFOAmjPRNNGnyeg7
# l0lTiThFqE+2aOs6+heegqAdelGgNJKRHLWRuhGKuLIw5lkgx9Ky+QvZrn/Ddi8u
# TIgWKp+MGG8xY6PBvvjgt9jQShlnPrZ3UY8Bvwy6rynhXBaV0V0TTL0gEx7eh/K1
# o8Miaru6s/7FyqOLeUS4vTHh9TgBL5DtxCYurXbSBVtL1Fj44+Od/6cmC9mmvrti
# yG709Y3Rd3YdJj2f3GJq7Y7KdWq0QYhatKhBeg4fxjhg0yut2g6aM1mxjNPrE48z
# 6HWCNGu9gMK5ZudldRw4a45Z06Aoktof0CqOyTErvq0YjoE4Xpa0+87T/PVUXNqf
# 7Y+qSU7+9LtLQuMYR4w3cSPjuNusvLf9gBnch5RqM7kaDtYWDgLyB42EfsxeMqwK
# WwA+TVi0HrWRqfSx2olbE56hJcEkMjOSKz3sRuupFCX3UroyYf52L+2iVTrda8XW
# esPG62Mnn3T8AuLfzeJFuAbfOSERx7IFZO92UPoXE1uEjL5skl1yTZB3MubgOA4F
# 8KoRNhviFAEST+nG8c8uIsbZeb08SeYQMqjVEmkwggd6MIIFYqADAgECAgphDpDS
# AAAAAAADMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0
# ZSBBdXRob3JpdHkgMjAxMTAeFw0xMTA3MDgyMDU5MDlaFw0yNjA3MDgyMTA5MDla
# MH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMT
# H01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTEwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQCr8PpyEBwurdhuqoIQTTS68rZYIZ9CGypr6VpQqrgG
# OBoESbp/wwwe3TdrxhLYC/A4wpkGsMg51QEUMULTiQ15ZId+lGAkbK+eSZzpaF7S
# 35tTsgosw6/ZqSuuegmv15ZZymAaBelmdugyUiYSL+erCFDPs0S3XdjELgN1q2jz
# y23zOlyhFvRGuuA4ZKxuZDV4pqBjDy3TQJP4494HDdVceaVJKecNvqATd76UPe/7
# 4ytaEB9NViiienLgEjq3SV7Y7e1DkYPZe7J7hhvZPrGMXeiJT4Qa8qEvWeSQOy2u
# M1jFtz7+MtOzAz2xsq+SOH7SnYAs9U5WkSE1JcM5bmR/U7qcD60ZI4TL9LoDho33
# X/DQUr+MlIe8wCF0JV8YKLbMJyg4JZg5SjbPfLGSrhwjp6lm7GEfauEoSZ1fiOIl
# XdMhSz5SxLVXPyQD8NF6Wy/VI+NwXQ9RRnez+ADhvKwCgl/bwBWzvRvUVUvnOaEP
# 6SNJvBi4RHxF5MHDcnrgcuck379GmcXvwhxX24ON7E1JMKerjt/sW5+v/N2wZuLB
# l4F77dbtS+dJKacTKKanfWeA5opieF+yL4TXV5xcv3coKPHtbcMojyyPQDdPweGF
# RInECUzF1KVDL3SV9274eCBYLBNdYJWaPk8zhNqwiBfenk70lrC8RqBsmNLg1oiM
# CwIDAQABo4IB7TCCAekwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFEhuZOVQ
# BdOCqhc3NyK1bajKdQKVMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1Ud
# DwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO
# 4eqnxzHRI4k0MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWljcm9zb2Z0
# LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcmwwXgYIKwYBBQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dDIwMTFfMjAxMV8wM18y
# Mi5jcnQwgZ8GA1UdIASBlzCBlDCBkQYJKwYBBAGCNy4DMIGDMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2RvY3MvcHJpbWFyeWNw
# cy5odG0wQAYIKwYBBQUHAgIwNB4yIB0ATABlAGcAYQBsAF8AcABvAGwAaQBjAHkA
# XwBzAHQAYQB0AGUAbQBlAG4AdAAuIB0wDQYJKoZIhvcNAQELBQADggIBAGfyhqWY
# 4FR5Gi7T2HRnIpsLlhHhY5KZQpZ90nkMkMFlXy4sPvjDctFtg/6+P+gKyju/R6mj
# 82nbY78iNaWXXWWEkH2LRlBV2AySfNIaSxzzPEKLUtCw/WvjPgcuKZvmPRul1LUd
# d5Q54ulkyUQ9eHoj8xN9ppB0g430yyYCRirCihC7pKkFDJvtaPpoLpWgKj8qa1hJ
# Yx8JaW5amJbkg/TAj/NGK978O9C9Ne9uJa7lryft0N3zDq+ZKJeYTQ49C/IIidYf
# wzIY4vDFLc5bnrRJOQrGCsLGra7lstnbFYhRRVg4MnEnGn+x9Cf43iw6IGmYslmJ
# aG5vp7d0w0AFBqYBKig+gj8TTWYLwLNN9eGPfxxvFX1Fp3blQCplo8NdUmKGwx1j
# NpeG39rz+PIWoZon4c2ll9DuXWNB41sHnIc+BncG0QaxdR8UvmFhtfDcxhsEvt9B
# xw4o7t5lL+yX9qFcltgA1qFGvVnzl6UJS0gQmYAf0AApxbGbpT9Fdx41xtKiop96
# eiL6SJUfq/tHI4D1nvi/a7dLl+LrdXga7Oo3mXkYS//WsyNodeav+vyL6wuA6mk7
# r/ww7QRMjt/fdW1jkT3RnVZOT7+AVyKheBEyIXrvQQqxP/uozKRdwaGIm1dxVk5I
# RcBCyZt2WwqASGv9eZ/BvW1taslScxMNelDNMYIZjzCCGYsCAQEwgZUwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMQITMwAAAlKLM6r4lfM52wAAAAACUjAN
# BglghkgBZQMEAgEFAKCBrjAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgor
# BgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgAdp1GtVJ
# YU6rgcrIIARGNB/NYA5cbqqQNL4WNDcVFa0wQgYKKwYBBAGCNwIBDDE0MDKgFIAS
# AE0AaQBjAHIAbwBzAG8AZgB0oRqAGGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbTAN
# BgkqhkiG9w0BAQEFAASCAQC5Xx7Y1f6wkLRGYnfAxaMX4/z60yQbTRqaZpBGOMCb
# 0RNbgQclSlQ0O091skUNG3L18zsrF5ZGAnGJ6WxrCBLZY7DrOErNuAnjaQ3IaZCr
# 7t/n1SW2Plx2nNJ6VPSwk/xA2myNegccD8IdE1pjQSDFRYKgb+M4m5z8tGrRjmke
# BNkvAR1S8BcNXQSh19bPJuqVLEfONukHdqFf3UJ2+QkS9OHWlknL++iA8iqkksg9
# +51KKDghCRpeEJv5P7UE88jVNRTxXp18IFzJXH0qAOAkAH212VgRxvXkuCmUtKBc
# O+6ONe6t6RwSTSWOnQkTSwC5YeqQ/nJNI1JXT/gzjghCoYIXGTCCFxUGCisGAQQB
# gjcDAwExghcFMIIXAQYJKoZIhvcNAQcCoIIW8jCCFu4CAQMxDzANBglghkgBZQME
# AgEFADCCAVkGCyqGSIb3DQEJEAEEoIIBSASCAUQwggFAAgEBBgorBgEEAYRZCgMB
# MDEwDQYJYIZIAWUDBAIBBQAEINsQx0dmXIofz73ELRYMR4DXF7Uxzt0Xm1Ggh0Rf
# bazwAgZh8yjr2QMYEzIwMjIwMjAzMTQyMjA0LjYzOVowBIACAfSggdikgdUwgdIx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhh
# bGVzIFRTUyBFU046MDg0Mi00QkU2LUMyOUExJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghFoMIIHFDCCBPygAwIBAgITMwAAAYdCFmYEXPP0
# jQABAAABhzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yMTEwMjgxOTI3MzlaFw0yMzAxMjYxOTI3MzlaMIHSMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQg
# SXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJjAkBgNVBAsTHVRoYWxlcyBUU1Mg
# RVNOOjA4NDItNEJFNi1DMjlBMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAvml4GWM9
# A6PREQiHgZAAPK6n+Th6m+LYwKYLaQFlZXbTqrodhsni7HVIRkqBFuG8og1KZry0
# 2xEmmbdp89O40xCIQfW8FKW7oO/lYYtUAQW2kp0uMuYEJ1XkZ6eHjcMuqEJwC47U
# akZx3AekakP+GfGuDDO9kZGQRe8IpiiJ4Qkn6mbDhbRpgcUOdsDzmNz6kXG7gfIf
# gcs5kzuKIP6nN4tsjPhyF58VU0ZfI0PSC+n5OX0hsU8heWe3pUiDr5gqP16a6kIj
# FJHkgNPYgMivGTQKcjNxNcXnnymT/JVuNs7Zvk1P5KWf8G1XG/MtZZ5/juqsg0Qo
# UmQZjVh0XRku7YpMpktW7XfFA3y+YJOG1pVzizB3PzJXUC8Ma8AUywtUuULWjYT5
# y7/EwwHWmn1RT0PhYp9kmpfS6HIYfEBboYUvULW2HnGNfx65f4Ukc7kgNSQbeAH6
# yjO5dg6MUwPfzo/rBdNaZfJxZ7RscTByTtlxblfUT46yPHCXACiX/BhaHEY4edFg
# p/cIb7XHFJbu4mNDAPzRlAkIj1SGuO9G4sbkjM9XpNMWglj2dC9QLN/0geBFXoNI
# 8F+HfHw4Jo+p6iSP8hn43mkkWKSGOiT4hLJzocErFntK5i9PebXSq2BvMgzVc+BB
# vCN35DfD0mokRKxam2tQM060SORy3S7ucesCAwEAAaOCATYwggEyMB0GA1UdDgQW
# BBQiUcAWukEtYYF+3WFzmZA/DaWNIDAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3Rh
# bXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMA0GCSqGSIb3DQEBCwUAA4ICAQC5q35T2RKjAFRN/3cYjnPFztPa
# 7KeqJKJnKgviUj9IMfC8/FQ2ox6Uwyd40TS7zKvtuMl11FFlfWkEncN3lqihiSAq
# IDPOdVvr1oJY4NFQBOHzLpetepHnMg0UL2UXHzvjKg24VOIzb0dtdP69+QIy7SDp
# cVh9KI0EXKG2bolpBypqRttGTDd0JQkOtMdiSpaDpOHwgCMNXE8xIu48hiuT075o
# IqnHJha378/DpugI0DZjYcZH1cG84J06ucq5ygrod9szr19ObCZJdJLpyvJWCy8P
# RDAkRjPJglSmfn2UR0KvnoyCOzjszAwNCp/JJnkRp20weItzm97iNg+FZF1J9E16
# eWIB1sCr7Vj9QD6Kt+z81rOcLRfxhlO2/sK09Uw+DiQkPbu6OZ3TsDvLsr8yG9W2
# A8yXcggNqd4XpLtdEkf52OIN0GgRLSY1LNDB4IKY+Zj34IwMbDbs2sCig5Li2ILW
# EMV/6gyL37J71NbW7Vzo7fcGrNne9OqxgFC2WX5degxyJ3Sx2bKw6lbf04KaXnTB
# OSz0QC+RfJuz8nOpIf28+WmMPicX2l7gs/MrC5anmyK/nbeKkaOx+AXhwYLzETNg
# +1IcygjdwnbqWKafLdCNKfhsb/gM5SFbgD5ATEX1bAxwUFVxKvQv0dIRAm5aDjF3
# DZpgvy3mSojSrBN/8zCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUw
# DQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1dGhv
# cml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg
# 4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aO
# RmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41
# JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5
# LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL
# 64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9
# QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj
# 0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqE
# UUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0
# kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435
# UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB
# 3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTE
# mr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwG
# A1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNV
# HSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNV
# HQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo
# 0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29m
# dC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5j
# cmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDAN
# BgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4
# sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th54
# 2DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRX
# ud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBew
# VIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0
# DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+Cljd
# QDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFr
# DZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFh
# bHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7n
# tdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+
# oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6Fw
# ZvKhggLXMIICQAIBATCCAQChgdikgdUwgdIxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046MDg0Mi00QkU2
# LUMyOUExJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoB
# ATAHBgUrDgMCGgMVAHh3k1QEKAZEhsLGYGHtf/6DG4PzoIGDMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQEFBQACBQDlpjjaMCIY
# DzIwMjIwMjAzMTkxOTU0WhgPMjAyMjAyMDQxOTE5NTRaMHcwPQYKKwYBBAGEWQoE
# ATEvMC0wCgIFAOWmONoCAQAwCgIBAAICDDcCAf8wBwIBAAICEUcwCgIFAOWniloC
# AQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEK
# MAgCAQACAwGGoDANBgkqhkiG9w0BAQUFAAOBgQBXqKFNZF3bJaJFZLfrRqEfsBAC
# mrTSZdunXd+46gGiKItBLdcKx+3gNxD+TzLBt4KEvGC8vwBrq/7nIqyq0SpsZAWs
# Fs8YqiARmOYV89579Hhsr6xJKRpjs+UBx5on37Wydj30tG+O9RSAs5Bc4pahRCIk
# XDQWlXI2IQVp8vb/xzGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQSAyMDEwAhMzAAABh0IWZgRc8/SNAAEAAAGHMA0GCWCGSAFlAwQCAQUAoIIB
# SjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIO/C
# iA0iP8LK2m7huJL7YS+TNopO/0YxcEi1cCI8Ce0zMIH6BgsqhkiG9w0BCRACLzGB
# 6jCB5zCB5DCBvQQgxCzwoBNuoB92wsC2SxZhz4HVGyvCZnwYNuczpGyam1gwgZgw
# gYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAYdCFmYEXPP0
# jQABAAABhzAiBCBg/cX2uGk3bAlqwaqAvUpzhRpLO7ozB7sk4emS2sAL1DANBgkq
# hkiG9w0BAQsFAASCAgC4Qj8uSqx7CitUqiZHgQ5hwyN47wu4b2ahh97o4NA2AZ1T
# 2xhHadE2FkGs7drCTRkPwWZDyNx6KjRRoIAAb8rT5eOKyQ4MtdK7W+HJ52Fn2CuL
# Epz3BAEDrwbAV8PCkn2JOFnsU1G339L3SzLMO2JEJ7YxK9cGktbGRA4iRunLMftV
# dhg0lHgoboVHm6Woc/r6+BV4sPN44vUJtJF3e+Urx+h97p/RKfyUab4FFqInxrdH
# P5doS9tbCiS/0l6ZAIlG+eRS/iJ2mJVkQEZBunuAM5Gy4+Kusu866XxBqP+2xEMG
# 6goDEKAVE00y4MBIi7uMC4cLc5emW3l1UfQ9C0Gk95tTr3gdTO0+7W5wDMYGRwe/
# A9vd8v7Gbyzq+8AQoVaHM5lEyJoW/P5kIzvwoeP90yLMH0lKLvc6nJHoLwqqLD8R
# e9/mSZZp2eTK/RfliJPXSYqYkHO9W2BSxiWzARivl+E+fJNikeZ44fyRwJQrk76O
# LMyR4gBpnM/sDRBAm34pMNKgfz+2WZqUFldCYeuA2Nf8EKtk9vQkdS7mrJ0nHbgQ
# K1ylEI2cS4Cx2FWQreU/3VMJTtL/vhkuvyDPJRzm/mRqveFuredo1wgQ7IhBDC8n
# VRQqsPK3s37dpyeqypw6tS5Kx37gh/EaThVIZOfzXa9FuGbHKaNo+urREhVaiQ==
# SIG # End signature block
