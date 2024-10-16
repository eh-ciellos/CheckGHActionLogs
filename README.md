# CheckGHActionLogs

[![GitHub release (latest by date)](https://img.shields.io/github/v/release/eh-ciellos/CheckGHActionLogs)](https://github.com/eh-ciellos/CheckGHActionLogs/releases)
[![GitHub](https://img.shields.io/github/license/eh-ciellos/CheckGHActionLogs)](https://github.com/eh-ciellos/CheckGHActionLogs/blob/main/LICENSE)

A GitHub Action that checks specified GitHub workflows for errors or failures, retrieves logs, and provides detailed outputs for further processing or notifications.

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [Usage](#usage)
  - [Setting Up the `WORKFLOWS` Repository Variable](#setting-up-the-workflows-repository-variable)
  - [Example Workflow](#example-workflow)
- [Examples](#examples)
  - [Decoding the Base64 Encoded Message](#decoding-the-base64-encoded-message)
- [Notes](#notes)
- [License](#license)

## Introduction

**CheckGHActionLogs** is a composite GitHub Action designed to:

- Check specified GitHub workflows for specific conclusions (e.g., failure).
- Retrieve and process logs from failed workflow runs.
- Extract relevant error messages (e.g., AL error codes) from the logs.
- Provide detailed outputs that can be used for notifications or further processing.

This action is particularly useful for automating the monitoring of workflows and integrating with notification systems like email alerts.

## Features

- **Automated Workflow Monitoring**: Checks the most recent runs of specified workflows.
- **Error Extraction**: Retrieves logs from failed runs and extracts relevant error messages.
- **Detailed Outputs**: Provides comprehensive outputs, including base64 encoded messages, for seamless integration with other actions or systems.
- **Flexible Integration**: Can be combined with other actions to compose emails, send notifications, or trigger other automated responses.

## Prerequisites

- **GitHub Token**: A personal access token or a repository secret (`GHTOKENWORKFLOW`) with the necessary permissions:
  - `repo`
  - `actions: read`

- **GitHub CLI (`gh`)**: The action uses the GitHub CLI, which should be available in the runner environment.

- **Repository Variable `WORKFLOWS`**: A repository variable that contains a JSON array of the workflow names you want to monitor.

### Setting Up the `WORKFLOWS` Repository Variable

1. Go to your repository on GitHub.
2. Navigate to **Settings** > **Secrets and variables** > **Actions**.
3. Under the **Variables** section, click on **New repository variable**.
4. Name the variable `WORKFLOWS`.
5. Set the value to a JSON array of your workflow names. For example:

   ```json
   ["Build", "Test", "Deploy"]
