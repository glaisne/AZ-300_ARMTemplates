Configuration DSCConfiguration
{
    param (
        $MachineName,
        $WebDeployPackagePath
    )

    Node ($MachineName)
    {
	   
        WindowsFeature WebServerRole

        {
            Name   = "Web-Server"
            Ensure = "Present"
        }

        WindowsFeature WebMgmtCompat
        {
            Name      = "Web-Mgmt-Compat"
            Ensure    = "Present"
            DependsOn = "[WindowsFeature]WebServerRole"
        }



        WindowsFeature WebMgmtTools
        {
            Name      = "Web-Mgmt-Tools"
            Ensure    = "Present"
            DependsOn = "[WindowsFeature]WebServerRole"
        }

        WindowsFeature WebMgmtConsole
        {
            Name      = "Web-Mgmt-Console"
            Ensure    = "Present"
            DependsOn = "[WindowsFeature]WebServerRole"
        }

        Script DeployWebPackage
        {
            GetScript  = {
                @{
                    Result = ""
                }
            }
            TestScript = {
                $false
            }
            SetScript  = {

                $WebClient = New-Object -TypeName System.Net.WebClient
                $Destination = "C:\WindowsAzure\WebApplication.zip" 
                $WebClient.DownloadFile($using:WebDeployPackagePath, $destination)
                $Argument = '-source:package="C:\WindowsAzure\WebApplication.zip"' + ' -dest:auto,ComputerName="localhost"' + '" -verb:sync -allowUntrusted'
                $MSDeployPath = (Get-ChildItem "HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy" | Select -Last 1).GetValue("InstallPath")
                Start-Process "$MSDeployPath\msdeploy.exe" $Argument -Verb runas
        
            }
        }
    }
}
