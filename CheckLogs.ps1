Param(
    [Parameter(HelpMessage = "The GitHub Token running the action", Mandatory = $true)]
    [string] $GH_TOKEN,
    [Parameter(HelpMessage = "Comma-separated list of GitHub workflow names", Mandatory = $true)]
    [string] $WORKFLOWS
)

# Use the default GitHub environment variable for the repository
$REPO = $env:GITHUB_REPOSITORY

function Check-GitHubWorkflow {
    Param(
        [Parameter(HelpMessage = "The GitHub Token running the action", Mandatory = $true)]
        [string] $GH_TOKEN,
        [Parameter(HelpMessage = "Comma-separated list of GitHub workflow names", Mandatory = $true)]
        [string] $WORKFLOWS,
        [Parameter(HelpMessage = "The GitHub repo name", Mandatory = $true)]
        [string] $REPO
    )

    $ErrorActionPreference = "Stop"
    Set-StrictMode -Version 2.0

    # Ensure the GitHub token is provided
    if ([string]::IsNullOrEmpty($GH_TOKEN)) {
        Write-Host "Error: GitHub token is not provided."
        return
    }

    # Initialize output variables
    $allFoundErrors = @()
    $foundWorkflows = @()

    # Split WORKFLOWS by comma and trim spaces
    $workflowNames = $WORKFLOWS -split ',' | ForEach-Object { $_.Trim() }

    # Fetch the workflow runs using GitHub CLI
    $workflowRunsJson = gh run list --repo $REPO --limit 3 --json attempt,startedAt,name,number,displayTitle,createdAt,headBranch,event,url,databaseId,workflowDatabaseId,workflowName,status,conclusion

    # Convert JSON output to PowerShell object
    $workflowRuns = $workflowRunsJson | ConvertFrom-Json

    # Ensure workflowRuns is an array, even if it's a single object
    if ($workflowRuns -isnot [System.Array]) {
        $workflowRuns = @($workflowRuns)
    }

    # Filter runs for specific workflows
    $filteredWorkflows = $workflowRuns | Where-Object { $_.displayTitle -in $workflowNames }

    # Ensure filteredWorkflows is an array
    if ($filteredWorkflows -isnot [System.Array]) {
        $filteredWorkflows = @($filteredWorkflows)
    }

    # Check if any filtered workflow runs are found
    if ($filteredWorkflows.Count -eq 0) {
        Write-Host "No workflow runs found for the specified workflows in repository '$REPO'."
        return
    }

    # Iterate through the filtered workflow runs and find those that need handling
    foreach ($run in $filteredWorkflows) {
        # Initialize message
        $workflowRunMessage = ""

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
            $workflowRunMessage = "The workflow '$workflowRunName' started at $workflowRunStartTime on branch '$workflowRunOnBranch' for the event '$workflowRunAtEvent' has been attempted $workflowRunAttempts times and has finished with status: $workflowRunConclusion."
            Write-Host $workflowRunMessage
            Write-Host "To find out more information, please check: $workflowRunURL"

            # Collect found workflow details
            $foundWorkflows += [PSCustomObject]@{
                WorkflowRunName       = $workflowRunName
                WorkflowRunId         = $workflowRunId
                WorkflowRunAttempts   = $workflowRunAttempts
                WorkflowRunStartTime  = $workflowRunStartTime
                WorkflowRunOnBranch   = $workflowRunOnBranch
                WorkflowRunAtEvent    = $workflowRunAtEvent
                WorkflowRunConclusion = $workflowRunConclusion
                WorkflowRunURL        = $workflowRunURL
                WorkflowRunMessage    = $workflowRunMessage
            }
        }
        elseif ($workflowRunConclusion -eq "failure") {
            # Set headers for authentication
            # Fetch workflow run logs using Invoke-RestMethod
            $workflowRunLogURL = "https://api.github.com/repos/$REPO/actions/runs/$workflowRunId/logs"

            Write-Host "Fetching logs from $workflowRunLogURL"

            # Use Invoke-RestMethod to download the logs
            $logFile = "$($env:TEMP)\workflow_$workflowRunId.zip"
            $headers = @{
                "Authorization"       = "Bearer $GH_TOKEN"
                "Accept"              = "application/vnd.github+json"
                "X-GitHub-Api-Version" = "2022-11-28"
            }

            # Try to download the logs
            try {
                Invoke-RestMethod -Uri $workflowRunLogURL -Headers $headers -OutFile $logFile
                Write-Host "Log file downloaded successfully to $logFile"

                # Read and extract error messages from the log file
                if (Test-Path $logFile) {
                    $extractPath = "$($env:TEMP)\workflow_logs_$workflowRunId"
                    Expand-Archive -Path $logFile -DestinationPath $extractPath -Force
                    $logFiles = Get-ChildItem -Path $extractPath -Recurse -Filter "*.txt"
                    foreach ($file in $logFiles) {
                        $content = Get-Content -Path $file.FullName
                        $errorMessages = $content | Select-String -Pattern "\[##error\](.*)" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }

                        if ($errorMessages) {
                            $workflowRunMessage += "`n`nErrors found in logs:`n" + ($errorMessages -join "`n")
                        }
                    }

                    # Clean up temporary files
                    Remove-Item -Path $extractPath -Recurse -Force
                    Remove-Item -Path $logFile -Force
                }

                # Collect found workflow details
                $foundWorkflows += [PSCustomObject]@{
                    WorkflowRunName       = $workflowRunName
                    WorkflowRunId         = $workflowRunId
                    WorkflowRunAttempts   = $workflowRunAttempts
                    WorkflowRunStartTime  = $workflowRunStartTime
                    WorkflowRunOnBranch   = $workflowRunOnBranch
                    WorkflowRunAtEvent    = $workflowRunAtEvent
                    WorkflowRunConclusion = $workflowRunConclusion
                    WorkflowRunURL        = $workflowRunURL
                    WorkflowRunMessage    = $workflowRunMessage
                }

            } catch {
                Write-Host "Failed to download or extract the log file for workflow run ID $workflowRunId."
                Write-Host "Exception Message: $($_.Exception.Message)"
                $allFoundErrors += "Failed to process logs for workflow: '$workflowRunName'"
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
        $workflowRunMessage = $foundWorkflows[0]?.WorkflowRunMessage

        # Escape special characters in allFoundErrors
        $allFoundErrorsEscaped = ($allFoundErrors -join "`n") -replace "`n", '\n' -replace "`r", '\r' -replace '"', '\"'

        # Set output variables using environment file
        Add-Content -Path $env:GITHUB_OUTPUT -Value "allFoundErrors=$allFoundErrorsEscaped"
        Add-Content -Path $env:GITHUB_ENV -Value "allFoundErrors=$allFoundErrorsEscaped"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunName=$workflowRunName"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunName=$workflowRunName"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunId=$workflowRunId"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunId=$workflowRunId"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunAttempts=$workflowRunAttempts"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunAttempts=$workflowRunAttempts"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunStartTime=$workflowRunStartTime"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunStartTime=$workflowRunStartTime"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunOnBranch=$workflowRunOnBranch"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunOnBranch=$workflowRunOnBranch"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunAtEvent=$workflowRunAtEvent"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunAtEvent=$workflowRunAtEvent"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunConclusion=$workflowRunConclusion"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunConclusion=$workflowRunConclusion"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunURL=$workflowRunURL"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunURL=$workflowRunURL"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunMessage=$workflowRunMessage"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunMessage=$workflowRunMessage"
    } else {
        Write-Host "No workflows with the specified conclusions found."
    }
}

# Call the function
Check-GitHubWorkflow -GH_TOKEN $GH_TOKEN -WORKFLOWS $WORKFLOWS -REPO $REPO
