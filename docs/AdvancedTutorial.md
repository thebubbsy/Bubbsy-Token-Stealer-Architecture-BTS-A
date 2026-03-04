# BTS-A: Advanced Multi-Tenant Registry
### Designing for Global Scale and Parallel Continuity

In an enterprise landscape with multiple tenants (e.g., Parent/Subsidiary acquisitions), a single identity is insufficient. BTS-A implements a **Registry Pattern** to manage complex authentication states.

## 🏛️ The Registry Schema

The Registry is a centralized hashtable that tracks the "State of the Steal" across your entire environment.

### 1. The Sync-and-Map Function
This function automates the discovery of the tenant identity and the extraction of its token.

```powershell
function Sync-BTSAIdentity {
    try {
        $resp = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/organization" -Method GET -OutputType HttpResponseMessage
        $token = $resp.RequestMessage.Headers.Authorization.Parameter
        $org = Get-MgOrganization
        
        return [PSCustomObject]@{
            IdentityKey = $org.Id
            Token       = $token
            DisplayName = $org.DisplayName
            Timestamp   = [DateTime]::Now
        }
    } catch {
        throw "BTS-A Interception Error: Could not synchronize identity."
    }
}
```

### 2. Multi-Tenant Orchestration
Store these identity objects in a Registry to "Pivot" between tenants instantly.

```powershell
$script:BTSARegistry = @{}

# Process Tenant A
Connect-MgGraph -TenantId "TENANT-A-ID"
$script:BTSARegistry["Primary"] = Sync-BTSAIdentity

# Process Tenant B
Connect-MgGraph -TenantId "TENANT-B-ID"
$script:BTSARegistry["Acquisition"] = Sync-BTSAIdentity

# pivot back to Primary without any prompts
$p = $script:BTSARegistry["Primary"]
Connect-MgGraph -AccessToken (ConvertTo-SecureString $p.Token -AsPlainText -Force)
```

## ☄️ High-Performance Parallelism
BTS-A allows you to pass the **entire Registry** into a parallel block, giving child threads full context of every tenant you have permission to access.

```powershell
$users | ForEach-Object -Parallel {
    $reg = $using:script:BTSARegistry
    $token = $reg["Primary"].Token
    
    # Instant re-auth in the thread
    Connect-MgGraph -AccessToken (ConvertTo-SecureString $token -AsPlainText -Force)
}
```
