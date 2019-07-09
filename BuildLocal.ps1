<#
.SYNOPSIS
    "Builds" the solution and checks it
	
.DESCRIPTION
	.\BuildLocal.ps1 -sourcesDirectory <CMS_folder> -commonSourcesDirectory <COMMON_folder> -slfUserName "slf_username" -slfPassword "pass+token" -slfServerURL "slf_server/"
	
	By default, proxy is disabled. If you need to use a proxy, you have to add:
	
	-proxyIsEnabled "true" -proxyHost="proxyIP" -proxyPort="proxyPort" -proxyUser "domain_user" -proxyPassword "domain_pass"

.EXAMPLE
	.\BuildLocal.ps1 -sourcesDirectory D:\lesmoris\CMS\ -commonSourcesDirectory D:\lesmoris\Common\ -slfUserName "adminuser@vso.com.neo.ci" -slfPassword "XXXXXXXXXXXXXXXXXX" -slfServerURL "https://test.salesforce.com/" -proxyIsEnabled "true" -proxyHost "" -proxyPort "" -proxyUser "" -proxyPassword "XXXXXXXXXXX"
	
	(Replace XXXXX with the passwords...)
	
#>
Param(
	[string]$sourcesDirectory = $(throw "sourcesDirectory is null!"),
	
	#ant 
	[string]$deployTarget = "checkCodeLocal",
	
	#testing
	[string]$testsToRun,
	
	#slf parameters
	[string]$slfUserName = $(throw "slfUserName is null!"),
	[string]$slfPassword = $(throw "slfPassword is null!"),
	[string]$slfServerURL = $(throw "slfServerURL is null!"),
	[string]$slfTestlevel = "RunLocalTests",
	[string]$slfCheckOnly = "true", 
	
	#proxy 
	[string]$proxyIsEnabled = "false", 
	[string]$proxyHost,
	[string]$proxyPort,
	[string]$proxyUser,
	[string]$proxyPassword
)

try {
	& ".\Create_package_xml.ps1" -sourcesDirectory $sourcesDirectory

    Write-Host -ForegroundColor "Green" "Building code..."	
	
	$antCommand = "ant -buildfile $sourcesDirectory\build\build.xml $deployTarget -Dusername='$slfUserName' -Dpassword='$slfPassword' -DserverURL=$slfServerURL -Dtestlevel='$slfTestlevel' -DcheckOnly=$slfCheckOnly -DproxyIsEnabled=$proxyIsEnabled -DproxyHost='$proxyHost' -DproxyPort=$proxyPort -DproxyUser='$proxyUser' -DproxyPassword='$proxyPassword' "
	
	if ($deployTarget -eq "runSpecifiedTests")
	{
		$antCommand = $antCommand + " -DtestsToRun='$testsToRun' -lib lib/ant-salesforce.jar"
	}
	
	$antCommand
	
	iex $antCommand
}
catch
{
	throw
}
