Param(
    [Parameter(HelpMessage = "The GitHub Token running the action", Mandatory = $true)]
    [string] $GH_TOKEN,
    [Parameter(HelpMessage = "The GitHub workflow name", Mandatory = $true)]
    [string] $WORKFLOWS
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

# IMPORTANT: No code that can fail should be outside the try/catch

try {
    $workflowName = $env:GITHUB_WORKFLOW
    $Script:IsOnGitHub = $true

# Example outputs
$workflowRunMessage = "Workflow completed with status: success"
$workflowRunName = "Example Workflow"
$workflowRunId = "12345"

# Set the outputs using GitHub Actions environment file
Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunMessage=$workflowRunMessage"
Add-Content -Path $env:GITHUB_ENV -Value "workflowRunMessage=$workflowRunMessage"
Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunName=$workflowRunName"
Add-Content -Path $env:GITHUB_ENV -Value "workflowRunName=$workflowRunName"
Add-Content -Path $env:GITHUB_OUTPUT -Value "workflowRunId=$workflowRunId"
Add-Content -Path $env:GITHUB_ENV -Value "workflowRunId=$workflowRunId"

# Debug: Print the output values
Write-Output "Set workflowRunMessage: $workflowRunMessage"
Write-Output "Set workflowRunName: $workflowRunName"
Write-Output "Set workflowRunId: $workflowRunId"
}
catch{
    Write-Output "$workflowRunMessage"
    Write-Output "$workflowRunName"
    Write-Output "$workflowRunId"
    Write-Output "$workflowName"
}