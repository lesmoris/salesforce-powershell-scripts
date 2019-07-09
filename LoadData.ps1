Param(
    [string]$dataDirectory = $(throw "dataDirectory is null!"),
    [string]$keyDirectory = $(throw "keyDirectory is null!"),
    [string]$clientId = $(throw "clientId is null!"),
    [string]$user = $(throw "user is null!"),
    [string]$url = $(throw "url is null!")
)
Write-Host "Installing SFDX"
npm install --global sfdx-cli
Write-Host "Authenticating on the org with key in $keyDirectory"
sfdx force:auth:jwt:grant -s -i $clientId -r $url -u $user -f $keyDirectory
Write-Host "Load data from $dataDirectory"
Get-ChildItem $dataDirectory -Filter *.csv | 
Foreach-Object {

    Write-Host "Loading $_"
    sfdx force:data:bulk:upsert -s $_.BaseName -f $_.FullName -i Name
}