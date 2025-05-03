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

The Maester Conditional Access Test Generator is a PowerShell tool that automatically generates <a href="https://maester.dev">Maester.dev</a> test for Conditional access, based on your current Conditional Access setup. <a href="https://maester.dev">Maester.dev</a> is a Microsoft Security test automation framework.

TODO: GIF van example report

# 🛠️ Installation

TODO: installation video

```powershell
git clone https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator
cd Maester-Conditional-Access-Test-Generator
Install-Module Microsoft.Graph.Authentication
```

Authenticating can be done with the `Connect-MgGraph` command or with an App Registration. To use an App Registration, create the file `settings.json` in the root of the project and set the credentials in following JSON object:

```json
{
    "tenantID": "",
    "clientID": "",
    "clientSecret": ""
}
```

# 💻 Usage

```powershell
# Connecting with your user account
Connect-MgGraph
.\run.ps1

# Connecting with an App Registration
.\run.ps1

# OR if you want to include CA policies that are in 'report-only' mode
.\run.ps1 -IncludeReportOnly
```

TODO: usage video (timestamp)

# 💡 Hardcoded rules

For each Conditional Access policy, a test is created based on the configured properties in the CA policy itself. Some hard-coded rules:

- Conditional Access policies are imported sorted on their name.
- if the CA policy is scoped on `'All users'`, we limit the scope to 5 random users. These accounts are indicated with `'(random)'` after their UPN
- if the CA policy is scoped on a group (included or excluded), we limit the scope to 5 random users of that group. These accounts are indicated with `'(random)'` after their UPN
- if the CA policy is scoped on `'All guets'`, we limit the scope to 2 random guests. These accounts are indicated with `'(random)'` after their UPN
- if the CA policy is scoped on `'All resources'` cloud apps, we limit the scope to `Office 365 Exchange Online`, `Office 365 SharePoint Online` and `Office 365 Portal`
- if the CA policy is scoped on `Office365` cloud apps, we limit the scope to `Office 365 Exchange Online`, `Office 365 SharePoint Online` and `Office 365 Portal`
- if the CA policy is scoped on more than 3 cloud apps, we limit the scope to the first 3 applications
- if the CA policy is scope on a Named Location, we add tests for each IP range of the Named Location
- if the CA policy is scope on a Named Location, the country of the test will always be `'FR'` (France)

# 🚧 Current limitations
- sign-in risk is not supported   
- insider risk is not supported
- user principal risk is not supported
- device properties are not supported
- session controls are not supported
- excluded guest users are not supported, only included guests are supported
- guest types are not supported. In each case, 2 random guests are chosen for the test.

# 📞 Contact

Jasper Baes (https://www.linkedin.com/in/jasper-baes)

Discovered a bug or do you have an improvement? Create an <a href="https://github.com/jasperbaes/Maester-Conditional-Access-Test-Generator/issues">issue</a>.

# 🆕 Release history

Release version numbers: YEAR.WEEK

- 2025.18
  - initial release (preview)

# 🏁 Roadmap
- Fix: add a check so random chosen users are not excluded from the CA policy
- Add search field and filters to HTML
- Add Sign-in risk, Insider risk and User Principal risk
- Add device properties
- Add other access controls
- Add session controls
- Create tree: add try catch

# 📜 License

Please be aware that this project is only allowed for use by organizations seeking financial gain, on 2 conditions:
- this is communicated to me over LinkedIn
- the header and footer of the HTML report is unchanged. Colors can be changed. Other items can be added.

Thank you for respecting these usage terms and contributing to a fair and ethical software community. 

Jasper Baes (https://www.linkedin.com/in/jasper-baes)

Buy Me a Coffee (https://buymeacoffee.com/jasperbaes)