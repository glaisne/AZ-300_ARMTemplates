<############################################################
This arm template is for a VM which is configured with 
the VMAgent and a Log Analytic. The Agent is configured
to send update inforamtion to the Log Analytic

# Extension Install reference:
# https://github.com/Azure/azure-quickstart-templates/tree/master/201-oms-extension-windows-vm


#############################################################>

param (
    [string] $name,
    [string] $purpose,
    [string] $attempt
)

#-----------------------------
# Variables
#-----------------------------

if (-not $name   ) { $name = 'AZ300-LoadBalancer' }
if (-not $purpose) { $purpose = 'AZ300-LoadBalancer' }

$SubscriptionName = 'Azure-InfraSandbox'
$SubscriptionName = 'Visual Studio Enterprise'


$TemplateFile = "$pwd\azuredeploy.json"
$rgname = "$name$Attempt" # working on better OUs & Autoshutdown
#$saname = "genesyssa$Attempt"     # Lowercase required
$VM1Name = 'LBServer1' # Windows computer name cannot be more than 15 characters long, be entirely numeric, or contain the following characters: ` ~ ! @ # $ % ^ & * ( ) = + _ [ ] { } \ | ; : . ' " , < > / ?
$VM2Name = 'LBServer2'
$dnsLabel1Prefix = "$VM1Name$(get-random -min 1000 -max 9999)".toLower()
$dnsLabel2Prefix = "$VM2Name$(get-random -min 1000 -max 9999)".toLower()
$location = 'East US'
$KeyVaultName = [string]::format("{0}{1}-kv", "$($rgname.replace('.','-').replace('_','-'))-".substring(0, [system.Math]::Min((24 - 7), $rgname.length)), $(get-random -min 1000 -max 9999))  # Must match pattern '^[a-zA-Z0-9-]{3,24}$'
$SecretName = "$($rgname.replace('.','').replace('_','-'))`-Secret"
$certificateName = "Azure-$rgname-SSCert" # SSCert = 'Self-Signed Certificate'
$adminUsername = 'Gene'
$cred = $([System.Management.Automation.PSCredential]::new('gene', $(ConvertTo-SecureString -String 'Password!101' -AsPlainText -Force)))
$WindowsOSVersion = '2019-Datacenter'


if ($keyVaultName -notmatch '^[a-zA-Z0-9-]{3,24}$' -or $keyVaultName[0] -notmatch '[a-z]')
{
    Throw "The keyVaultName does not match the pattern '^[a-zA-Z0-9-]{3,24}$' or does not start with a letter"
}

if ($SecretName -notmatch '^[0-9a-zA-Z-]+$')
{
    throw "The secretname '$SecretName' is not valid and does not match the pattern '^[0-9a-zA-Z-]+$'."
}

if ($VMName.length -gt 15)
{
    Throw "VMName ($VMName) is longer than 15 characters."
}

#-----------------------------
# Functions
#-----------------------------

function GetPSSession
{
    param (
        [parameter(mandatory)]
        [string] $IPAddress,

        # Specify credentials for this CmdLet
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty
    )
    $trycount = 0
    $Connected = $false
    While ($Trycount -lt 20 -and $connected -eq $False)
    {
        # Destroy the old!
        get-pssession -ea 0 |? {$_.ComputerName -eq $IPAddress} | Remove-PSSession -ea 0

        if ($TryCount -gt 0)
        {
            Get-pssession |ft -auto
        }

        if ($TryCount -gt 5)
        {
            Write-Verbose "[$(Get-Date -format G)] $($TryCount.ToString('0000')) Removing all PSSessions"
            get-pssession -ea 0 | Remove-PSSession -ea 0
        }


        Write-Verbose "[$(Get-Date -format G)] $($TryCount.ToString('0000')) Attempting to get PS Session to $IP"
    
        # This was moved from teh script to a function. Bad code... no biscuit!
        # if (-not (get-variable sessionCred -Scope Global -EA 'SilentlyContinue'))
        # {
        #     $Global:sessionCred = get-Credential ~\gene
        # }
    
        try
        {
            $Session = new-pssession -ConnectionUri "https://$IPAddress`:5986" -credential $Credential -SessionOption (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck) -Authentication Negotiate -ErrorAction Stop
            $Connected = $True
        }
        catch
        {
            $err = $_
            Write-warning "Failed to get sesion: $($Err.Exception.Message)"
            Start-sleep -s 20
        }
        $trycount++
    }

    $Session
}

