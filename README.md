# The Knowledge Hub – Hybrid Cloud (CS2)

Azure landing zone, site-to-site VPN to the CS1 lab, a private monitoring API on Azure Container Apps,
MySQL as the central data store, and the CS1 monitoring script extended to send its data there.
Everything is deployed with Bicep from GitHub Actions.

```
knowledgehub_cicd/
├── .github/workflows/
│   ├── deploy.yml        # landing zone + API container (firewall/VPN optional)
│   ├── teardown.yml      # removes firewall + VPN (manual, and every night at 03:00)
│   └── validate.yml      # tests + Bicep lint on every push
├── infra/
│   ├── main.bicep        # the landing zone (one deployment, toggles for firewall/VPN)
│   ├── app.bicep         # the API Container App (deployed after the image is built)
│   ├── governance.bicep  # policies, RBAC, budget – run once by the owner
│   └── modules/          # network, peering, vpn, firewall, database, monitoring, containers, dns
├── api/                  # Flask monitoring API + unit tests + Dockerfile
├── monitor/              # monitoring script v4 (sends to the API) + unit tests
├── scripts/setup-azure.sh
└── docs/                 # API spec, pfSense VPN, on-prem DNS
```

## Design in one table

| Part | Choice | Why |
|---|---|---|
| Network | Hub `10.10.0.0/16` (gateway, firewall), spoke `10.20.0.0/16` (private endpoints `10.20.3.0/24`, Container Apps `10.20.4.0/23`) | Shared connectivity and security in the hub, workloads in the spoke |
| On-prem reach | CS1 SRV `10.32.0.0/24` and MGMT `10.64.0.0/24` only | Guests and DMZ never reach the cloud (least privilege) |
| Hybrid link | S2S VPN, route-based, IKEv2, AES256/SHA256/DH14, static routes | pfSense supports it; no BGP needed for two sites |
| Inspection | Azure Firewall Basic, policy-based rules, UDRs on GatewaySubnet and spoke subnets | All hybrid traffic passes one control point |
| Database | MySQL Flexible Server B1ms, public access disabled, private endpoint + `privatelink.mysql.database.azure.com` | Managed (low admin), cheapest tier, private only |
| API host | Azure Container Apps, **internal** environment (VNet-only IP), private DNS zone for its domain | Container = no lock-in, scale to zero, private by design |
| Images | Azure Container Registry Basic, pulled with a managed identity (no passwords) | |
| Monitoring | Log Analytics, diagnostic settings, alert on database CPU, email action group | |
| Governance | Allowed locations, inherited tags, RBAC per role, monthly budget | `governance.bicep` |
| Login | GitHub OIDC (federated credential) | No client secret that can expire |

## 1. One-time setup (subscription owner, ±10 minutes)

In the Azure portal open **Cloud Shell (Bash)**:

```bash
git clone https://github.com/<you>/knowledgehub_cicd.git && cd knowledgehub_cicd
chmod +x scripts/setup-azure.sh
./scripts/setup-azure.sh <you>/knowledgehub_cicd <your-email>
```

It creates the resource group, the GitHub login (OIDC, no secret), and runs `governance.bicep`.
Then add the printed values in GitHub → **Settings → Secrets and variables → Actions**:

| Secrets | Variables |
|---|---|
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | `ON_PREM_PUBLIC_IP` (run `curl ifconfig.me` at home) |
| `MYSQL_ADMIN_PASSWORD`, `VPN_SHARED_KEY`, `API_KEY` | `ALERT_EMAIL` |

> The script reuses the existing `KnowledgeHub-GitHubActions` app if it is already there, and only
> adds the federated credential (the old client secret is no longer needed).

## 2. Deploy

GitHub → **Actions → Deploy - Knowledge Hub → Run workflow**.

- First run: leave firewall and VPN off. It builds the network, database, registry, Container Apps
  environment and deploys the API (±15 minutes).
- For the hybrid tests: run again with **firewall** and **VPN** on (VPN gateway ±30–45 minutes).
  The run summary shows the VPN gateway IP, the Container Apps domain/static IP and the database name.

## 3. Tear down what costs money

The firewall and the VPN gateway are billed per hour while they exist.

- **Actions → Teardown - firewall and VPN → Run workflow**, type `teardown`.
  Optionally stop the database too (Deploy starts it again).
- The same workflow runs **every night at 03:00** as a safety net. Working later than that? Disable it
  for the night: Actions → Teardown → ⋯ → Disable workflow.

Everything else (network, DNS, registry, environment, API) stays, so the next Deploy brings
firewall and VPN back in one run.

## 4. On-premises side

- pfSense IPsec settings and firewall rules: [docs/pfsense-vpn.md](docs/pfsense-vpn.md)
- DNS records on the domain controller: [docs/onprem-dns.md](docs/onprem-dns.md)

## 5. Monitoring script v4 on the Monitor server

```bash
cd ~/knowledgehub && git pull            # or copy the monitor/ folder
cd monitor && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cp .env.example .env && nano .env        # API_URL and API_KEY
.venv/bin/python monitor.py measure      # test once
crontab -e
*/5 * * * * cd /home/student/knowledgehub/monitor && .venv/bin/python monitor.py measure >> monitor.log 2>&1
```

## 6. Local development

```bash
cd api && pip install -r requirements.txt
python -m unittest discover -s tests -v        # 19 tests
API_KEY=dev flask --app wsgi run -p 8000         # uses SQLite when DB_HOST is not set
cd ../monitor && python -m unittest discover -s tests -v   # 8 tests
```

API endpoints and examples: [docs/API.md](docs/API.md).

## What changed compared to the old pipeline

| Old problem | Fix |
|---|---|
| Jobs had no `needs:`, so firewall/VPN started before the network existed | One `main.bicep` deployment, ARM orders the resources |
| Firewall Basic had classic rules *and* a policy, no management subnet, hard-coded old subscription | Policy-only rules, `AzureFirewallManagementSubnet`, no IDs in code |
| `VpnGw1AZ` with a non-zonal public IP; local gateway pointed at a private GNS3 IP | Zone-redundant IP; local gateway = public IP from a variable |
| On-prem ranges (10.49/10.74/…) did not match the CS1 lab | CS1 ranges 10.32 (SRV) and 10.64 (MGMT), as a parameter |
| `useRemoteGateways: false`, so on-prem could never reach the spoke | Gateway transit on while the gateway exists |
| NSGs and route table created but never attached | Attached to their subnets in the VNet definition |
| Database NSG on a hub subnet while the private endpoint was in the spoke | NSG on the private endpoint subnet, network policies enabled |
| Private DNS record added by hand with CLI | Private DNS zone group keeps the record in sync |
| `--sdk-auth` client secret expired | OIDC federated credential, nothing to expire |
| Subscription IDs and example passwords in the repo | Removed; everything sensitive is a GitHub secret |
