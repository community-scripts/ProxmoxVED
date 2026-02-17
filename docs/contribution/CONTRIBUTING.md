
# Community Scripts Contribution Guide

## **Welcome to the communty-scripts Repository!** 

📜 These documents outline the essential coding standards for all our scripts and JSON files. Adhering to these standards ensures that our codebase remains consistent, readable, and maintainable. By following these guidelines, we can improve collaboration, reduce errors, and enhance the overall quality of our project.

### Why Coding Standards Matter

Coding standards are crucial for several reasons:

1. **Consistency**: Consistent code is easier to read, understand, and maintain. It helps new team members quickly get up to speed and reduces the learning curve.
2. **Readability**: Clear and well-structured code is easier to debug and extend. It allows developers to quickly identify and fix issues.
3. **Maintainability**: Code that follows a standard structure is easier to refactor and update. It ensures that changes can be made with minimal risk of introducing new bugs.
4. **Collaboration**: When everyone follows the same standards, it becomes easier to collaborate on code. It reduces friction and misunderstandings during code reviews and merges.

### Scope of These Documents

These documents cover the coding standards for the following types of files in our project:

- **`install/$AppName-install.sh` Scripts**: These scripts are responsible for the installation of applications.
- **`ct/$AppName.sh` Scripts**: These scripts handle the creation and updating of containers.
- **`json/$AppName.json`**: These files store structured data and are used for the website.

Each section provides detailed guidelines on various aspects of coding, including shebang usage, comments, variable naming, function naming, indentation, error handling, command substitution, quoting, script structure, and logging. Additionally, examples are provided to illustrate the application of these standards.

By following the coding standards outlined in this document, we ensure that our scripts and JSON files are of high quality, making our project more robust and easier to manage. Please refer to this guide whenever you create or update scripts and JSON files to maintain a high standard of code quality across the project. 📚🔍

Let's work together to keep our codebase clean, efficient, and maintainable! 💪🚀


## Getting Started

Before contributing, please ensure that you have the following setup:

1. **Visual Studio Code** (recommended for script development)
2. **Recommended VS Code Extensions:**
   - [Shell Syntax](https://marketplace.visualstudio.com/items?itemName=bmalehorn.shell-syntax)
   - [ShellCheck](https://marketplace.visualstudio.com/items?itemName=timonwong.shellcheck)
   - [Shell Format](https://marketplace.visualstudio.com/items?itemName=foxundermoon.shell-format)

### Important Notes
- Use [AppName.sh](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/ct/AppName.sh) and [AppName-install.sh](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/install/AppName-install.sh) as templates when creating new scripts.

---

# 🚀 The Application Script (ct/AppName.sh)

- You can find all coding standards, as well as the structure for this file [here](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/ct/AppName.md).
- These scripts are responsible for container creation, setting the necessary variables and handling the update of the application once installed.

---

# 🛠 The Installation Script (install/AppName-install.sh)

- You can find all coding standards, as well as the structure for this file [here](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/install/AppName-install.md).
- These scripts are responsible for the installation of the application.

---

## 🚀 Building Your Own Scripts

Start with the [template script](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/install/AppName-install.sh)

---

## 🤝 Contribution Process

### 1. Fork the repository
Fork to your GitHub account

### 2. Clone your fork on your local environment 
```bash
git clone https://github.com/yourUserName/ForkName
```

### 3. Create a new branch
```bash
git switch -c your-feature-branch
```

### 4. Testing Scripts From Your Fork (Development)
To test scripts from your own fork or branch, you no longer need to edit any files. The recommended method is to set the `PVE_SCRIPT_BASE_URL` environment variable and then run the script using the `curl | bash` method, pointing to your fork.

**Example:**
```bash
# 1. Set the base URL to your feature branch
export PVE_SCRIPT_BASE_URL="https://raw.githubusercontent.com/YOUR_USER/ProxmoxVED/YOUR_BRANCH"

# 2. Run the script from your branch using curl
bash -c "$(curl -fsSL ${PVE_SCRIPT_BASE_URL}/ct/myapp.sh)"
```
This method ensures that both the entrypoint script (`myapp.sh`) and all its dependencies (`build.func`, `myapp-install.sh`, etc.) are fetched from your specified branch.

If the `PVE_SCRIPT_BASE_URL` variable is not set, the scripts will default to the main `community-scripts/ProxmoxVED` repository.

**To return to the default behavior, unset the variable:**
```bash
unset PVE_SCRIPT_BASE_URL
```

### 5. Commit changes
```bash
git commit -m "Your commit message"
```

### 6. Push to your fork
```bash
git push origin your-feature-branch
```

### 7. Create a Pull Request
Open a Pull Request from your feature branch to the main repository branch. You must only include your **$AppName.sh**, **$AppName-install.sh** and **$AppName.json** files in the pull request.

---

## 📚 Pages

- [CT Template: AppName.sh](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/ct/AppName.sh)
- [Install Template: AppName-install.sh](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/install/AppName-install.sh)
- [JSON Template: AppName.json](https://github.com/community-scripts/ProxmoxVED/blob/main/.github/CONTRIBUTOR_AND_GUIDES/json/AppName.json)
