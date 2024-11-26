Param(
    [Parameter(HelpMessage = "The GitHub Token running the action", Mandatory = $true)]
    [string] $GH_TOKEN,
    [Parameter(HelpMessage = "The GitHub repo name", Mandatory = $false)]
    [string] $REPO = $env:GITHUB_REPOSITORY
)

function Check-GitHubWorkflow {
    Param(
        [string] $GH_TOKEN,
        [string] $REPO
    )

    $ErrorActionPreference = "Stop"
    Set-StrictMode -Version 2.0

    # Authenticate GitHub CLI
    try {
        $GH_TOKEN | gh auth login --with-token
        Write-Host "GitHub CLI authenticated successfully."
    } catch {
        Write-Host "::Error::Failed to authenticate GitHub CLI. Check your token or permissions."
        return
    }

    # Fetch workflow runs
    $workflowRunsJson = gh run list --repo $REPO --limit 10 --json attempt,conclusion,displayTitle,url
    $workflowRuns = @($workflowRunsJson | ConvertFrom-Json)

    if (-not $workflowRuns) {
        Write-Host "No workflow runs found in repository '$REPO'."
        return
    }

    # Debug: Log retrieved workflow runs
    Write-Host "Retrieved workflow runs:"
    $workflowRuns | ForEach-Object {
        Write-Host "Display Title: '$($_.displayTitle)', Status: '$($_.status)', Conclusion: '$($_.conclusion)'"
    }

    # Process workflows
    foreach ($workflowName in $WORKFLOWS) {
        # Use the workflow name exactly as it is in the variable
        $workflowNameExact = $workflowName

        # Match workflow runs by displayTitle
        $filteredWorkflows = @($workflowRuns | Where-Object { $_.displayTitle -eq $workflowNameExact })

        if ($filteredWorkflows) {
            Write-Host "Found matching workflow: '$workflowNameExact'"
            $run = $filteredWorkflows[0]  # Process the first matching run

            # Extract details from the workflow run
            $workflowRunName = $run.displayTitle
            $workflowRunId = $run.databaseId
            $workflowRunAttempts = $run.attempt
            $workflowRunStartTime = $run.startedAt
            $workflowRunOnBranch = $run.headBranch
            $workflowRunAtEvent = $run.event
            $workflowRunConclusion = $run.conclusion
            $workflowRunURL = $run.url

            # Set outputs
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunName=$workflowRunName"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunId=$workflowRunId"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunAttempts=$workflowRunAttempts"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunStartTime=$workflowRunStartTime"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunOnBranch=$workflowRunOnBranch"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunAtEvent=$workflowRunAtEvent"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunConclusion=$workflowRunConclusion"
            Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunURL=$workflowRunURL"

            # Set environment variables
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunName=$workflowRunName"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunId=$workflowRunId"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunAttempts=$workflowRunAttempts"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunStartTime=$workflowRunStartTime"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunOnBranch=$workflowRunOnBranch"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunAtEvent=$workflowRunAtEvent"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunConclusion=$workflowRunConclusion"
            Add-Content -Path $env:GITHUB_ENV -Value "workflowRunURL=$workflowRunURL"

            Write-Host "Workflow details have been set as outputs and environment variables."
            return  # Exit after processing the first matching workflow
        } else {
            Write-Host "No workflow runs found for: '$workflowNameExact'"
        }
    }

    # Handle case where no workflows are found
    Write-Host "No workflows with the specified conclusions found."

    # Set default outputs
    Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunMessage=No workflows or errors found."
    Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunName=None"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunId=None"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunAttempts=0"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunStartTime=None"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunOnBranch=None"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunAtEvent=None"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunConclusion=None"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunURL=None"

    # Set default environment variables
    Add-Content -Path $env:GITHUB_ENV -Value "workflowRunName=None"
    Add-Content -Path $env:GITHUB_ENV -Value "workflowRunId=None"
    Add-Content -Path $env:GITHUB_ENV -Value "workflowRunAttempts=0"
    Add-Content -Path $env:GITHUB_ENV -Value "workflowRunStartTime=None"
    Add-Content -Path $env:GITHUB_ENV -Value "workflowRunOnBranch=None"
    Add-Content -Path $env:GITHUB_ENV -Value "workflowRunAtEvent=None"
    Add-Content -Path $env:GITHUB_ENV -Value "workflowRunConclusion=None"
    Add-Content -Path $env:GITHUB_ENV -Value "workflowRunURL=None"
}

# Call the function
Check-GitHubWorkflow -GH_TOKEN $GH_TOKEN -REPO $REPO
