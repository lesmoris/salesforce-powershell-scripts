String AreWorkOrdersEnabled() {
	try {
		Schema.DescribeSObjectResult[] descResult = Schema.describeSObjects(new String[]{'WorkOrder'});
		return 'WorkOrdersAreEnabled';
	}
	catch (Exception ex) {
		return 'WorkOrdersAreDisabled';
	}
}

system.debug( AreWorkOrdersEnabled() );