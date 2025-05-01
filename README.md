<br>
<p align="center">
  <a href="https://jbaes.be/CAB">
    <img src="./assets/logo.png" alt="Logo" height="80">
  </a>
  <h3 align="center">Maester Conditional Access Test Generator</h3>
  <p align="center">
    By Jasper Baes
    <br />
    <a href="https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator#%EF%B8%8F-installation">Installation</a>
    ·
     <a href="https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator#-usage">Usage</a>
    ·
    <a href="https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator/issues">Report Bug</a>
    ·
     <a href="https://www.jbaes.be/CAB">Conditional Access Blueprint</a>
  </p>
</p>

The Maester Conditional Access Test Generator is part of tool #4 in the <a href="https://www.jbaes.be/CAB">Conditional Access Blueprint</a>, a CA framework.

# 🚀 About

The Maester Conditional Access Test Generator is a PowerShell tool that automatically generates Maester.dev test for Conditional access, based on your current Conditional Access setup.

TODO: GIF van example report

# 🛠️ Installation

TODO: installation video

```powershell
git clone https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator
cd Maester-Conditional-Access-Test-Generator
Install-Module Microsoft.Graph.Authentication
```

Authenticating can be done with the `Connect-MgGraph` command or with an App Registration. To use an App Registration, set the credentials in the `settings.json` file:

```json
{
    "tenantID": "",
    "clientID": "",
    "clientSecret": "",
    "organizationName": "My Organization",
}
```

| JSON key           |               Description |
| ----------------- | --------------------------------------------------------------: |
| tenantID | Required field when authenticating with App Registration.|
| clientID | Required field when authenticating with App Registration.|
| clientSecret | Required field when authenticating with App Registration.|
| organizationName | Required field.|

# 💻 Usage

```powershell
Connect-MgGraph
.\run.ps1

.\run.ps1 -IncludeReportOnly
```

TODO: usage video (timestamp)

# 📞 Contact

Jasper Baes (https://www.linkedin.com/in/jasper-baes)

Discovered a bug or do you have an improvement? Create an <a href="https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator/issues">issue</a>.

# 🆕 Release history

Release version numbers: YEAR.WEEK

- 2025.18
  - initial release (preview)

# 🤝 Contributors

- Jasper Baes (https://www.linkedin.com/in/jasper-baes)

# 📜 License

Please be aware that this project is not allowed for use by organizations seeking financial gain. If interested, contact me. For all generated reports, the header and footer of the HTML report must be unchanged.

Thank you for respecting these usage terms and contributing to a fair and ethical software community. 

Jasper Baes (https://www.linkedin.com/in/jasper-baes)

Buy Me a Coffee (https://buymeacoffee.com/jasperbaes)