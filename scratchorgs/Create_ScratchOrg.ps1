Param(
	[string]$sourcesDirectory = $(throw "sourcesDirectory is null!"),
	[string]$secureKeyFile = $(throw "secureKeyFile is null!"),
	[string]$clientId = $(throw "clientId is null!"),
	[string]$pullRequestID = $(throw "pullRequestID is null!"),
	[boolean]$runTests = 1,
	[string]$orgAlias,
	[boolean]$deleteOrgIfError = 1
)

function InstallSFDX {
	Write-Host -ForegroundColor "Green" "Installing SFDX"
	npm install --global sfdx-cli
}

function AuthenticateWithDevHub ([string]$clientId, [string]$secureKeyFile) {
	Write-Host -ForegroundColor "Green" "Authenticating on the org with secure key..."
	sfdx force:auth:jwt:grant -d -a DevHub -r https://login.salesforce.com/ -u adminuser@vso.com.neo -i $clientId -f $secureKeyFile 
}

function DeleteScratchOrgIfDuplicated([string]$pullRequestID) {
	$orgAlias = "PR_{0}" -f $pullRequestID

	Write-Host -ForegroundColor "Green" "Deleting previous ScratchOrg with alias $orgAlias (if exists)..."
	(Get-Content -path $sourcesDirectory/scratchorgs/helpers/DeleteScratchOrg.cls -Raw) -replace '<SCRATCH_ORG_NAME>', $orgAlias | Set-Content -Path $sourcesDirectory/scratchorgs/helpers/DeleteScratchOrg.cls
	$result = (sfdx force:apex:execute -f $sourcesDirectory/scratchorgs/helpers/DeleteScratchOrg.cls -u DevHub --json | ConvertFrom-Json)
}

function CreateScratchOrg ([string]$sourcesDirectory, [string]$pullRequestID) {
	$orgAlias = "PR_{0}" -f $pullRequestID

	Write-Host -ForegroundColor "Green" "Creating scratch org from json file..."
	$result = (sfdx force:org:create -f $sourcesDirectory/scratchorgs/scratch-org-def.json -d 2 -a $orgAlias --json orgName="$orgAlias" | ConvertFrom-Json)
	if ($result.status -ne 0) {
		throw $result
	}

	Write-Host "Scratch org created. Alias = $orgAlias"
	
	return $orgAlias
}

