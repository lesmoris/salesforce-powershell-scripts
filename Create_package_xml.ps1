Param(
	[string]$sourcesDirectory = $(throw "sourcesDirectory is null!"),
	[string]$slf_api = 45.0
)

$sgp = Join-Path -Path $sourcesDirectory -ChildPath "\Tools\sfdc-generate-package\sgp.exe"

$sgpVersion = "{0} -V" -f $sgp
$sgpVersion = iex $sgpVersion
Write-Host -ForegroundColor "Green" "SGP version : $sgpVersion"

# Create package.xml
Write-Host -ForegroundColor "Green" "Creating package.xml..."	

$sgp = "{0} -s {1}\src -o {1}\src -a {2}"  -f $sgp,$sourcesDirectory,$slf_api
Invoke-Expression $sgp 
#-s $sourcesDirectory\src -o $sourcesDirectory\src -a $slf_api

