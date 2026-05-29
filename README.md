# Knowledge Hub - Azure Infrastructure

## Setup Instructions

### 1. Repo Structure
```
knowledgehub_cicd/
├── .github/
│   └── workflows/
│       └── pipeline.yml
├── Bicep/
│   ├── Vnets/
│   ├── VPN/
│   ├── NSGs/
│   ├── RouteTables/
│   ├── Firewall/
│   └── Database/
└── README.md
```

### 2. Create Azure Service Principal
Run this in Azure Cloud Shell:
```bash
az ad sp create-for-rbac \
  --name "KnowledgeHub-GitHubActions" \
  --role contributor \
  --scopes /subscriptions/b609dfbe-046a-47da-ab15-5955f83d52ec \
  --sdk-auth
```
Copy the entire JSON output.

### 3. Add GitHub Secrets
Go to your repo → Settings → Secrets and variables → Actions → New repository secret

| Secret Name | Value |
|---|---|
| AZURE_CREDENTIALS | The full JSON from step 2 |
| VPN_SHARED_KEY | A strong password e.g. KH@Azure2024! |
| MYSQL_PASSWORD | A strong password e.g. KH@MySQL2024! |

### 4. Run the Pipeline
Go to Actions → Knowledge Hub Infrastructure Deployment → Run workflow

Options:
- deploy_firewall: true/false (deploy Azure Firewall — costs money)
- deploy_database: true/false (deploy MySQL)
