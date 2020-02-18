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

if (-not $name   ) { $name = 'AZ300-AppGateway' }
if (-not $purpose) { $purpose = 'AZ300-AppGateway' }

$SubscriptionName = 'Visual Studio Enterprise'


$TemplateFile = "$pwd\azuredeploy.json"
$rgname = "$name$Attempt" # working on better OUs & Autoshutdown
#$saname = "genesyssa$Attempt"     # Lowercase required
$VM1Name = 'BackEnd01' # Windows computer name cannot be more than 15 characters long, be entirely numeric, or contain the following characters: ` ~ ! @ # $ % ^ & * ( ) = + _ [ ] { } \ | ; : . ' " , < > / ?
$VM2Name = 'BackEnd02'
$dnsLabelPrefix = "AppGateway-$(get-random -min 1000 -max 9999)".toLower()
$location = 'East US'
$adminUsername = 'Gene'
$cred = $([System.Management.Automation.PSCredential]::new('gene', $(ConvertTo-SecureString -String 'Password!101' -AsPlainText -Force)))
$WindowsOSVersion = '2019-Datacenter'

$webdeploypkg01 = "https://github.com/glaisne/AZ-300_ARMTemplates/raw/master/ApplicationGateway/WebPage01.html"
$webdeploypkg02 = "https://github.com/glaisne/AZ-300_ARMTemplates/raw/master/ApplicationGateway/WebPage02.html"
$modulesURL     = "https://github.com/glaisne/AZ-300_ARMTemplates/raw/master/ApplicationGateway/DSCConfiguration.ps1.zip"



if ($VMName.length -gt 15)
{
    Throw "VMName ($VMName) is longer than 15 characters."
}

#-----------------------------
# Functions
#-----------------------------


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
    NSGSourceIP     = $LocalIP
    adminUsername   = $adminUsername
    dnsLabelPrefix  = $dnsLabelPrefix
    webdeploypkg01  = $webdeploypkg01
    webdeploypkg02  = $webdeploypkg02
    modulesURL      = $modulesURL    
}

if ($WindowsOSVersion)
{
    $MyParams.Add('WindowsOSVersion', $WindowsOSVersion)
}

if ($MyParams['dnsLabelPrefix'] -cnotmatch '^[a-z][a-z0-9-]{1,61}[a-z0-9]$')
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


$VerbosePreference = $VP


# $CimSession = New-CimSession -Authentication Negotiate -Credential $cred -ComputerName "$dnsLabelPrefix`.eastus.cloudapp.azure.com" -SessionOption (New-CimSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck -UseSsl)
# $Class = Get-CimClass -Namespace root/Microsoft/Windows/WindowsUpdate -CimSession $cimsession -ClassName MSFT_WUOperations
# $ScanResults = Invoke-CimMethod -MethodName ScanForUpdates -Arguments @{SearchCriteria = "IsInstalled=0"} -CimClass $class -CimSession $cimSession
# $ScanResults.updates
