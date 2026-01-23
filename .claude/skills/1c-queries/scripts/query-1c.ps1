#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [string]$Query,
    [string]$QueryFile
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$envPath = Join-Path $scriptDir "..\.env"

if (-not (Test-Path $envPath)) {
    throw "Env file not found: $envPath"
}

$envValues = @{}
Get-Content -Path $envPath | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) {
        return
    }

    $parts = $line -split "=", 2
    if ($parts.Count -ne 2) {
        return
    }

    $key = $parts[0].Trim()
    $value = $parts[1].Trim()

    if ($value.StartsWith('"') -and $value.EndsWith('"')) {
        $value = $value.Substring(1, $value.Length - 2)
    } elseif ($value.StartsWith("'") -and $value.EndsWith("'")) {
        $value = $value.Substring(1, $value.Length - 2)
    }

    $envValues[$key] = $value
}

function Get-RequiredEnv([string]$Name) {
    if (-not $envValues.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace($envValues[$Name])) {
        throw "Missing $Name in $envPath"
    }

    return $envValues[$Name]
}

$url = Get-RequiredEnv "ONEC_QUERY_URL"
$login = Get-RequiredEnv "ONEC_QUERY_LOGIN"
$password = Get-RequiredEnv "ONEC_QUERY_PASSWORD"

if ($QueryFile) {
    $Query = Get-Content -Raw -Path $QueryFile
}

if (-not $Query) {
    $Query = [Console]::In.ReadToEnd()
}

if ([string]::IsNullOrWhiteSpace($Query)) {
    throw "Query is empty. Use -Query, -QueryFile, or pipe input."
}

$authBytes = [Text.Encoding]::ASCII.GetBytes("$($login):$($password)")
$authHeader = [Convert]::ToBase64String($authBytes)

$payload = @{ query = $Query } | ConvertTo-Json -Compress
$payloadBytes = [Text.Encoding]::UTF8.GetBytes($payload)
$headers = @{ Authorization = "Basic $authHeader" }

$requestParams = @{
    Method      = "Post"
    Uri         = $url
    Headers     = $headers
    ContentType = "application/json; charset=utf-8"
    Body        = $payloadBytes
    TimeoutSec  = 60
}

if ($PSVersionTable.PSVersion.Major -lt 6) {
    $requestParams.UseBasicParsing = $true
}

try {
    $response = Invoke-WebRequest @requestParams -ErrorAction Stop
    Write-Output $response.Content
} catch {
    $responseBody = $null
    $exception = $_.Exception
    $errorDetails = $_.ErrorDetails
    $response = $exception.Response

    if ($null -ne $response) {
        try {
            $stream = $response.GetResponseStream()
            if ($null -ne $stream) {
                $reader = New-Object System.IO.StreamReader($stream, [Text.Encoding]::UTF8)
                $responseBody = $reader.ReadToEnd()
                $reader.Close()
            }
        } catch {
        }
    }

    if ([string]::IsNullOrWhiteSpace($responseBody) -and $null -ne $errorDetails -and -not [string]::IsNullOrWhiteSpace($errorDetails.Message)) {
        Write-Output $errorDetails.Message
    } elseif ([string]::IsNullOrWhiteSpace($responseBody)) {
        Write-Output $exception.Message
    } else {
        Write-Output $responseBody
    }

    exit 1
}
