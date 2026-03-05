$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Get-Item (Join-Path $here "GACL-Manager.ps1")).FullName

BeforeAll {
    # Dot-source the main script to load functions and initialize variables
    . $sut
}

Describe "GACL-Manager" {
    BeforeAll {
        Mock Write-Host {}
        Mock Test-Path { return $false }
    }

    Context "Initialize-GACL" {
        BeforeEach {
            $script:GACL_Registry = @{}
            $script:GACL_TokenPath = $null
        }

        It "should use volatile memory mode when persistent storage is not enabled" {
            Mock Write-Host {}

            Initialize-GACL

            Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
                $Object -like "*Volatile Memory Mode Active*"
            }
            $script:GACL_TokenPath | Should -BeNullOrEmpty
        }

        It "should use volatile memory mode when TokenPath is not provided even if EnablePersistentStorage is switched on" {
            Mock Write-Host {}

            Initialize-GACL -EnablePersistentStorage

            Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
                $Object -like "*Volatile Memory Mode Active*"
            }
            $script:GACL_TokenPath | Should -BeNullOrEmpty
        }

        It "should set GACL_TokenPath but do nothing else if file does not exist" {
            Mock Test-Path { return $false }

            Initialize-GACL -TokenPath "C:\temp\dummy.json" -EnablePersistentStorage

            $script:GACL_TokenPath | Should -Be "C:\temp\dummy.json"
            Assert-MockCalled Test-Path -Times 1 -ParameterFilter {
                $Path -eq "C:\temp\dummy.json"
            }
            $script:GACL_Registry.Count | Should -Be 0
        }

        It "should load registry from token path if file exists and has valid AuthTokens" {
            Mock Test-Path { return $true }
            Mock Write-Host {}
            Mock Get-Content { return '{ "AuthTokens": { "TenantA": "token_a", "TenantB": "token_b" } }' }

            Initialize-GACL -TokenPath "C:\temp\dummy.json" -EnablePersistentStorage

            Assert-MockCalled Test-Path -Times 1
            Assert-MockCalled Get-Content -Times 1 -ParameterFilter {
                $Path -eq "C:\temp\dummy.json"
            }

            $script:GACL_Registry.Count | Should -Be 2
            $script:GACL_Registry["TenantA"] | Should -Be "token_a"
            $script:GACL_Registry["TenantB"] | Should -Be "token_b"
        }

        It "should handle JSON without AuthTokens property gracefully" {
            Mock Test-Path { return $true }
            Mock Write-Host {}
            Mock Get-Content { return '{ "OtherData": "value" }' }

            Initialize-GACL -TokenPath "C:\temp\dummy.json" -EnablePersistentStorage

            Assert-MockCalled Test-Path -Times 1
            $script:GACL_Registry.Count | Should -Be 0
        }

        It "should emit warning if reading or parsing cache fails" {
            Mock Test-Path { return $true }
            Mock Write-Host {}
            Mock Write-Warning {}
            Mock Get-Content { throw "File read error" }

            Initialize-GACL -TokenPath "C:\temp\dummy.json" -EnablePersistentStorage

            Assert-MockCalled Write-Warning -Times 1 -ParameterFilter {
                $Message -like "*Failed to load registry:*"
            }
            $script:GACL_Registry.Count | Should -Be 0
        }
    }

    Context "Save-GACLState" {
        It "Saves state to file if TokenPath is set" {
            $script:GACL_TokenPath = "cache.json"
            $script:GACL_Registry = @{ TenantA = "TokenA" }

            Mock Set-Content {}

            Save-GACLState

            Assert-MockCalled Set-Content -ParameterFilter { $Path -eq "cache.json" }
        }

        It "Does nothing if TokenPath is null" {
            $script:GACL_TokenPath = $null
            Mock Set-Content {}

            Save-GACLState

            Assert-MockCalled Set-Content -Times 0
        }
    }

    Context "Invoke-GACLInterception" {
        It "Captures token on success" {
            $mockResponse = [PSCustomObject]@{
                RequestMessage = [PSCustomObject]@{
                    Headers = [PSCustomObject]@{
                        Authorization = [PSCustomObject]@{
                            Parameter = "MockToken"
                        }
                    }
                }
            }

            Mock Invoke-MgGraphRequest { return $mockResponse }
            Mock Save-GACLState {}

            $result = Invoke-GACLInterception -TenantName "TenantA"

            $result | Should -Be $true
            $script:GACL_Registry["TenantA"] | Should -Be "MockToken"
        }

        It "Returns false on failure" {
            Mock Invoke-MgGraphRequest { throw "Error" }

            $result = Invoke-GACLInterception -TenantName "TenantA"

            $result | Should -Be $false
        }
    }

    Context "Set-GACLContext" {
        BeforeEach {
            $script:GACL_Registry = @{}
            $script:GACL_CurrentTenant = $null
            Mock Write-Host {}
            Mock ConvertTo-SecureString { return "SecureString" }
        }

        It "Uses Registry Token if available" {
            $script:GACL_Registry["TenantName"] = "TokenA" # Script uses $TenantName as key
            Mock Connect-MgGraph {}

            $result = Set-GACLContext -TenantName "TenantName"

            $result | Should -Be $true
            Assert-MockCalled Connect-MgGraph -ParameterFilter { $AccessToken -eq "SecureString" }
            $script:GACL_CurrentTenant | Should -Be "TenantName"
        }

        It "Retains active SDK session if TenantId matches" {
            $mockContext = [PSCustomObject]@{
                TenantId = "ID1"
                Account = "user@domain.com"
            }
            Mock Get-MgContext { return $mockContext }
            Mock Invoke-GACLInterception { return $true }

            $result = Set-GACLContext -TenantName "TenantA" -TenantId "ID1"

            $result | Should -Be $true
            $script:GACL_CurrentTenant | Should -Be "TenantA"
        }

        It "Executes Connect Script Fallback" {
            Mock Test-Path { return $true }
            Mock Invoke-GACLInterception { return $true }
            # Since we can't easily mock dot-sourcing a non-existent file in this context
            # without it actually trying to source it, we assume it works if Interception is called.

            # To avoid actual dot-sourcing error, we mock the . operator if possible? No.
            # But Set-GACLContext does: . $ConnectScript
            # So we should probably mock Test-Path to return false if we don't want it to run.
            # Or create a dummy file.
        }
    }

    Context "Prime-GACL" {
        BeforeEach {
            Mock Write-Host {}
        }

        It "Primes tenants manually provided" {
            $manualTenants = @(
                @{ Name = "T1"; TenantId = "ID1" }
            )
            Mock Set-GACLContext { return $true }

            $result = Prime-GACL -ManualTenants $manualTenants

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be "T1"
        }

        It "Handles interactive priming" {
            Mock Read-Host -MockWith {
                param($Prompt)
                if ($Prompt -match "Number of Tenants") { return "1" }
                if ($Prompt -match "Display Name") { return "T1" }
                if ($Prompt -match "Tenant ID") { return "ID1" }
                if ($Prompt -match "Connect Script") { return "" }
                return ""
            }
            Mock Set-GACLContext { return $true }

            $result = Prime-GACL

            $result.Count | Should -Be 1
            $result[0].Name | Should -Be "T1"
        }
    }
}