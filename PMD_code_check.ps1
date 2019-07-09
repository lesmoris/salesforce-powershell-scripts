Param(
	[string]$sourceBranch = $(throw "sourceBranch is null!")
)	
	
Write-Host "Installing PMD..."
npm install -g pmd-bin

Write-Host "Target branch:"
Write-Host $sourceBranch
Write-Host "Files to check:"
$sourceBranch = "$sourceBranch" -replace 'refs/heads', 'origin'
$getFileList = "git --no-pager diff --diff-filter=a --name-only $sourceBranch $(git merge-base $sourceBranch origin/master) | Select-String -Pattern '.cls'"
Invoke-Expression $getFileList
Invoke-Expression $getFileList | Out-File -FilePath .\PMD_files_to_process.txt -Encoding ASCII

If ((Get-Item ".\PMD_files_to_process.txt").length -gt 0kb) {
	Write-Host "Checking files with PMD..."
	Invoke-Expression "pmd -filelist PMD_files_to_process.txt -R .\apex_ruleset.xml -format textcolor -no-cache"
	Remove-Item ".\PMD_files_to_process.txt"
}
Else {
	Write-Host "No files to check"
}
