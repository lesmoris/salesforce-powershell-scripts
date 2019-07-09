String scratchOrgName = '<SCRATCH_ORG_NAME>';

String DeleteScratchOrg() {
	try {
		Integer count = [SELECT count() FROM ScratchOrgInfo WHERE OrgName=:scratchOrgName and Status='Active'];
		if (count == 0)
			return 'ScratchOrg not found';
			
		ScratchOrgInfo scratchOrg = [SELECT Id FROM ScratchOrgInfo WHERE OrgName=:scratchOrgName and Status='Active'];			
		delete scratchOrg;
		return 'ScratchOrg deleted';
	}
	catch (Exception ex) {
		return ex.getMessage();
	}
}

system.debug( DeleteScratchOrg() );