function DeploySettings ([string]$orgAlias, [string]$sourcesDirectory) {
	Write-Host -ForegroundColor "Green" "`n`nDeploying scratch org settings..."
	Rename-Item "$sourcesDirectory/src" "src__"
	New-Item -ItemType "directory" -Path $sourcesDirectory/src/main/default/settings
	Copy-Item $sourcesDirectory/scratchorgs/org_settings/*.* -Destination $sourcesDirectory/src/main/default/settings
	
	do {
		sfdx force:source:deploy -u $orgAlias -x "$sourcesDirectory/scratchorgs/org_settings.xml"
		Start-Sleep -s 2
		$result = (sfdx force:apex:execute -f $sourcesDirectory/scratchorgs/helpers/AreWorkOrdersEnabled.cls -u $orgAlias --json | ConvertFrom-Json)
		$areWorkOrdersEnabled = $result.result.logs -like "*DEBUG|WorkOrdersAreEnabled*"
		if ($areWorkOrdersEnabled -ne $true) {
			Write-Host "Org settings incorrectly deployed. Retrying..."
		}
		else {
			Write-Host "Org settings correctly deployed. Moving on..."
		}
		
	}
	while ($areWorkOrdersEnabled -ne $true)
	
	remove-item $sourcesDirectory/src/ -Recurse -Force
	Rename-Item "$sourcesDirectory/src__" "src"
}

function InstallManagedPackage ([string]$orgAlias, [string]$packageName, [string]$packageID ) {
	
	Write-Host -ForegroundColor "Green" "Installing package $packageName"
	$result = (sfdx force:package:install -u $orgAlias -r --package $packageID --json | ConvertFrom-Json)
	
	if ($result.status -ne 0) {
		throw $result
	}
	
	$installID = $result.result.Id
	
	Write-Host -ForegroundColor "Green" "InstallID = $installID"
	do {
		Start-Sleep -s 5
		$result = (sfdx force:package:install:report -u $orgAlias -i $installID --json | ConvertFrom-Json)
	}
	while($result.result.Status -eq "IN_PROGRESS") 
	
	if ($result.status -eq 1) {
		Write-Host -ForegroundColor "Red" "Error installing package $packageName"
		sfdx force:package:install:report -u $orgAlias -i $installID
	}	
	
	Write-Host "Package $packageName installed"
}

function DeployCodeAndMetadata ([string]$orgAlias, [string]$sourcesDirectory, [boolean]$runTests) {

	Write-Host -ForegroundColor "Green" "Deploying code and metadata..."
	if ($runTests) {
		Write-Host -ForegroundColor "Green" "Test execution enabled"
		$result = (sfdx force:mdapi:deploy -d $sourcesDirectory/src/ --json -u $orgAlias -l "RunLocalTests" | ConvertFrom-Json)
	}
	else {
		$result = (sfdx force:mdapi:deploy -d $sourcesDirectory/src/ --json -u $orgAlias | ConvertFrom-Json)
	}

	if ($result.result.status -ne "Queued") {
		throw $result
	}
	
	$deployID = $result.result.id
	
	Write-Host "Deploy $deployID over $orgAlias in progress..."
	
	$deployStatus = 0;
	$startedTests = $false
	
	do {
		try {
			$report = sfdx force:mdapi:deploy:report -i $deployID -u $orgAlias --json --verbose 2>&1 | ConvertFrom-Json 
		}
		catch {
			$deployStatus = 1;
			break;
		}

		if($null -eq $report -Or $deployStatus -eq 1 -or $report.result.status -eq "Failed") {
			continue
		}

		# Deployment progress block.
		if($null -ne $report.result.numberComponentsTotal -and $report.result.numberComponentsTotal -ne 0 -and $componentsRemaining -ne 0) {

			$deploymentRatio = [Math]::Ceiling(100 * ($report.result.numberComponentsDeployed / $report.result.numberComponentsTotal))
			
			$componentsRemaining = $report.result.numberComponentsTotal - $report.result.numberComponentsDeployed - $report.result.numberComponentsFailed

			# If the percentage is not yet 100%, update it.
			if($deploymentRatio -le 100) {
				Write-Host -NoNewLine "`rComponents deployed: " $report.result.numberComponentsDeployed " of " $report.result.numberComponentsTotal " : " $deploymentRatio "%"
			}

			# If the deployment has failed
			if($report.result.status -eq "Failed") {
				break
			}
		}
		
		if ($runTests) {
		
			# Write next header.
			if(($report.result.numberTestsTotal -ne 0) -and ($startedTests -eq $false)) {
				$startedTests = $true
				Write-Host -ForegroundColor green "`n`n:: Running tests ::"
			}

			# Write Test progress
			if($null -ne $report.result.numberTestsTotal -and $report.result.numberTestsTotal -ne 0 -and $testsRemaining -ne 0) {
				$testRatio = [Math]::Ceiling((100 * ($report.result.numberTestsCompleted / $report.result.numberTestsTotal)))
				$testsRemaining = $report.result.numberTestsTotal - $report.result.numberTestErrors - $report.result.numberTestsCompleted

				Write-Host -NoNewLine "`rTests passed: " $testRatio "% | Tests remaining: " $testsRemaining
			}

			if($testsRemaining -eq 0 -and $report.result.numberTestErrors -gt 0) {
				Write-Host -ForegroundColor red "`nERROR: $($report.result.numberTestErrors) tests have failed"
				exit
			}
			
		}
			
	} while(($report.result.status -eq "InProgress") -or ($report.result.status -eq "Pending"))
	
	if ($deployStatus -eq 1 -or $report.result.status -eq "Failed") {
		#Show errors
		sfdx force:mdapi:deploy:report -i $deployID -u $orgAlias
		
		throw
	}
}

function LoadData ([string]$orgAlias, [string]$sourcesDirectory) {
	Write-Host -ForegroundColor "Green" "`n`nLoading data from $sourcesDirectory/data"
	Get-ChildItem $sourcesDirectory/data -Filter *.csv | 
	Foreach-Object {
		Write-Host "Loading $_"
		$result = (sfdx force:data:bulk:upsert -s $_.BaseName -f $_.FullName -i Name -u $orgAlias --json | ConvertFrom-Json)
		
		if ($result.status -ne 0) {
			throw $result
		}
		
		$id = $result.result.id
		$jobId = $result.result.jobId
		
		while((sfdx force:data:bulk:status -u $orgAlias -i $jobId -b $id --json | ConvertFrom-Json).result.state -eq "Queued") { Start-Sleep -s 2 }
	}
}

function MigrateProvidersFromPROD ([string]$orgAlias) {
	Write-Host -ForegroundColor "Green" "`n`nDownloading providers from PROD environment..."
	$AccountRecordTypes=sfdx force:data:soql:query -q "SELECT ID FROM RecordType WHERE sObjectType='Account' AND DeveloperName = 'CMS_Provider'" -u $orgAlias --json | ConvertFrom-Json
	$OldHeader='Additional_distance__c','Call_Out__c','Currency_CMS__c','Distance_Unit__c','Included__c','Latitude__c','Longitud__c','Mobidem__c','Name','opcode__c','Phone__c','RAM__c'
	$NewHeader='Additional_Distance__c','Call_Out__c','Currency_CMS__c','Distance_Unit__c','Included__c','BillingLatitude','BillingLongitude','Mobidem__c','Name','opcode__c','Phone','RAM__c'
	$QueryableHeader=$($OldHeader | sort -Unique) -join "," 
	$providers=sfdx force:data:soql:query -q "SELECT $QueryableHeader FROM Provider__c" -u DevHub -r csv
	$providers = $providers[1..($providers.count - 1)]
	$providersObj = ConvertFrom-Csv -InputObject $providers -Header $NewHeader -Delimiter ','

	Foreach($record in $providersObj){ 
		$record = $record | Add-Member -MemberType NoteProperty -Name 'RecordTypeId' -Value $AccountRecordTypes.result.records[0].Id -PassThru
	}

	Write-Host -ForegroundColor "Green" "`n`nLoading providers to Scratch Org..."
	$providersObj | ConvertTo-Csv -Delimiter ';' -NoTypeInformation | % {$_ -replace ',',' ' -replace ';',',' -replace '"','' } | Out-File 'ReadyToInsertProv.csv' -Encoding Ascii
	$result = (sfdx force:data:bulk:upsert -s Account -f ReadyToInsertProv.csv -u $orgAlias -i Id --json | ConvertFrom-Json)

	if ($result.status -ne 0) {
		throw $result
	}
	
	$id = $result.result.id
	$jobId = $result.result.jobId
	
	while((sfdx force:data:bulk:status -u $orgAlias -i $jobId -b $id --json | ConvertFrom-Json).result.state -eq "Queued") { Start-Sleep -s 2 }
	
	Remove-Item ReadyToInsertProv.csv
}

function DeployUsers ([string]$orgAlias) {
	Write-Host -ForegroundColor "Green" "`n`nDeploying users..."
	$files = Get-ChildItem "$sourcesDirectory/scratchorgs/users/*.json"
	foreach ($file in $files) {
		sfdx force:user:create -u $orgAlias -f $file.fullname generatepassword=true
	}
}

function GeneratePassword ([string]$orgAlias) {
	Write-Host -ForegroundColor "Green" "`n`nGenerating password.."
	sfdx force:user:password:generate -u $orgAlias
	sfdx force:user:display -u $orgAlias
}

function PublishScratchOrgInfo([string]$orgAlias, [string]$pullRequestID) {
	if ($pullRequestID -ne $null -and $pullRequestID -ne "") { 
		Write-Host -ForegroundColor "Green" "`n`nPublishing Scratch Org Info in PullRequest .."
		$scratchOrgInfo = (sfdx force:user:display -u $orgAlias --json | ConvertFrom-Json)
		
		$repositoryId = "fabe1723-ecd7-48f8-a3b8-a697fc056bc8" # To be changed to Build.Repository.ID, maybe?
		$APIVersion = "5.0"
		$url = "https://dev.azure.com/aasolutions/aa_holding_customer_sales_and_service/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId/threads?api-version=$APIVersion"
		$encodedPassword = [System.Web.HttpUtility]::UrlEncode($scratchOrgInfo.result.password)
	
		$comment = "Scratch Org URL: \n https://test.salesforce.com/?un={0}&pw={1}" -f $scratchOrgInfo.result.username, $encodedPassword

		$JSONBody= @"
		{
		  "comments": [
			{
			  "parentCommentId": 0,
			  "content": "$comment",
			  "commentType": "system"
			}
		  ],
		  "status": "closed"
		}
"@

		$Response = Invoke-RestMethod -Uri $url	 `
									  -Method Post `
									  -ContentType "application/json" `
									  -Headers @{Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN"} `
									  -Body $JSONBody  
	}
}

function DeleteScratchOrg ([string]$orgAlias) {
	if ($orgAlias -ne "" -and $deleteOrgIfError) {
		Write-Host -ForegroundColor "Red" "`nDeleting Scratch Org..."
		sfdx force:org:delete -p -u $orgAlias 
	}
}

try {

	InstallSFDX	
	AuthenticateWithDevHub $clientId $secureKeyFile 
	if ($orgAlias -eq $null -or $orgAlias -eq "") { 
		DeleteScratchOrgIfDuplicated $pullRequestID
		$orgAlias = CreateScratchOrg $sourcesDirectory $pullRequestID
	}
	DeploySettings $orgAlias $sourcesDirectory 
	InstallManagedPackage $orgAlias "TimbaSurveys" '04t700000007ySvAAI'
	InstallManagedPackage $orgAlias "SmartCOMM" '04t0B0000001duZQAQ'
	DeployCodeAndMetadata $orgAlias $sourcesDirectory $runTests
	LoadData $orgAlias $sourcesDirectory
	MigrateProvidersFromPROD $orgAlias
	DeployUsers $orgAlias
	GeneratePassword $orgAlias
	PublishScratchOrgInfo $orgAlias $pullRequestID
		
}
catch
{
	Write-Host -ForegroundColor "Red" "`n`nError creating scratch org!"
	DeleteScratchOrg $orgAlias
	throw
}