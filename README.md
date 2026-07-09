# Keycloak + NiFi on AWS — Terraform Tutorial Project

Two EC2 servers, built entirely with code: **Keycloak** (the security desk that checks usernames and passwords) and **Apache NiFi** (the data factory), wired together so NiFi logins go through Keycloak.

> 📖 **New to all of this?** Read **GUIDE.md** first — it explains every concept (EC2, VPCs, subnets, security groups, ports, OIDC) in plain language, step by step. This README is the quick-start version.

---

## What's in this folder

```
keycloak-nifi-tutorial/
├── README.md                        <- you are here (quick start)
├── GUIDE.md                         <- the full beginner-friendly guide
├── CLI-GUIDE.md                     <- build the SAME thing with raw AWS CLI commands
├── terraform/
│   ├── providers.tf                 <- "we're using AWS"
│   ├── variables.tf                 <- the settings you can change
│   ├── network.tf                   <- VPC, subnet, internet gateway
│   ├── security.tf                  <- security groups (the bouncers)
│   ├── servers.tf                   <- the two EC2 instances
│   ├── outputs.tf                   <- prints IPs and URLs when done
│   └── terraform.tfvars.example     <- copy to terraform.tfvars, add your IP
├── docker/
│   ├── keycloak/docker-compose.yml  <- run Keycloak anywhere with Docker
│   └── nifi/docker-compose.yml      <- run NiFi anywhere with Docker
└── scripts/
    ├── configure-nifi-oidc.sh       <- one script to switch NiFi to Keycloak login
    ├── user-data-keycloak.sh        <- first-boot script for the Keycloak server
    └── user-data-nifi.sh            <- first-boot script for the NiFi server
```

**Two ways to build the servers — pick one:**
- **Terraform** (recommended): follow the Quick Start below.
- **AWS CLI** (educational): follow **CLI-GUIDE.md**, which runs the same build command-by-command using the `user-data-*.sh` scripts.

The two `docker-compose.yml` files are the exact same setups that Terraform installs on the EC2 servers automatically (via `user_data`). They're included separately so you can:
- read them to understand what's running on each server, or
- practice on your own laptop first — `docker compose up -d` in either folder, no AWS needed.

---

## Prerequisites

1. An **AWS account** (⚠️ this costs ~$0.06–$0.10/hour — destroy when done!)
2. **Terraform** ≥ 1.5 installed
3. **AWS CLI** installed and configured (`aws configure`)
4. An **SSH key**: `ssh-keygen -t ed25519 -f ~/.ssh/tutorial-key`
5. Your **public IP** from https://checkip.amazonaws.com

---

## Quick Start (10 steps)

### 1. Set your variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: put in YOUR IP address (keep the /32!)
```

### 2. Build everything

```bash
terraform init
terraform plan      # dress rehearsal - nothing is created
terraform apply     # type "yes" - takes ~3 minutes
```

Terraform prints the URLs and IPs you need (`keycloak_url`, `nifi_url`, `nifi_redirect_uri`, etc.). **Wait another ~5 minutes** for the servers to install Docker and pull images.

### 3. Log in to Keycloak

Open the `keycloak_url` output → log in with `admin` / `ChangeMeAdmin123!` (or whatever you set in `terraform.tfvars`).

### 4. Create the realm

Top-left dropdown → **Create realm** → name it exactly `nifi` → **Create**.

### 5. Create the client

**Clients → Create client**
- Client ID: `nifi`
- **Client authentication: ON** (next screen)
- Valid redirect URI: the `nifi_redirect_uri` Terraform output
- Valid post logout redirect URI: the `nifi_logout_uri` output

Then open the client's **Credentials** tab and **copy the Client Secret**.

### 6. Create users

**Users → Create new user**, twice:

| Username | Email | Password | Email verified |
|----------|-------|----------|----------------|
| alice | alice@example.com | AlicePassword123! | ON |
| bob | bob@example.com | BobPassword123! | ON |

Set each password under the **Credentials** tab with **Temporary: OFF**. Alice will become NiFi's administrator.

### 7. Copy the script to the NiFi server

```bash
scp -i ~/.ssh/tutorial-key ../scripts/configure-nifi-oidc.sh ubuntu@NIFI_IP:~/
```

(Get `NIFI_IP` from the `nifi_public_ip` output.)

### 8. Run the script on the NiFi server

```bash
ssh -i ~/.ssh/tutorial-key ubuntu@NIFI_IP
./configure-nifi-oidc.sh KEYCLOAK_IP YOUR_CLIENT_SECRET alice@example.com
```

It checks connectivity, rewrites `nifi.properties` and `authorizers.xml`, and restarts NiFi. Wait 2–3 minutes.

### 9. Test the login 🎉

Open a **fresh incognito window** → `https://NIFI_IP:8443/nifi` → click through the certificate warning → you're redirected to **Keycloak** → log in as `alice` / `AlicePassword123!` → you land on the NiFi canvas as admin.

Bob can log in too, but has no permissions until Alice grants them (☰ menu → Users, then Policies).

### 10. Tear it all down when finished

```bash
terraform destroy   # type "yes"
```

---

## The ports, in one table

| Port | Server | Purpose | Open to |
|------|--------|---------|---------|
| 22 | both | SSH remote control | your IP only |
| 8080 | Keycloak | login pages + OIDC (HTTP) | everyone (lab only!) |
| 8443 | NiFi | web UI (HTTPS) | your IP only |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Page won't load right after apply | Wait 5 min; then `ssh` in and check `sudo docker ps` / `sudo docker logs keycloak` (or `nifi`) |
| "Invalid redirect URI" from Keycloak | The URI in the client must exactly match the `nifi_redirect_uri` Terraform output |
| Logged in but "insufficient permissions" | The admin email passed to the script must exactly match the user's email in Keycloak. Re-run the script — it clears `users.xml`/`authorizations.xml` so the Initial Admin is re-applied |
| Script says it can't reach discovery URL | Create the `nifi` realm first (step 4); check Keycloak SG allows 8080 |
| Everything's broken | `terraform destroy` then `terraform apply` — fresh start in minutes |

More detail on every step, and every concept, in **GUIDE.md**.

---

## ⚠️ Lab shortcuts (do NOT do these in production)

- Keycloak runs in `start-dev` mode over plain HTTP with port 8080 open to the world
- NiFi uses a self-signed certificate (hence the browser warning)
- Passwords are written in config files instead of a secrets manager
- Terraform state is stored locally instead of in S3

GUIDE.md Part 10 explains what a production setup changes.
# nifikeycloak
