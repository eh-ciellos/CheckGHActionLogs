Param(
    [Parameter(HelpMessage = "The GitHub Token running the action", Mandatory = $true)]
    [string] $GH_TOKEN,
    [Parameter(HelpMessage = "Array of GitHub workflow names", Mandatory = $true)]
    [string[]] $WORKFLOWS = @(" Test Next Major", " Test Next Minor"),
    [Parameter(HelpMessage = "The GitHub repo name", Mandatory = $false)]
    [string] $REPO = $env:GITHUB_REPOSITORY
)

function Check-GitHubWorkflow {
    Param(
        [Parameter(HelpMessage = "The GitHub Token running the action", Mandatory = $true)]
        [string] $GH_TOKEN,
        [Parameter(HelpMessage = "Array of GitHub workflow names", Mandatory = $true)]
        [string[]] $WORKFLOWS = @(" Test Next Major", " Test Next Minor"),
        [Parameter(HelpMessage = "The GitHub repo name", Mandatory = $false)]
        [string] $REPO = $env:GITHUB_REPOSITORY
    )

    $ErrorActionPreference = "Stop"
    Set-StrictMode -Version 2.0

    # Initialize output variables
    $allFoundErrors = @()
    $foundWorkflows = @()

    # Authenticate GitHub CLI
    $GH_TOKEN | gh auth login --with-token

    # Fetch the workflow runs using GitHub CLI
    $workflowRunsJson = gh run list --repo $REPO --limit 3 --json attempt,conclusion,startedAt,name,number,displayTitle,createdAt,headBranch,event,url,databaseId,workflowDatabaseId,workflowName,status

    # Convert JSON output to PowerShell object
    $workflowRuns = $workflowRunsJson | ConvertFrom-Json

    # Ensure $workflowRuns is always an array
    $workflowRuns = @($workflowRuns)

    # Use WORKFLOWS as an array directly
    $workflowNames = $WORKFLOWS

    # Filter runs for specific workflows
    $filteredWorkflows = @($workflowRuns | Where-Object { $_.displayTitle -in $workflowNames })

    # Check if any filtered workflow runs are found
    if ($filteredWorkflows) {
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
                        $filteredErrors = Get-Content -Path $allLogsFile | Select-String -Pattern "\[error\]" | ForEach-Object { $_ -replace '.*\[error\]\s*', '' }

                        if ($filteredErrors) {
                            $workflowRunMessage += "`n`nErrors found in logs:`n" + ($filteredErrors -join "`n")
                        } else {
                            $workflowRunMessage = "No errors found in logs."
                        }

                        # Clean up temporary files
                        Remove-Item -Path $extractPath -Recurse -Force
                        Remove-Item -Path $logFile -Force
                        Remove-Item -Path $allLogsFile -Force  # Clean up all_logs.txt
                    }
                } catch {
                    Write-Output "Failed to download or extract the log file."
                    Write-Output $_.Exception.Message
                    $allFoundErrors += "Failed to download or process log file for workflow: '$workflowRunName'"
                    $workflowRunMessage = "Failed to download or extract the log file."
                    continue
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
            }
        }

        # Prepare outputs if workflows were found
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
            $allFoundErrors        = $allFoundErrors -join "`n"

            # Generate unique delimiters
            $delimWorkflowRunMessage = "EOF$(Get-Random)"
            $delimAllFoundErrors = "EOF$(Get-Random)"

            # Set output variables using $GITHUB_OUTPUT (supports multi-line)
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunName=$workflowRunName"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunId=$workflowRunId"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunAttempts=$workflowRunAttempts"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunStartTime=$workflowRunStartTime"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunOnBranch=$workflowRunOnBranch"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunAtEvent=$workflowRunAtEvent"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunConclusion=$workflowRunConclusion"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunURL=$workflowRunURL"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunMessage<<$delimWorkflowRunMessage`n$workflowRunMessage`n$delimWorkflowRunMessage"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "allFoundErrors<<$delimAllFoundErrors`n$allFoundErrors`n$delimAllFoundErrors"

            # Encode multi-line values before writing to $GITHUB_ENV
            $encodedWorkflowRunMessage = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($workflowRunMessage))
            $encodedAllFoundErrors = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($allFoundErrors))

            # Write to $GITHUB_ENV
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunName=$workflowRunName"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunId=$workflowRunId"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunAttempts=$workflowRunAttempts"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunStartTime=$workflowRunStartTime"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunOnBranch=$workflowRunOnBranch"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunAtEvent=$workflowRunAtEvent"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunConclusion=$workflowRunConclusion"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunURL=$workflowRunURL"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunMessage=$encodedWorkflowRunMessage"
            Add-Content -Path $env:GITHUB_ENV -Value "allFoundErrors=$encodedAllFoundErrors"

            # Debug: Print the output values
            Write-Output "Set allFoundErrors: $allFoundErrors"
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
    } else {
        Write-Host "No workflow runs found for the specified workflows in repository '$REPO'."
    }
}

# Call the function
Check-GitHubWorkflow -GH_TOKEN $GH_TOKEN -WORKFLOWS $WORKFLOWS -REPO $REPO
