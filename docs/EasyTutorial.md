# BTS-A: Basic Identity Interception
### The "Hello World" of Token Interception

The goal of this core pattern is to establish a bridge between the managed Microsoft Graph SDK and your custom execution logic.

## 🛠️ The Implementation Schema

Once you have established a primary connection via `Connect-MgGraph`, implement the interception block:

```powershell
# 1. Trigger Identity Synchronization
# We call 'me' to force the SDK to generate and verify an active Bearer token.
$sync = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/v1.0/me" -Method GET -OutputType HttpResponseMessage

# 2. Extract the Identity Token
# BTS-A targets the RequestMessage headers specifically.
$identityToken = $sync.RequestMessage.Headers.Authorization.Parameter

# 3. Project Identity to REST Layer
$authHeader = @{ Authorization = "Bearer $identityToken" }
$me = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/me" -Headers $authHeader
```

## 📝 Key Principle
By opting for `HttpResponseMessage`, we are not just getting data—we are getting the **metadata of the transaction**. This is the foundational stone of the BTS-A architecture.
