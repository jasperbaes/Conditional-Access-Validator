<br>
<p align="center">
  <a href="https://jbaes.be/CAB">
    <img src="./assets/logo.png" alt="Logo" height="80">
  </a>
  <h3 align="center">Maester Conditional Access Test Generator</h3>
  <p align="center">
    By Jasper Baes
    <br />
    <a href="https://github.com/jasperbaes/Conditional-Access-Persona-Report#%EF%B8%8F-installation">Installation</a>
    ·
     <a href="https://github.com/jasperbaes/Conditional-Access-Persona-Report#-usage">Usage</a>
    ·
    <a href="https://github.com/jasperbaes/Conditional-Access-Persona-Report/issues">Report Bug</a>
    ·
     <a href="https://www.jbaes.be/CAB">Conditional Access Blueprint</a>
  </p>
</p>

The Conditional Access Persona Report is part of tool #3 in the <a href="https://www.jbaes.be/CAB">Conditional Access Blueprint</a>, a CA framework.

# 🚀 About

The Conditional Access Persona Report is a PowerShell script that generates a HTML report of all included and excluded Personas of your Conditional Access Policies. This follows the persona-approach of the <a href="https://www.jbaes.be/CAB">Conditional Access Blueprint</a> where the goal is to use a static set Conditional Access policies and only add/remove personas (=Entra groups) as needed.

TODO: GIF van example report

Features:
- HTML report of CA Personas
- 'Add' and 'Remove' buttons that can link to a MSSP support page so customers can request changes
- Automatic generated Maester tests

# 🛠️ Installation

TODO: installation video

```powershell
git clone https://github.com/jasperbaes/Conditional-Access-Persona-Report
cd Conditional-Access-Persona-Report
Install-Module Microsoft.Graph.Authentication
```

Authenticating can be done with the `Connect-MgGraph` command or with an App Registration. To use an App Registration, set the credentials in the `settings.json` file:

```json
{
    "tenantID": "",
    "clientID": "",
    "clientSecret": "",
    "organizationName": "My Organization",
    "removePersonaURL": "",
    "addPersonaURL": ""
}
```

| JSON key           |               Description |
| ----------------- | --------------------------------------------------------------: |
| tenantID | Required field when authenticating with App Registration.|
| clientID | Required field when authenticating with App Registration.|
| clientSecret | Required field when authenticating with App Registration.|
| organizationName | Required field.|
| removePersonaURL | Optional field. If you provide this HTML report to customers as part of you MSSP service, `removePersonaURL` can be the link to your Jira, ServiceNow, Microsoft Forms, ... for customers to request a change. Or, you can fill in `mailto:jasper.baes@company.org` to redirect to an email. When `removePersonaURL` is empty, it automatically redirects to the Entra Portal. |
| addPersonaURL | Optional field. If you provide this HTML report to customers as part of you MSSP service, `addPersonaURL` can link to your Jira, ServiceNow, Microsoft Forms, ... for customers to request a change. Or, you can fill in `mailto:jasper.baes@company.org` to redirect to an email. When `addPersonaURL` is empty, it automatically redirects to the Entra Portal.|

# 💻 Usage

```powershell
Connect-MgGraph
.\Create-ConditionalAccessPersonaReport.ps1
```

TODO: usage video (timestamp)

# 📞 Contact

Jasper Baes (https://www.linkedin.com/in/jasper-baes)

Discovered a bug or do you have an improvement? Create an <a href="https://github.com/jasperbaes/Conditional-Access-Persona-Report/issues">issue</a>.

# 🆕 Release history

Release version numbers: YEAR.WEEK

- 2025.18
  - initial release

# 🤝 Contributors

- Jasper Baes (https://www.linkedin.com/in/jasper-baes)
- Robbe Van den Daele (https://www.linkedin.com/in/robbe-van-den-daele-677986190)
- Thor Nicolaï (https://www.linkedin.com/in/thornicolai)

# 📜 License

Please be aware that the Conditional Access Persona Report code is allowed for use by organizations seeking financial gain, on 2 conditions:
- this is communicated to me
- the header and footer of the HTML report is unchanged. The name of your company can be added.

Thank you for respecting these usage terms and contributing to a fair and ethical software community. 

Jasper Baes (https://www.linkedin.com/in/jasper-baes)

Buy Me a Coffee (https://buymeacoffee.com/jasperbaes)