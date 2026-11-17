# pfSense side of the site-to-site VPN

The Azure side is created by the Deploy workflow (VPN on). Its run summary shows
`vpnGatewayPublicIp`. The values below must match `infra/modules/vpn.bicep`.

## Before you start

- `ON_PREM_PUBLIC_IP` (GitHub variable) = the public IP of the network your GNS3 host is on
  (`curl ifconfig.me`). pfSense sits behind NAT (GNS3 NAT + home router), so pfSense must
  **start** the tunnel; NAT traversal (UDP 4500) handles the rest. No port forwarding is needed
  in most home routers. If the tunnel does not come up, forward UDP 500 and 4500 to the GNS3 host.

## Phase 1 – VPN → IPsec → Tunnels → Add P1

| Setting | Value |
|---|---|
| Key exchange version | IKEv2 |
| Interface | WAN |
| Remote gateway | `vpnGatewayPublicIp` from the run summary |
| Authentication | Mutual PSK |
| My identifier | IP address → your `ON_PREM_PUBLIC_IP` (needed behind NAT) |
| Peer identifier | Peer IP address |
| Pre-shared key | the GitHub secret `VPN_SHARED_KEY` |
| Encryption | AES 256, hash SHA256, DH group 14 (2048 bit) |
| Lifetime | 28800 |
| NAT traversal | Auto |
| Dead Peer Detection | enabled |
| Child SA start action | Initiate at start |

## Phase 2 – one entry per on-prem network

| Local network | Remote network |
|---|---|
| `10.32.0.0/24` (SRV) | `10.20.0.0/16` (spoke) |
| `10.64.0.0/24` (MGMT) | `10.20.0.0/16` (spoke) |

Mode Tunnel IPv4, protocol ESP, AES 256, SHA256, PFS group 14, lifetime 3600.
"Initiate at start" in phase 1 plus Dead Peer Detection keep the tunnel up from the pfSense side.

## Firewall rules on pfSense

The CS1 rules block `PrivateNets`, which includes `10.20.0.0/16`. Add these **above** the block rules:

| Interface | Source | Destination | Port | Why |
|---|---|---|---|---|
| SRV | SRV net | `10.20.4.0/23` | TCP 443 | Monitor → API |
| SRV | SRV net | `10.20.3.0/24` | TCP 3306 | Validate the database privately |
| MGMT | MGMT net | `10.20.4.0/23` | TCP 443 | Staff → internal app |
| SRV, MGMT | net | `10.20.0.0/16` | ICMP | Testing |

No rules are needed on the IPsec tab for these: return traffic is allowed by the state table.
Guests (GST) and the DMZ get no rule, so they cannot reach the cloud.

## Check

- **Status → IPsec**: the tunnel shows *Established* and both child SAs are installed.
- Azure portal → KH-VPN-Connection: status *Connected*.
- From the Monitor server: `curl -s https://kh-monitoring-api.<domain>/health`.
