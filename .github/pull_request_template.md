## **Scripts which are clearly AI generated and not further revised by the Author of this PR (in terms of Coding Standards and Script Layout) may be closed without review.**

## ✍️ Description  
<!-- Briefly describe your changes. -->  

## 🔗 Related PR / Issue  

Link: #

## ✅ Prerequisites  (**X** in brackets) 

- [ ] **Self-review completed** – Code follows project standards.  
- [ ] **Tested thoroughly** – Changes work as expected.  
- [ ] **No breaking changes** – Existing functionality remains intact.  
- [ ] **No security risks** – No hardcoded secrets, unnecessary privilege escalations, or permission issues.  

---

## 🏗️ arm64 Support (**X** in brackets)

- [ ] **arm64 supported** - Tested and supported on arm64.
- [ ] **arm64 not tested** - Assumed to work on arm64, but testing has not been done.
- [ ] **arm64 not supported** - Confirmed upstream dependencies or binaries do not support arm64.

---

## 🛠️ Type of Change (**X** in brackets)  

- [ ] 🐞 **Bug fix** – Resolves an issue without breaking functionality.  
- [ ] ✨ **New feature** – Adds new, non-breaking functionality.  
- [ ] 💥 **Breaking change** – Alters existing functionality in a way that may require updates.  
- [ ] 🆕 **New script** – A fully functional and tested script or script set.  
- [ ] 🌍 **Website update** – Changes to website-related JSON files or metadata.  
- [ ] 🔧 **Refactoring / Code Cleanup** – Improves readability or maintainability without changing functionality.  
- [ ] 📝 **Documentation update** – Changes to `README`, `AppName.md`, `CONTRIBUTING.md`, or other docs.  

---

## 🔍 Code & Security Review  (**X** in brackets) 

- [ ] **Follows `CODE-AUDIT.md` & `CONTRIBUTING.md` guidelines**  
- [ ] **Uses correct script structure (`AppName.sh`, `AppName-install.sh`, `AppName.json`)**  
- [ ] **No hardcoded credentials**  
- [ ] **No Docker / Docker Compose** – The application is installed bare-metal; Docker is not used.
- [ ] **No git pull** – Updates use `fetch_and_deploy_gh_release`, `fetch_and_deploy_codeberg_release`, `fetch_and_deploy_gl_release`, or `fetch_and_deploy_from_url` instead of `git pull`.

---

## 🤖 AI Assistance (**X** in brackets)

> If you used an AI tool (GitHub Copilot, Claude, ChatGPT, etc.) to write or generate any scripts in this PR, you **must** confirm compliance below.  
> Select exactly one option.

- [ ] **No AI used** – Scripts were written without AI assistance.
- [ ] **AI was used** – I confirm the scripts were built using [`AGENTS.md`](https://github.com/community-scripts/ProxmoxVED/blob/main/AGENTS.md) and [`.github/agents/pve-script-creator.agent.md`](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/agents/pve-script-creator.agent.md) as guidance, and the output has been reviewed and corrected to match those guidelines.

---

## 📋 Additional Information (optional)  
<!-- Add any extra context, screenshots, or references. -->  

---

## 📦 Application Requirements (for new scripts)

> ⚠️ Do not remove this section.
> It is used by automated PR validation checks.
> If this PR is not a new script submission, leave the checkboxes unchecked.

> Required for **🆕 New script** submissions.  
> Pull requests that do not meet these requirements may be closed without review.
- [ ] The application is **at least 6 months old**
- [ ] The application is **actively maintained**
- [ ] The application has **600+ GitHub stars**
- [ ] Official **release tarballs** are published
- [ ] I understand that not all scripts will be accepted due to various reasons and criteria by the community-scripts ORG

## 🌐 Source
<!-- Add any sources and github links. -->  
