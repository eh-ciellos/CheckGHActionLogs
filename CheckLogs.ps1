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
$outputFile = "$env:GITHUB_OUTPUT"
Add-Content -Path $outputFile -Value "workflowRunMessage=$workflowRunMessage`n"
Add-Content -Path $outputFile -Value "workflowRunName=$workflowRunName`n"
Add-Content -Path $outputFile -Value "workflowRunId=$workflowRunId`n"

# Debug: Print the output values
Write-Output "Set workflowRunMessage: $workflowRunMessage"
Write-Output "Set workflowRunName: $workflowRunName"
Write-Output "Set workflowRunId: $workflowRunId"
