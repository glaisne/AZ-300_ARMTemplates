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

        Script DownloadDefaultDotHtm
        {
            TestScript = {
                Test-Path "C:\inetpub\wwwroot\default.htm"
            }
            SetScript ={
                $dest = "C:\inetpub\wwwroot\default.htm"
                Invoke-WebRequest $using:WebDeployPackagePath -OutFile $dest
            }
            GetScript = {@{Result = "DownloadDefaultDotHtm"}}
            DependsOn = "[WindowsFeature]WebServerRole"
        }
    }
}
