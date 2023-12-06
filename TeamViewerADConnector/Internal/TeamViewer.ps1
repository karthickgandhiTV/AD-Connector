# Copyright (c) 2018-2023 TeamViewer Germany GmbH
# See file LICENSE

#requires -modules TeamViewerPS

$tvApiVersion = 'v1'
$tvApiBaseUrl = 'https://webapi.teamviewer.com'

function ConvertTo-TeamViewerRestError {
    param([parameter(ValueFromPipeline)]$err)

    Process {
        try {
            return ($err | Out-String | ConvertFrom-Json)
        }
        catch {
            return $err
        }
    }
}

function Invoke-TeamViewerAdRestMethod {
    # TeamViewer Web API requires TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $method = (& { param($Method) $Method } @args)

    if ($method -in 'Put', 'Delete') {
        # There is a known issue for PUT and DELETE operations to hang on Windows Server 2012.
        # Use `Invoke-WebRequest` for those type of methods.
        try {
            return ((Invoke-WebRequest -UseBasicParsing @args).Content | ConvertFrom-Json)
        }
        catch [System.Net.WebException] {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $reader.BaseStream.Position = 0

            Throw ($reader.ReadToEnd() | ConvertTo-TeamViewerRestError)
        }
    }
    else {
        try {
            return Invoke-RestMethod -ErrorVariable restError @args
        }
        catch {
            Throw ($restError | ConvertTo-TeamViewerRestError)
        }
    }
}

function Invoke-TeamViewerPing($accessToken) {
    $result = Invoke-TeamViewerAdRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/ping" -Method Get -Headers @{authorization = "Bearer $accessToken" }

    return $result.token_valid
}


function Add-TeamViewerUser($accessToken, $user) {
    $missingFields = (@('name', 'email', 'language') | Where-Object { !$user[$_] })

    if ($missingFields.Count -gt 0) {
        Throw "Cannot create user! Missing required fields [$missingFields]!"
    }

    $payload = @{ }
    @('email', 'password', 'name', 'language', 'sso_customer_id', 'meeting_license_key') | Where-Object { $user[$_] } | ForEach-Object { $payload[$_] = $user[$_] }

    return Invoke-TeamViewerAdRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users" -Method Post -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Edit-TeamViewerUser($accessToken, $userId, $user) {
    $payload = @{ }

    @('email', 'name', 'password', 'active') | Where-Object { $user[$_] } | ForEach-Object { $payload[$_] = $user[$_] }
    return Invoke-TeamViewerAdRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users/$userId" -Method Put -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json)))
}

function Disable-TeamViewerUser($accessToken, $userId) {
    return Invoke-TeamViewerAdRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/users/$userId" -Method Put -Headers @{authorization = "Bearer $accessToken" } `
        -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes((@{active = $false } | ConvertTo-Json)))
}

function Get-TeamViewerAccount($accessToken, [switch] $NoThrow = $false) {
    try {
        return Invoke-TeamViewerAdRestMethod -Uri "$tvApiBaseUrl/api/$tvApiVersion/account" -Method Get -Headers @{authorization = "Bearer $accessToken" }
    }
    catch {
        if (!$NoThrow) {
            Throw
        }
    }
}


