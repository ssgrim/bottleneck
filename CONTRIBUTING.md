# Contributing to Bottleneck

Thank you for your interest in contributing to Bottleneck! This document provides guidelines and information for contributors.

## 🎯 Ways to Contribute

- **Bug Reports**: Open an issue with detailed reproduction steps
- **Feature Requests**: Describe the feature and use case
- **Code Contributions**: Submit pull requests for fixes or enhancements
- **Documentation**: Improve README, add examples, write guides
- **Testing**: Test on different Windows versions and configurations

## 🚀 Getting Started

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/yourusername/bottleneck.git`
3. **Create a branch**: `git checkout -b feature/your-feature-name`
4. **Make changes** and test thoroughly
5. **Commit**: `git commit -m "Add: description of changes"`
6. **Push**: `git push origin feature/your-feature-name`
7. **Open a Pull Request** with a clear description

## 📝 Code Standards

### PowerShell Style Guide

- **Naming**: Use `PascalCase` for functions, `camelCase` for variables
- **Comments**: Document complex logic and public functions
- **Error Handling**: Use try/catch blocks, avoid silent fails
- **Parameters**: Use `[CmdletBinding()]` and proper validation
- **Logging**: Use `Write-BottleneckLog` for debug/info/error messages

### Example Function
```powershell
function Test-BottleneckMyCheck {
    <#
    .SYNOPSIS
    Brief description of what this check does
    
    .DESCRIPTION
    Detailed description including what it checks and how
    
    .EXAMPLE
    Test-BottleneckMyCheck
    #>
    [CmdletBinding()]
    param()
    
    try {
        Write-BottleneckLog "Starting MyCheck" -Level "DEBUG" -CheckId "MyCheck"
        
        # Your diagnostic logic here
        $result = Get-SomeData
        
        return New-BottleneckResult `
            -Id 'MyCheck' `
            -Tier 'Standard' `
            -Category 'My Category' `
            -Impact 5 `
            -Confidence 8 `
            -Effort 2 `
            -Priority 3 `
            -Evidence "Data: $result" `
            -FixId 'MyFix' `
            -Message "Check completed: $result"
    } catch {
        Write-BottleneckLog "MyCheck failed: $_" -Level "ERROR" -CheckId "MyCheck"
        return $null
    }
}
```

## 🧪 Testing

Before submitting a PR:

1. **Test all scan tiers**: Quick, Standard, Deep
2. **Verify report generation**: HTML output renders correctly
3. **Check error handling**: Test with and without admin rights
4. **Validate on multiple systems**: Windows 10 and 11 if possible
5. **Review logs**: Check for errors in Reports/*.log files

### Running Tests
```powershell
# Import module
Import-Module .\src\ps\Bottleneck.psm1 -Force

# Run Quick scan test
$results = Invoke-BottleneckScan -Tier Quick
Invoke-BottleneckReport -Results $results -Tier Quick

# Verify no errors
Get-Content .\Reports\bottleneck-$(Get-Date -Format 'yyyy-MM-dd').log | Select-String "ERROR"
```

## 🐛 Bug Reports

When reporting bugs, include:

- **PowerShell Version**: `$PSVersionTable.PSVersion`
- **Windows Version**: `Get-ComputerInfo | Select WindowsVersion, OSArchitecture`
- **Error Message**: Full error text and stack trace
- **Steps to Reproduce**: Detailed steps that consistently trigger the bug
- **Expected vs Actual Behavior**: What should happen vs what does happen
- **Log File**: Attach relevant portions of the log file

## 💡 Feature Requests

For new features, describe:

- **Use Case**: Why is this feature needed?
- **Proposed Solution**: How should it work?
- **Alternatives Considered**: Other approaches you've thought about
- **Priority**: Critical / High / Medium / Low

## 📋 Pull Request Checklist

- [ ] Code follows PowerShell best practices
- [ ] Function includes comment-based help
- [ ] Changes are logged with `Write-BottleneckLog`
- [ ] Error handling is implemented
- [ ] Tested on Windows 10 or 11
- [ ] Tested with and without admin rights
- [ ] Documentation updated (README.md, TODO.md)
- [ ] No merge conflicts with main branch
- [ ] Commit messages are clear and descriptive

## 🏗️ Project Architecture

### Module Structure
- **Bottleneck.psm1**: Main entry point, orchestrates scans
- **Bottleneck.Checks.ps1**: Defines check tiers and basic checks
- **Bottleneck.Report.ps1**: HTML report generation
- **Bottleneck.Performance.ps1**: CIM caching and timeout wrappers
- **Bottleneck.Logging.ps1**: Centralized logging framework
- **Specialized Modules**: Thermal, Network, Security, UserExperience, etc.

### Adding a New Check Module

1. Create `Bottleneck.MyModule.ps1` in `src/ps/`
2. Add dot-sourcing in `Bottleneck.psm1`: `. $PSScriptRoot/Bottleneck.MyModule.ps1`
3. Register check in `Bottleneck.Checks.ps1` in appropriate tier
4. Add recommendation logic in `Bottleneck.Report.ps1`
5. Document in README.md

## 🎨 Scoring System

Checks return results with these metrics:

- **Impact** (1-10): How much this issue affects performance
- **Confidence** (1-10): How certain we are about the diagnosis
- **Effort** (1-10): How difficult it is to fix
- **Priority** (1-10): User-facing priority ranking

**Score Calculation**: `(Impact × Confidence) ÷ (Effort + 1)`

**Color Coding**:
- 🟢 Green: 0-10 (Good)
- 🟡 Yellow: 11-25 (Minor concern)
- 🟠 Orange: 26-45 (Attention needed)
- 🔴 Red: 46+ (Critical)

## 📞 Questions?

- Open a [GitHub Discussion](https://github.com/yourusername/bottleneck/discussions)
- Check existing [Issues](https://github.com/yourusername/bottleneck/issues)
- Review `docs/` folder for technical documentation

## 🙏 Thank You!

Every contribution, no matter how small, helps make Bottleneck better for everyone. We appreciate your time and effort!
