Param(
    [Parameter(HelpMessage = "The GitHub Token running the action", Mandatory = $true)]
    [string] $GH_TOKEN,
    [Parameter(HelpMessage = "The GitHub repo name", Mandatory = $false)]
    [string] $REPO = $env:GITHUB_REPOSITORY
)

function Check-GitHubWorkflow {
    Param(
        [Parameter(HelpMessage = "The GitHub Token running the action", Mandatory = $true)]
        [string] $GH_TOKEN,
        [Parameter(HelpMessage = "The GitHub repo name", Mandatory = $false)]
        [string] $REPO
    )

    $ErrorActionPreference = "Stop"
    Set-StrictMode -Version 2.0

    # Initialize output variables
    $foundWorkflows = @()

    # Authenticate GitHub CLI
    $GH_TOKEN | gh auth login --with-token

    # Retrieve the 'WORKFLOWS' repository variable using GitHub REST API
    $headers = @{
        "Authorization" = "Bearer $GH_TOKEN"
        "Accept"        = "application/vnd.github+json"
    }

    $variablesUrl = "https://api.github.com/repos/$REPO/actions/variables/WORKFLOWS"

    try {
        $variableResponse = Invoke-RestMethod -Uri $variablesUrl -Headers $headers
    } catch {
        Write-Host "Failed to retrieve the 'WORKFLOWS' repository variable."
        Write-Host $_.Exception.Message
        return
    }

    if (-not $variableResponse || -not $variableResponse.value) {
        Write-Host "The 'WORKFLOWS' variable is not set or has no value."
        return
    }

    # Parse the JSON string to get the list of workflows
    try {
        $WORKFLOWS = ConvertFrom-Json -InputObject $variableResponse.value
    } catch {
        Write-Host "Failed to parse the 'WORKFLOWS' variable as JSON."
        Write-Host $_.Exception.Message
        return
    }

    if (-not $WORKFLOWS) {
        Write-Host "No workflow names found in the 'WORKFLOWS' variable."
        return
    }

    # Remove duplicates and empty entries
    $WORKFLOWS = $WORKFLOWS | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique

    # Fetch the workflow runs using GitHub CLI
    $workflowRunsJson = gh run list --repo $REPO --limit 10 --json attempt,conclusion,startedAt,name,number,displayTitle,createdAt,headBranch,event,url,databaseId,workflowDatabaseId,workflowName,status

    # Convert JSON output to PowerShell object
    $workflowRuns = $workflowRunsJson | ConvertFrom-Json

    # Ensure $workflowRuns is always an array
    $workflowRuns = @($workflowRuns)

    # Check if any workflow runs are found
    if (-not $workflowRuns) {
        Write-Host "No workflow runs found in repository '$REPO'."
        return
    }

    # Loop over each workflow name
    foreach ($workflowName in $WORKFLOWS) {
        # Use the workflow name as is, without trimming
        $workflowNameExact = $workflowName

        # Filter runs for the specific workflow
        $filteredWorkflows = @($workflowRuns | Where-Object { $_.displayTitle -eq $workflowNameExact })

        # Check if any filtered workflow runs are found
        if ($filteredWorkflows) {
            # Process only the first found workflow
            $run = $filteredWorkflows[0]

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

                # Exit the loop after processing the first workflow
                break
            }
            elseif ($workflowRunConclusion -eq "failure") {
                # Initialize message
                $workflowRunMessage = ""
                $logUrl = "https://api.github.com/repos/$REPO/actions/runs/$workflowRunId/logs"

                # Set headers for authentication
                $headers = @{
                    "Authorization"       = "Bearer $GH_TOKEN"
                    "Accept"              = "application/vnd.github+json"
                    "X-GitHub-Api-Version" = "2022-11-28"
                }

                # Define a temporary file path for logs
                $logFile = "$($env:TEMP)\workflow_$workflowRunId.zip"

                # Try to download the logs
                try {
                    Invoke-RestMethod -Uri $logUrl -Headers $headers -OutFile $logFile
                    Write-Output "Log file downloaded successfully to $logFile"

                    # Read and extract error messages from the log file
                    if (Test-Path $logFile) {
                        $extractPath = "$($env:TEMP)\workflow_logs_$workflowRunId"
                        $allLogsFile = "$($env:TEMP)\all_logs_$workflowRunId.txt"  # Place outside of $extractPath

                        Expand-Archive -Path $logFile -DestinationPath $extractPath -Force

                        # Combine all .txt files into one file called all_logs.txt
                        Get-ChildItem -Path $extractPath -Recurse -Filter "*.txt" | ForEach-Object { Get-Content $_.FullName } | Out-File -FilePath $allLogsFile

                        # Filter for errors and extract the content after [error]
                        $filteredErrors = Get-Content -Path $allLogsFile | Select-String -Pattern "\[error\]" | ForEach-Object {
                            # Extract the error message after [error]
                            $errorMessage = $_ -replace '.*\[error\]\s*', ''
                            # Check if the error message starts with AL followed by digits
                            if ($errorMessage -match '^AL\d+\b') {
                                # Return the error message
                                $errorMessage
                            }
                        } | Select-Object -Unique

                        if ($filteredErrors) {
                            $workflowRunMessage += "`n`nErrors found in logs:`n" + ($filteredErrors -join "`n")
                        } else {
                            $workflowRunMessage = "No relevant AL error codes found in logs."
                        }

                        # Clean up temporary files
                        Remove-Item -Path $extractPath -Recurse -Force
                        Remove-Item -Path $logFile -Force
                        Remove-Item -Path $allLogsFile -Force  # Clean up all_logs.txt
                    }

                } catch {
                    Write-Output "Failed to download or extract the log file."
                    Write-Output $_.Exception.Message
                    $workflowRunMessage = "Failed to download or extract the log file."
                }

                # Collect found workflow details, including the workflowRunMessage
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

                # Exit the loop after processing the first workflow
                break
            } else {
                Write-Host "Workflow '$workflowRunName' has conclusion: $workflowRunConclusion. No action taken."
                # Proceed to the next workflow if needed
            }
        } else {
            Write-Host "No workflow runs found for the specified workflow '$workflowNameExact' in repository '$REPO'."
        }
    }

    # Prepare outputs if the workflow was processed
    if ($foundWorkflows) {
        # Output all relevant details of the first found workflow
        $workflowRunName       = $foundWorkflows[0].WorkflowRunName
        $workflowRunId         = $foundWorkflows[0].WorkflowRunId
        $workflowRunAttempts   = $foundWorkflows[0].WorkflowRunAttempts
        $workflowRunStartTime  = $foundWorkflows[0].WorkflowRunStartTime
        $workflowRunOnBranch   = $foundWorkflows[0].WorkflowRunOnBranch
        $workflowRunAtEvent    = $foundWorkflows[0].WorkflowRunAtEvent
        $workflowRunConclusion = $foundWorkflows[0].WorkflowRunConclusion
        $workflowRunURL        = $foundWorkflows[0].WorkflowRunURL
        $workflowRunMessage    = $foundWorkflows[0].WorkflowRunMessage

        # Base64 encode the WorkflowRunMessage
        $encodedWorkflowRunMessage = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($workflowRunMessage))

        # Set outputs
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunName=$workflowRunName"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunId=$workflowRunId"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunAttempts=$workflowRunAttempts"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunStartTime=$workflowRunStartTime"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunOnBranch=$workflowRunOnBranch"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunAtEvent=$workflowRunAtEvent"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunConclusion=$workflowRunConclusion"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunURL=$workflowRunURL"
        Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunMessage=$encodedWorkflowRunMessage"

        # Set env
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunName=$workflowRunName"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunId=$workflowRunId"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunAttempts=$workflowRunAttempts"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunStartTime=$workflowRunStartTime"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunOnBranch=$workflowRunOnBranch"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunAtEvent=$workflowRunAtEvent"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunConclusion=$workflowRunConclusion"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunURL=$workflowRunURL"
        Add-Content -Path $env:GITHUB_ENV -Value "workflowRunMessage=$encodedWorkflowRunMessage"

        # Debug: Print the output values
        Write-Output "Set workflowRunName: $workflowRunName"
        Write-Output "Set workflowRunId: $workflowRunId"
        Write-Output "Set workflowRunAttempts: $workflowRunAttempts"
        Write-Output "Set workflowRunStartTime: $workflowRunStartTime"
        Write-Output "Set workflowRunOnBranch: $workflowRunOnBranch"
        Write-Output "Set workflowRunAtEvent: $workflowRunAtEvent"
        Write-Output "Set workflowRunConclusion: $workflowRunConclusion"
        Write-Output "Set workflowRunURL: $workflowRunURL"
        Write-Output "Set workflowRunMessage: $workflowRunMessage"
    } else {
        Write-Host "No workflows with the specified conclusions found."
    }
}

# Call the function
Check-GitHubWorkflow -GH_TOKEN $GH_TOKEN -REPO $REPO