function GetMyIp()
{
    # Get local IP Address
    $url = "http://checkip.dyndns.com"
    $r = Invoke-WebRequest $url
    $r.ParsedHtml.getElementsByTagName("body")[0].innertext.trim().split(' ')[-1]
}


#-----------------------------
# Main
#-----------------------------


#
#    Setup Azure Environment
#


# Import AzureRM modules for the given version manifest in the AzureRM module
if (-not $(get-module AzureRm))
{
    Import-Module AzureRm -Verbose
}

# Authenticate to your Azure account
# Login-AzureRmAccount

try
{
    Select-AzureRmSubscription -SubscriptionName $SubscriptionName -ErrorAction 'Stop'
}
catch 
{
    $err = $_
    If ($err.Exception.Message -like "*Please provide a valid tenant or a valid subscription*")
    {
        Write-Warning "The Subscription Name ($SubscriptionName) may not be valid."
        throw $err
    }
    else
    {
        throw $err
    }
}


# Create the new resource group.
if (-not [string]::isnullorempty($purpose))
{
    New-AzureRmResourceGroup -Name $rgname -Location $Location -Verbose -Tag @{purpose = $purpose }
}
else
{
    New-AzureRmResourceGroup -Name $rgname -Location $Location -Verbose 
}

# Create a Key Vault
$NewVault = New-AzureRmKeyVault -VaultName $KeyVaultName -ResourceGroupName $rgname -Location $location -EnabledForDeployment -EnabledForTemplateDeployment

Write-Warning "[$(Get-Date -format G)] message"


#
#    Create Certificate
#


# Create a self-signed certificate to add to the Key Vault
$certificatefilePath = "$env:temp\$certificateName_$(get-date -f 'MMddyyyyHHmmss')$Attempt.pfx"
$thumbprint = (New-SelfSignedCertificate -DnsName $certificateName -CertStoreLocation Cert:\CurrentUser\My -KeySpec KeyExchange).Thumbprint
$cert = (Get-ChildItem -Path cert:\CurrentUser\My\$thumbprint)
$password = $cred.Password

# $password = Read-Host -Prompt "Please enter the certificate password." -AsSecureString
Export-PfxCertificate -Cert $cert -FilePath $certificatefilePath -Password $password -Force

# Upload the self-signed certificate to the Key Vault
$fileContentBytes = Get-Content $certificatefilePath -Encoding Byte
$fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)

$jsonObject = @"
{
  "data": "$filecontentencoded",
  "dataType" :"pfx",
  "password": "$($cred.GetNetworkCredential().Password)"
}
"@

$jsonObjectBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonObject)
$jsonEncoded = [System.Convert]::ToBase64String($jsonObjectBytes)

# Add the secret to the KeyVault
$secret = ConvertTo-SecureString -String $jsonEncoded -AsPlainText -Force
$newSecret = Set-AzureKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -SecretValue $secret



#
#    Setup Arm Template
#


# Get local public IP Address
$LocalIP = GetMyIp

# Parameters for the template and configuration
$MyParams = @{
    # storageAccount_name = $saname
    location        = $location
    VM1Name         = $VM1Name
    VM2Name         = $VM2Name
    CertificateUrl  = $newSecret.id
    KeyVaultName    = $KeyVaultName
    NSGSourceIP     = $LocalIP
    adminUsername   = $adminUsername
    dnsLabel1Prefix = $dnsLabel1Prefix
    dnsLabel2Prefix = $dnsLabel2Prefix
}

if ($WindowsOSVersion)
{
    $MyParams.Add('WindowsOSVersion', $WindowsOSVersion)
}

if ($MyParams['dnsLabel1Prefix'] -cnotmatch '^[a-z][a-z0-9-]{1,61}[a-z0-9]$')
{
    Throw 'dnsLabelPrefix does not match "^[a-z][a-z0-9-]{1,61}[a-z0-9]$"'
}

if ($MyParams['dnsLabel2Prefix'] -cnotmatch '^[a-z][a-z0-9-]{1,61}[a-z0-9]$')
{
    Throw 'dnsLabelPrefix does not match "^[a-z][a-z0-9-]{1,61}[a-z0-9]$"'
}

# Splat the parameters on New-AzureRmResourceGroupDeployment
$SplatParams = @{
    TemplateFile            = $TemplateFile
    ResourceGroupName       = $rgname
    TemplateParameterObject = $MyParams
    Name                    = 'Win2016VM'
    adminPassword           = $Cred.Password
}

