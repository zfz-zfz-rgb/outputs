param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'Backups'))

# Read-only collection. No network settings are changed.
$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$folder = Join-Path $OutputDirectory ('Network-' + $stamp)
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$script:issues = New-Object System.Collections.Generic.List[string]

function Save-Json($Name, [scriptblock]$Collect) {
    try {
        $data = @(& $Collect)
        ConvertTo-Json -InputObject $data -Depth 16 | Set-Content -LiteralPath (Join-Path $folder ($Name + '.json')) -Encoding UTF8
    } catch {
        $script:issues.Add($Name + ': ' + $_.Exception.Message)
    }
}

function Save-Command($Name, $Executable, [string[]]$CommandArguments) {
    try {
        $result = & $Executable @CommandArguments 2>&1
        $code = $LASTEXITCODE
        $result | Out-File -LiteralPath (Join-Path $folder $Name) -Encoding UTF8
        if ($code -ne 0) { throw ('Exit code ' + $code) }
    } catch {
        $script:issues.Add($Name + ': ' + $_.Exception.Message)
    }
}

Save-Json 'metadata' {
    [pscustomobject]@{
        SchemaVersion = 1
        CapturedAt = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Purpose = 'Network configuration snapshot; not an automatic restore package'
    }
}
Save-Json 'user-proxy' {
    $p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $c = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings\Connections' -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ProxyEnable = $p.ProxyEnable
        ProxyServer = $p.ProxyServer
        ProxyOverride = $p.ProxyOverride
        AutoConfigURL = $p.AutoConfigURL
        AutoDetectRegistryValue = $p.AutoDetect
        DefaultConnectionSettings = $c.DefaultConnectionSettings
        SavedLegacySettings = $c.SavedLegacySettings
        Note = 'Missing registry values are null. Automatic detection may be encoded in connection settings.'
    }
}
Save-Json 'adapters' {
    Get-NetAdapter -IncludeHidden | Select-Object Name,InterfaceDescription,InterfaceIndex,InterfaceGuid,Status,MacAddress,LinkSpeed
}
Save-Json 'ip-interfaces' {
    Get-NetIPInterface | Select-Object InterfaceAlias,InterfaceIndex,AddressFamily,Dhcp,ConnectionState,InterfaceMetric,AutomaticMetric,NlMtu,Forwarding
}
Save-Json 'ip-addresses' {
    Get-NetIPAddress | Select-Object InterfaceAlias,InterfaceIndex,AddressFamily,IPAddress,PrefixLength,PrefixOrigin,SuffixOrigin,AddressState,SkipAsSource
}
Save-Json 'dns-servers' {
    Get-DnsClientServerAddress | Select-Object InterfaceAlias,InterfaceIndex,AddressFamily,ServerAddresses
}
Save-Json 'dns-client' {
    Get-DnsClient | Select-Object InterfaceAlias,InterfaceIndex,ConnectionSpecificSuffix,RegisterThisConnectionsAddress,UseSuffixWhenRegistering
}
Save-Json 'dns-global' { Get-DnsClientGlobalSetting | Select-Object SuffixSearchList,UseDevolution,DevolutionLevel }
Save-Json 'routes-active' {
    Get-NetRoute -PolicyStore ActiveStore | Select-Object InterfaceAlias,InterfaceIndex,AddressFamily,DestinationPrefix,NextHop,RouteMetric,Protocol,Publish,State
}
Save-Json 'routes-persistent' {
    Get-NetRoute -PolicyStore PersistentStore | Select-Object InterfaceAlias,InterfaceIndex,AddressFamily,DestinationPrefix,NextHop,RouteMetric,Protocol
}

# Registry values distinguish static DNS from DHCP-provided DNS.
Save-Json 'interface-registry' {
    foreach ($base in @('HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces', 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces')) {
        foreach ($key in Get-ChildItem -LiteralPath $base) {
            $p = Get-ItemProperty -LiteralPath $key.PSPath
            [pscustomobject]@{
                RegistryPath = $key.Name
                InterfaceGuid = $key.PSChildName
                EnableDHCP = $p.EnableDHCP
                NameServer = $p.NameServer
                DhcpNameServer = $p.DhcpNameServer
                Domain = $p.Domain
                DhcpDomain = $p.DhcpDomain
                IPAddress = $p.IPAddress
                SubnetMask = $p.SubnetMask
                DefaultGateway = $p.DefaultGateway
            }
        }
    }
}

Save-Command 'ipconfig-all.txt' 'ipconfig.exe' @('/all')
Save-Command 'winhttp-proxy.txt' 'netsh.exe' @('winhttp','show','proxy')
Save-Command 'winhttp-dump.txt' 'netsh.exe' @('winhttp','dump')
Save-Command 'ipv4-dump.txt' 'netsh.exe' @('interface','ipv4','dump')
Save-Command 'ipv6-dump.txt' 'netsh.exe' @('interface','ipv6','dump')
Save-Command 'route-print.txt' 'route.exe' @('print')
Save-Command 'proxy-registry-export-log.txt' 'reg.exe' @('export','HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',(Join-Path $folder 'InternetSettings.reg'),'/y')

try {
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\drivers\etc\hosts') -Destination (Join-Path $folder 'hosts.txt')
} catch { $script:issues.Add('hosts: ' + $_.Exception.Message) }

$complete = $script:issues.Count -eq 0
[pscustomobject]@{
    CollectionComplete = $complete
    IssueCount = $script:issues.Count
    Issues = @($script:issues.ToArray())
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $folder 'collection-status.json') -Encoding UTF8

@'
This folder is a read-only snapshot of local Windows network settings.
Check collection-status.json for missing items or permission errors.
For a useful baseline, capture when the proxy app is off and normal websites work.
DHCP addresses, active routes and virtual adapters may be temporary.
Do not blindly import .reg files or execute netsh dumps on another network or PC.
InternetSettings.reg includes more Internet Settings than just proxy settings.
No automatic restoration is included. Browser extensions, browser-specific DNS,
proxy app subscriptions, VPN credentials and Wi-Fi passwords are not collected.
The snapshot can contain usernames, MAC/IP addresses, internal domains and private
proxy/PAC URLs. Keep it private and review it before sharing.
'@ | Set-Content -LiteralPath (Join-Path $folder 'READ-ME.txt') -Encoding UTF8

Write-Host ''
Write-Host ('Saved to: ' + $folder) -ForegroundColor Green
if (-not $complete) {
    Write-Host 'Partial export: see collection-status.json for details.' -ForegroundColor Yellow
    foreach ($issue in $script:issues) { Write-Host ('  ' + $issue) }
    exit 2
}
Write-Host 'Export complete. No network settings were changed.'
exit 0
