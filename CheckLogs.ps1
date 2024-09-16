# .github/actions/check-logs/CheckLogs.ps1

param (
    [string]$GH_TOKEN,
    [string]$WORKFLOWS
)

# Use the default GitHub environment variable for the repository
$REPO = $env:GITHUB_REPOSITORY

function Check-GitHubWorkflow {
    param (
        [string]$GH_TOKEN,
        [string]$WORKFLOWS,
        [string]$REPO
    )

    # Initialize output variables
    $allFoundErrors = @()
    $foundWorkflows = @()

    # Fetch the workflow runs using GitHub CLI
    $workflowRuns = gh run list --repo $REPO --limit 10 --json attempt,startedAt,name,number,displayTitle,createdAt,headBranch,event,url,databaseId,workflowDatabaseId,workflowName,status,conclusion

    # Convert JSON output to PowerShell object
    $workflowRuns = $workflowRuns | ConvertFrom-Json

    # Filter runs for specific workflows: "Test Next Major" or "Test Next Minor"
    $filteredWorkflows = $workflowRuns | Where-Object { $_.displayTitle -in @(" Test Next Major", " Test Next Minor") }

    # Check if any filtered workflow runs are found
    if ($filteredWorkflows.Count -eq 0) {
        Write-Host "No workflow runs found for ' Test Next Major' or ' Test Next Minor' in repository '$REPO'."
        return
    }

    # Iterate through the filtered workflow runs and find those that need handling
    foreach ($run in $filteredWorkflows) {
        # Extract workflow details
        $workflowRunName = $run.displayTitle
        $workflowRunId = $run.databaseId
        $workflowRunAttempts = $run.attempt
        $workflowRunStartTime = $run.startedAt
        $workflowRunOnBranch = $run.headBranch
        $workflowRunAtEvent = $run.event
        $workflowRunConclusion = $run.conclusion
        $workflowRunURL = $run.url

        # Handle workflows with specific conclusions
        if ($workflowRunConclusion -in @("neutral", "cancelled", "skipped", "timed_out", "action_required")) {
            # Prepare a message
            $workflowRunMessage = "The workflow $workflowRunName started at $workflowRunStartTime on branch $workflowRunOnBranch for the event $workflowRunAtEvent has been attempted $workflowRunAttempts times and has finished with status: $workflowRunConclusion."
            Write-Host $workflowRunMessage
            Write-Host "To find out more information, please check: $workflowRunURL"

            # Collect found workflow details
            $foundWorkflows += [PSCustomObject]@{
                WorkflowRunName = $workflowRunName
                WorkflowRunId   = $workflowRunId
                WorkflowRunAttempts = $workflowRunAttempts
                WorkflowRunStartTime = $workflowRunStartTime
                WorkflowRunOnBranch = $workflowRunOnBranch
                WorkflowRunAtEvent = $workflowRunAtEvent
                WorkflowRunConclusion = $workflowRunConclusion
                WorkflowRunURL = $workflowRunURL
            }
        }
        elseif ($workflowRunConclusion -eq "failure") {
            # Set headers for authentication
            $headers = @{
                "Authorization" = "Bearer $GH_TOKEN"
                "Accept"        = "application/vnd.github+json"
                "X-GitHub-Api-Version" = "2022-11-28"
            }

            # Define a temporary file path for logs
            $logFile = "$($env:TEMP)\workflow_$workflowRunId_log.zip"

            # Try to download the logs
            try {
                Invoke-RestMethod -Uri $workflowRunURL -Headers $headers -OutFile $logFile
                Write-Host "Log file downloaded successfully to $logFile"

                # Read and extract error messages from the log file
                if (Test-Path $logFile) {
                    Expand-Archive -Path $logFile -DestinationPath "$($env:TEMP)\workflow_logs" -Force
                    $logFiles = Get-ChildItem -Path "$($env:TEMP)\workflow_logs" -Recurse -Filter "*.txt"
                    foreach ($file in $logFiles) {
                        $content = Get-Content -Path $file.FullName
                        $errorMessages = $content | Select-String -Pattern "\[##error\](.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }
                        
                        if ($errorMessages) {
                            $workflowRunMessage += "`n`nErrors found in logs:`n" + ($errorMessages -join "`n")
                        }
                    }
                }

            } catch {
                Write-Host "Failed to download or extract the log file."
                Write-Host $_.Exception.Message
                $allFoundErrors += "Failed to download or process log file for workflow: '$workflowRunName'"
                continue
            }
        }
    }

    # Prepare outputs if workflows were found
    if ($foundWorkflows.Count -gt 0) {
        # Output all relevant details of the workflow
        $workflowRunName = $foundWorkflows[0]?.WorkflowRunName
        $workflowRunId = $foundWorkflows[0]?.WorkflowRunId
        $workflowRunAttempts = $foundWorkflows[0]?.WorkflowRunAttempts
        $workflowRunStartTime = $foundWorkflows[0]?.WorkflowRunStartTime
        $workflowRunOnBranch = $foundWorkflows[0]?.WorkflowRunOnBranch
        $workflowRunAtEvent = $foundWorkflows[0]?.WorkflowRunAtEvent
        $workflowRunConclusion = $foundWorkflows[0]?.WorkflowRunConclusion
        $workflowRunURL = $foundWorkflows[0]?.WorkflowRunURL

        # Set output variables using environment file
        $outputFile = "$env:GITHUB_OUTPUT"
        Add-Content -Path $outputFile -Value "allFoundErrors=$($allFoundErrors -join ', ')"
        Add-Content -Path $outputFile -Value "workflowRunName=$workflowRunName"
        Add-Content -Path $outputFile -Value "workflowRunId=$workflowRunId"
        Add-Content -Path $outputFile -Value "workflowRunAttempts=$workflowRunAttempts"
        Add-Content -Path $outputFile -Value "workflowRunStartTime=$workflowRunStartTime"
        Add-Content -Path $outputFile -Value "workflowRunOnBranch=$workflowRunOnBranch"
        Add-Content -Path $outputFile -Value "workflowRunAtEvent=$workflowRunAtEvent"
        Add-Content -Path $outputFile -Value "workflowRunConclusion=$workflowRunConclusion"
        Add-Content -Path $outputFile -Value "workflowRunURL=$workflowRunURL"
        Add-Content -Path $outputFile -Value "workflowRunMessage=$workflowRunMessage"
    } else {
        Write-Host "No workflows with the specified conclusions found."
    }
}

# Call the function
Check-GitHubWorkflow -GH_TOKEN $GH_TOKEN -WORKFLOWS $WORKFLOWS -REPO $REPO
