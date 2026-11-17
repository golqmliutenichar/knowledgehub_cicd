# On-premises name resolution for the private Azure services

Inside Azure the private DNS zones answer automatically. On-premises clients ask the CS1 domain
controller, so it needs the same two zones. This is the low-cost alternative to an Azure DNS
Private Resolver (which would let the DC forward instead, but costs money every hour; the hub has
`DNS-Resolver-Subnet` reserved for it).

## 1. Get the private IPs (Cloud Shell)

```bash
RG=KostovRG
# Database: server name and private endpoint IP
az mysql flexible-server list -g $RG --query "[0].name" -o tsv
az network private-endpoint show -g $RG -n KH-MySQL-PrivateEndpoint \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv
# Container Apps: domain and static IP
az containerapp env show -g $RG -n KH-ContainerApps-Env \
  --query "{domain:properties.defaultDomain, ip:properties.staticIp}" -o table
```

## 2. Create the zones on the domain controller (PowerShell as admin)

```powershell
$dbName   = "kh-monitoring-db-xxxxx"        # from step 1
$dbIp     = "10.20.3.4"
$appsZone = "<defaultDomain>"                # e.g. happy-sea-1234.swedencentral.azurecontainerapps.io
$appsIp   = "10.20.4.x"

Add-DnsServerPrimaryZone -Name "privatelink.mysql.database.azure.com" -ReplicationScope Forest
Add-DnsServerResourceRecordA -ZoneName "privatelink.mysql.database.azure.com" -Name $dbName -IPv4Address $dbIp

Add-DnsServerPrimaryZone -Name $appsZone -ReplicationScope Forest
Add-DnsServerResourceRecordA -ZoneName $appsZone -Name "*" -IPv4Address $appsIp
Add-DnsServerResourceRecordA -ZoneName $appsZone -Name "@" -IPv4Address $appsIp
```

The public name `<dbName>.mysql.database.azure.com` is a CNAME to
`<dbName>.privatelink.mysql.database.azure.com`; because the DC holds that zone, clients get the
private IP. The Container Apps domain only exists privately, so the DC zone is the only answer.

## 3. Check from the Monitor server

```bash
nslookup <dbName>.mysql.database.azure.com     # -> 10.20.3.x
nslookup kh-monitoring-api.<defaultDomain>     # -> 10.20.4.x
nc -zv <dbName>.mysql.database.azure.com 3306  # private connectivity to the database
```