# test first

$TestParams = $splatParams
$TestParams.Remove('Name')
# $TestParams.Remove('adminPassword')

$global:results = Test-AzureRmResourceGroupDeployment @TestParams -Verbose

$Global:results | fl * -force

# One prompt for the domain admin password
try
{
    New-AzureRmResourceGroupDeployment @SplatParams -Verbose -DeploymentDebugLogLevel All -ErrorAction Stop
}
catch
{
    throw $_
}


# Find the VM IP and FQDN
$PublicAddresses = Get-AzureRmPublicIpAddress -ResourceGroupName $rgname

foreach ($PublicAddress in $PublicAddresses)
{
    $IP = $PublicAddress.IpAddress
    $DNSFQDN = $PublicAddress.DnsSettings.Fqdn

    $VP = $VerbosePreference
    $VerbosePreference = 'Continue'

    # Get a PS Session to the VM
    $Session = GetPSSession -IPAddress $IP -credential $cred

    # Setup the DSC file environment
    Write-Verbose "[$(Get-Date -format G)] Setting up DSC files"
    invoke-command {mkdir c:\DSC} -Session $session
    Write-Verbose "[$(Get-Date -format G)] Copying DSC files to server"
    Get-ChildItem .\DSC\*.ps* | copy-item -ToSession $session -Destination c:\DSC\

    Write-Verbose "[$(Get-Date -format G)] Configuring wsman"
    invoke-command {dir WSMan:\localhost | ft -auto} -session $Session
    invoke-command {set-item wsman:\localhost\MaxEnvelopeSizekb -value 50000} -session $session

    # Downloads and installs
    # Write-Verbose "[$(Get-Date -format G)] Install DSC requirements"
    # Write-Verbose "[$(Get-Date -format G)]  - Nuget"
    # invoke-command {install-packageProvider -Name 'Nuget' -Force} -session $session
    # invoke-command {set-packagesource -Name psgallery -Trusted } -session $session

    Write-Verbose "[$(Get-Date -format G)]  - DSC"
    invoke-command {install-windowsfeature DSC-Service } -session $session
    # Write-Verbose "[$(Get-Date -format G)]  - chocolatey"
    # invoke-command {find-packageprovider chocolatey | install-packageprovider -Force} -session $Session
    # invoke-command {set-packagesource -Name chocolatey -Trusted } -session $session
    # invoke-command {set-packagesource -Name chocolatey -Trusted:$false } -session $session

    # Create the DSC MOF file
    Write-Verbose "[$(Get-Date -format G)] Create DSC MOF files"
    invoke-command  -Session $session { . c:\dsc\InstallIIs.ps1}
    invoke-command  -Session $session {InstallIIs}

    # Configure the LCM
    # See https://www.jacobbenson.io/index.php/2015/02/21/exploring-the-powershell-dsc-xpendingreboot-resource/
    Write-Verbose "[$(Get-Date -format G)] Configuring the LCM"
    invoke-command {Set-DscLocalConfigurationManager 'c:\dsc\InstallIIs\' -Verbose} -session $session

    # Start the DSC configuration
    Write-Verbose "[$(Get-Date -format G)] Start DSC Configuration"
    # It seems someimes this fails or runs successfully and doesn't do anything.
    # I think it is because the system may not see the F: drive. I'm building this loop
    # to try and solve this issue.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $TryCount = 0
    While ($sw.Elapsed.totalSeconds -lt 30 -and $TryCount -le 20)
    {
        $sw.Reset()
        $sw.Start()
        invoke-command {Start-DscConfiguration -Path 'c:\dsc\InstallIIs\' -Wait -Verbose} -session $session
        $sw.stop()
        Start-Sleep -s 15
        $TryCount++
    }

}

$VerbosePreference = $VP


# $CimSession = New-CimSession -Authentication Negotiate -Credential $cred -ComputerName "$dnsLabelPrefix`.eastus.cloudapp.azure.com" -SessionOption (New-CimSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck -UseSsl)
# $Class = Get-CimClass -Namespace root/Microsoft/Windows/WindowsUpdate -CimSession $cimsession -ClassName MSFT_WUOperations
# $ScanResults = Invoke-CimMethod -MethodName ScanForUpdates -Arguments @{SearchCriteria = "IsInstalled=0"} -CimClass $class -CimSession $cimSession
# $ScanResults.updates