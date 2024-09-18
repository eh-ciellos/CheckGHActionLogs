# .github/actions/check-logs/CheckLogs.ps1

param(
    [string]$GH_TOKEN,
    [string]$WORKFLOWS
)

# Example outputs
$workflowRunMessage = "Workflow completed with status: success"
$workflowRunName = "Example Workflow"
$workflowRunId = "12345"

# Set the outputs using GitHub Actions environment file
Add-Content -Path $env:GITHUB_OUTPUT -Value "Environments=$workflowRunMessage"
Add-Content -Path $env:GITHUB_ENV -Value "Environments=$workflowRunMessage"
Add-Content -Path $env:GITHUB_OUTPUT -Value "Environments=$workflowRunName"
Add-Content -Path $env:GITHUB_ENV -Value "Environments=$workflowRunName"
Add-Content -Path $env:GITHUB_OUTPUT -Value "Environments=$workflowRunId"
Add-Content -Path $env:GITHUB_ENV -Value "Environments=$workflowRunId"

# Debug: Print the output values
Write-Output "Set workflowRunMessage: $workflowRunMessage"
Write-Output "Set workflowRunName: $workflowRunName"
Write-Output "Set workflowRunId: $workflowRunId"
