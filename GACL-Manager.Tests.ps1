# Requires -Version 5.1
# Requires -Modules Pester

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = Join-Path $here "GACL-Manager.ps1"

Describe "Initialize-GACL" {
    BeforeAll {
        # Dot-source the script to load functions into the current scope
        . $sut
    }

    BeforeEach {
        # Reset script-scoped variables before each test
        $script:GACL_Registry = @{}
        $script:GACL_TokenPath = $null
        $script:GACL_CurrentTenant = $null
    }

    Context "When called with no parameters (Default Behavior)" {
        It "Should operate in volatile memory mode (does not set GACL_TokenPath)" {
            # Arrange
            Mock Write-Host {}

            # Act
            Initialize-GACL

            # Assert
            $script:GACL_TokenPath | Should -BeNullOrEmpty
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -match "Volatile Memory Mode Active" }
        }
    }

    Context "When EnablePersistentStorage is `$true but TokenPath is empty" {
        It "Should fall back to volatile memory mode" {
            # Arrange
            Mock Write-Host {}

            # Act
            Initialize-GACL -EnablePersistentStorage

            # Assert
            $script:GACL_TokenPath | Should -BeNullOrEmpty
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -match "Volatile Memory Mode Active" }
        }
    }

    Context "When EnablePersistentStorage is `$true and TokenPath is provided" {
        It "Should set GACL_TokenPath and not load registry if file does not exist" {
            # Arrange
            $testPath = "C:\fake\path\token.json"
            Mock Test-Path { return $false }
            Mock Write-Host {}
            Mock Get-Content {}

            # Act
            Initialize-GACL -EnablePersistentStorage -TokenPath $testPath

            # Assert
            $script:GACL_TokenPath | Should -Be $testPath
            Assert-MockCalled Test-Path -Times 1 -ParameterFilter { $Path -eq $testPath }
            Assert-MockCalled Get-Content -Times 0
            Assert-MockCalled Write-Host -Times 0 -ParameterFilter { $Object -match "Loading cached Identity Registry" }
        }

        It "Should set GACL_TokenPath and load registry if valid JSON cache exists" {
            # Arrange
            $testPath = "C:\fake\path\token.json"
            $mockJson = '{ "AuthTokens": { "TenantA": "tokenA", "TenantB": "tokenB" }, "LastUpdated": "2023-10-26 12:00:00", "Version": "1.1.0" }'
            Mock Test-Path { return $true }
            Mock Write-Host {}
            Mock Get-Content { return $mockJson }

            # Act
            Initialize-GACL -EnablePersistentStorage -TokenPath $testPath

            # Assert
            $script:GACL_TokenPath | Should -Be $testPath
            $script:GACL_Registry.Count | Should -Be 2
            $script:GACL_Registry["TenantA"] | Should -Be "tokenA"
            $script:GACL_Registry["TenantB"] | Should -Be "tokenB"
            Assert-MockCalled Test-Path -Times 1 -ParameterFilter { $Path -eq $testPath }
            Assert-MockCalled Get-Content -Times 1 -ParameterFilter { $Path -eq $testPath }
        }

        It "Should set GACL_TokenPath, catch exception, and issue warning if file read fails or JSON is invalid" {
            # Arrange
            $testPath = "C:\fake\path\token.json"
            Mock Test-Path { return $true }
            Mock Write-Host {}
            Mock Write-Warning {}
            Mock Get-Content { throw "File lock exception" }

            # Act
            Initialize-GACL -EnablePersistentStorage -TokenPath $testPath

            # Assert
            $script:GACL_TokenPath | Should -Be $testPath
            $script:GACL_Registry.Count | Should -Be 0
            Assert-MockCalled Test-Path -Times 1 -ParameterFilter { $Path -eq $testPath }
            Assert-MockCalled Get-Content -Times 1 -ParameterFilter { $Path -eq $testPath }
            Assert-MockCalled Write-Warning -Times 1 -ParameterFilter { $Message -match "Failed to load registry: File lock exception" }
        }

        It "Should handle cache without AuthTokens property gracefully" {
            # Arrange
            $testPath = "C:\fake\path\token.json"
            $mockJson = '{ "LastUpdated": "2023-10-26 12:00:00", "Version": "1.1.0" }'
            Mock Test-Path { return $true }
            Mock Write-Host {}
            Mock Get-Content { return $mockJson }

            # Act
            Initialize-GACL -EnablePersistentStorage -TokenPath $testPath

            # Assert
            $script:GACL_TokenPath | Should -Be $testPath
            $script:GACL_Registry.Count | Should -Be 0
            Assert-MockCalled Test-Path -Times 1 -ParameterFilter { $Path -eq $testPath }
            Assert-MockCalled Get-Content -Times 1 -ParameterFilter { $Path -eq $testPath }
        }
    }
}
