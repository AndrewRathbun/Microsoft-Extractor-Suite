Function Get-UALGraph
{
<#
    .SYNOPSIS
    Gets all the unified audit log entries.

    .DESCRIPTION
    Makes it possible to extract all unified audit data out of a Microsoft 365 environment. 
	The output will be written to: Output\UnifiedAuditLog\

	.PARAMETER UserIds
    UserIds is the UserIds parameter filtering the log entries by the account of the user who performed the actions.

	.PARAMETER StartDate
    startDate is the parameter specifying the start date of the date range.
	Default: Today -90 days

	.PARAMETER EndDate
    endDate is the parameter specifying the end date of the date range.
	Default: Now

	.PARAMETER OutputDir
	OutputDir is the parameter specifying the output directory.
	Default: Output\UnifiedAuditLog

	.PARAMETER Encoding
    Encoding is the parameter specifying the encoding of the CSV/JSON output file.
	Default: UTF8

    .PARAMETER RecordType
    The RecordType parameter filters the log entries by record type.
	Options are: ExchangeItem, ExchangeAdmin, etc. A total of 236 RecordTypes are supported.

    .PARAMETER Keyword
    The Keyword parameter allows you to filter the Unified Audit Log for specific keywords.

    .PARAMETER Service
    The Service parameter filters the Unified Audit Log based on the specific services.
    Options are: Exchange,Skype,Sharepoint etc.

    .PARAMETER Operations
    The Operations parameter filters the log entries by operation or activity type. Usage: -Operations UserLoggedIn,MailItemsAccessed
	Options are: New-MailboxRule, MailItemsAccessed, etc.

    .PARAMETER IPAddress
    The IP address parameter is used to filter the logs by specifying the desired IP address.
	
	.PARAMETER SearchName
    Specifies the name of the search query. This parameter is required.

    .PARAMETER ObjecIDs 
    Exact data returned depends on the service in the current `@odatatype.microsoft.graph.security.auditLogQuery` record.
    For Exchange admin audit logging, the name of the object modified by the cmdlet.
    For SharePoint activity, the full URL path name of the file or folder accessed by a user. 
    For Microsoft Entra activity, the name of the user account that was modified.|
    
    .EXAMPLE
    Get-UALGraph -searchName Test 
	Gets all the unified audit log entries.
	
	.EXAMPLE
	Get-UALGraph -searchName Test -UserIds Test@invictus-ir.com
	Gets all the unified audit log entries for the user Test@invictus-ir.com.
	
	.EXAMPLE
	Get-UALGraph -searchName Test -startDate "2024-03-10T09:28:56Z" -endDate "2024-03-20T09:28:56Z" -Service Exchange
    Retrieves audit log data for the specified time range March 10, 2024 to March 20, 2024 and filters the results to include only events related to the Exchange service.
	
	.EXAMPLE
	Get-UALGraph -searchName Test -startDate "2024-03-01" -endDate "2024-03-10" -IPAddress 182.74.242.26
	Retrieve audit log data for the specified time range March 1, 2024 to March 10, 2024 and filter the results to include only entries associated with the IP address 182.74.242.26.

#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		$searchName,
		[string]$OutputDir = "Output\UnifiedAuditLog\",
		[string]$Encoding = "UTF8",
		[string]$startDate,
		[string]$endDate,
		[string[]]$RecordType = @(),
		[string]$Keyword = "",
		[string]$Service = "",
		[string[]]$Operations = @(),
		[string[]]$UserIds = @(),
		[string[]]$IPAddress = @(),
		[string[]]$ObjecIDs = @()
	)
	
	$requiredScopes = @("AuditLogsQuery.Read.All")
	$graphAuth = Get-GraphAuthType -RequiredScopes $RequiredScopes
	
	if (!(test-path $OutputDir))
	{
		write-logFile -Message "[INFO] Creating the following directory: $OutputDir"
		New-Item -ItemType Directory -Force -Name $OutputDir > $null
	}
	else
	{
		if (Test-Path -Path $OutputDir)
		{
			write-LogFile -Message "[INFO] Custom directory set to: $OutputDir"
		}
		else
		{
			write-Error "[Error] Custom directory invalid: $OutputDir exiting script" -ErrorAction Stop
			write-LogFile -Message "[Error] Custom directory invalid: $OutputDir exiting script"
		}
	}
	
	$script:startTime = Get-Date
	
	StartDate
	EndDate
	
	write-logFile -Message "[INFO] Running Get-UALGraph" -Color "Green"
	
	$body = @{
		"@odata.type"			    = "#microsoft.graph.security.auditLogQuery"
		displayName				    = $searchName
		filterStartDateTime		    = $script:startDate
		filterEndDateTime		    = $script:endDate
		recordTypeFilters		    = $RecordType
		keywordFilter			    = $Keyword
		serviceFilter			    = $Service
		operationFilters		    = $Operations
		userPrincipalNameFilters    = $UserIds
		ipAddressFilters		    = $IPAddress
		objectIdFilters			    = $ObjecIDs
		administrativeUnitIdFilters = @()
		status					    = ""
	} | ConvertTo-Json
	
	try
	{
		$response = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/security/auditLog/queries" -Body $body -ContentType "application/json"
		$scanId = $response.id
		write-logFile -Message "[INFO] A new Unified Audit Log search has started with the name: $searchName and ID: $scanId." -Color "Green"
		
		Start-Sleep -Seconds 10
		$apiUrl = "https://graph.microsoft.com/beta/security/auditLog/queries/$scanId"
		
		write-logFile -Message "[INFO] Waiting for the scan to start..."
		$lastStatus = ""
		do
		{
			$response = Invoke-MgGraphRequest -Method Get -Uri $apiUrl -ContentType 'application/json'
			$status = $response.status
			if ($status -ne $lastStatus)
			{
				$lastStatus = $status
			}
			Start-Sleep -Seconds 5
		}
		while ($status -ne "succeeded" -and $status -ne "running")
		if ($status -eq "running")
		{
			write-logFile -Message "[INFO] Unified Audit Log search has started... This can take a while..."
			do
			{
				$response = Invoke-MgGraphRequest -Method Get -Uri $apiUrl -ContentType 'application/json'
				$status = $response.status
				if ($status -ne $lastStatus)
				{
					write-logFile -Message "[INFO] Unified Audit Log search is still running. Waiting..."
					$lastStatus = $status
				}
				Start-Sleep -Seconds 5
			}
			while ($status -ne "succeeded")
		}
		write-logFile -Message "[INFO] Unified Audit Log search complete."
	}
	catch
	{
		Write-logFile -Message "[ERROR] An error occurred: $($_.Exception.Message)" -Color "Red"
		throw
	}
	
	try
	{
		write-logFile -Message "[INFO] Collecting scan results from api (this may take a while)"
		$date = [datetime]::Now.ToString('yyyyMMddHHmmss')
		$outputFilePath = "$($date)-$searchName-UnifiedAuditLog.json"
		$apiUrl = "https://graph.microsoft.com/beta/security/auditLog/queries/$scanId/records"
		
		Do
		{
			$response = Invoke-MgGraphRequest -Method Get -Uri $apiUrl -ContentType "application/json; odata.metadata=minimal; odata.streaming=true;" -OutputType Json
			$responseJson = $response | ConvertFrom-Json
			
			if ($responseJson.value)
			{
				$filePath = Join-Path -Path $OutputDir -ChildPath $outputFilePath
				$responseJson.value | ConvertTo-Json -Depth 100 | Out-File -FilePath $filePath -Append -Encoding $Encoding
				
			}
			else
			{
				Write-logFile -Message "[INFO] No results matched your search." -color Yellow
			}
			$apiUrl = $responseJson.'@odata.nextLink'
		}
		While ($apiUrl)
		
		write-logFile -Message "[INFO] Audit log records have been saved to $outputFilePath" -Color "Green"
		$endTime = Get-Date
		$runtime = $endTime - $script:startTime
		write-logFile -Message "[INFO] Total runtime (HH:MM:SS): $($runtime.Hours):$($runtime.Minutes):$($runtime.Seconds)" -Color "Green"
	}
	catch
	{
		Write-logFile -Message "[ERROR] An error occurred: $($_.Exception.Message)" -Color "Red"
		throw
	}
}



