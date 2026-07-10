# AWS CLI Guide: Building the Same Setup by Hand

This guide builds the **exact same infrastructure** as the Terraform project, but using individual **AWS CLI commands**. Why would you do this?

- To understand what Terraform is actually doing under the hood (every Terraform resource = one or more CLI/API calls)
- To learn the AWS CLI, which is great for quick checks and scripting
- Because it's on the exam 😄

> 🧠 **Terraform vs CLI, the big idea:** The CLI is like giving a builder verbal instructions one at a time — and having to remember every ID they hand back to you. Terraform is like handing them a blueprint: it remembers everything (in the state file), can show you a diff before changing anything, and can demolish it all in one command. You'll feel the difference by the end of this guide.

---

## Part 0: The Two Workflows Side by Side

| Task | Terraform | AWS CLI |
|------|-----------|---------|
| Download plugins | `terraform init` | (not needed) |
| Preview changes | `terraform plan` | (no equivalent — you just run it!) |
| Build everything | `terraform apply` | ~20 commands below |
| See what exists | `terraform show` / `terraform state list` | `aws ec2 describe-*` commands |
| Delete everything | `terraform destroy` | ~12 commands, in reverse order |

### Terraform command reference (the short version)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # add your IP
terraform init                                  # once per project
terraform fmt                                   # tidy up formatting (optional)
terraform validate                              # check for syntax errors (optional)
terraform plan                                  # dress rehearsal
terraform apply                                 # build it (type "yes")
terraform output                                # re-print the URLs/IPs anytime
terraform output nifi_redirect_uri              # print just one value
terraform destroy                               # tear it all down (type "yes")
```

Now let's do the same thing the long way.

---

## Part 1: Setup — Variables We'll Reuse

The CLI hands back an ID after each command (like `vpc-0abc123...`). We'll save each one in a shell variable so later commands can use it. **Run everything below in ONE terminal session** — if you close it, the variables are gone (the resources aren't, but you'll have to look the IDs up again).

```bash
# ----- EDIT THESE TWO -----
export AWS_REGION="us-east-1"
export MY_IP="203.0.113.25/32"        # from https://checkip.amazonaws.com — keep the /32!
# --------------------------

export AWS_DEFAULT_REGION=$AWS_REGION
```

> 💡 **Tip:** `--query` picks fields out of the response (so we can grab just the ID) and `--output text` strips the quotes. You'll see this pattern constantly.

---

## Part 2: Build the Network (VPC, Subnet, Gateway, Routes)

### Step 2.1 — Create the VPC (the neighborhood)

```bash
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=tutorial-vpc}]' \
  --query 'Vpc.VpcId' --output text)

echo "VPC: $VPC_ID"

# Turn on DNS support (Terraform did this with two arguments; CLI needs two calls)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
```

### Step 2.2 — Create the public subnet (the street)

```bash
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=tutorial-public-subnet}]' \
  --query 'Subnet.SubnetId' --output text)

echo "Subnet: $SUBNET_ID"

# Auto-assign public IPs to anything launched on this street
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID --map-public-ip-on-launch
```

### Step 2.3 — Internet gateway (the gate) — create AND attach

```bash
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=tutorial-igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)

echo "Internet Gateway: $IGW_ID"

aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
```

### Step 2.4 — Route table (the road signs) — create, add route, associate

```bash
RTB_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=tutorial-public-routes}]' \
  --query 'RouteTable.RouteTableId' --output text)

echo "Route Table: $RTB_ID"

# The sign: "traffic to ANYWHERE (0.0.0.0/0) goes through the gate"
aws ec2 create-route \
  --route-table-id $RTB_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

# Nail the sign onto our street
aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET_ID
```

> 🧮 **Scorekeeping:** 4 Terraform resources took us 10 CLI commands, and you're now the proud caretaker of 4 IDs. Terraform tracks those for you.

---

## Part 3: Security Groups (the Bouncers)

### Step 3.1 — Keycloak's security group

```bash
KC_SG_ID=$(aws ec2 create-security-group \
  --group-name keycloak-sg \
  --description "Rules for the Keycloak server" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

echo "Keycloak SG: $KC_SG_ID"

# Door 22 (SSH): only my laptop
aws ec2 authorize-security-group-ingress \
  --group-id $KC_SG_ID --protocol tcp --port 22 --cidr $MY_IP

# Door 8443 (Keycloak HTTPS web + OIDC): open to all so both your
# browser and the NiFi server can reach it
aws ec2 authorize-security-group-ingress \
  --group-id $KC_SG_ID --protocol tcp --port 8443 --cidr 0.0.0.0/0
```

### Step 3.2 — NiFi's security group

```bash
NIFI_SG_ID=$(aws ec2 create-security-group \
  --group-name nifi-sg \
  --description "Rules for the NiFi server" \
  --vpc-id $VPC_ID \
  --query 'GroupId' --output text)

echo "NiFi SG: $NIFI_SG_ID"

# Door 22 (SSH): only my laptop
aws ec2 authorize-security-group-ingress \
  --group-id $NIFI_SG_ID --protocol tcp --port 22 --cidr $MY_IP

# Door 8443 (NiFi HTTPS UI): only my laptop
aws ec2 authorize-security-group-ingress \
  --group-id $NIFI_SG_ID --protocol tcp --port 8443 --cidr $MY_IP
```

> 🧠 **Where are the egress (outbound) rules?** AWS security groups allow ALL outbound traffic by default, so there's nothing to add. (Terraform's AWS provider *removes* that default, which is why our `.tf` files declare egress explicitly.) Inbound is the opposite: everything is denied until you `authorize-security-group-ingress`.

---

## Part 4: Key Pair and the Ubuntu Image

### Step 4.1 — Upload your SSH public key

```bash
aws ec2 import-key-pair \
  --key-name tutorial-key \
  --public-key-material fileb://~/.ssh/tutorial-key.pub
```

### Step 4.2 — Find the newest Ubuntu 24.04 image

This is the CLI twin of Terraform's `data "aws_ami"` block — same owner, same name filter, sorted by date, take the last one:

```bash
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
            "Name=virtualization-type,Values=hvm" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

echo "Ubuntu AMI: $AMI_ID"
```

---

## Part 5: Launch the Two Servers

The `--user-data` flag points at the same first-boot scripts Terraform uses — they install Docker + Docker Compose and start each container. They live in this project at `scripts/user-data-keycloak.sh` and `scripts/user-data-nifi.sh`. Run these commands **from the project root folder** so the paths work.

### Step 5.1 — Launch Keycloak

```bash
KC_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.small \
  --subnet-id $SUBNET_ID \
  --security-group-ids $KC_SG_ID \
  --key-name tutorial-key \
  --user-data file://scripts/user-data-keycloak.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=keycloak-server}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "Keycloak instance: $KC_INSTANCE_ID"
```

### Step 5.2 — Launch NiFi

```bash
NIFI_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.medium \
  --subnet-id $SUBNET_ID \
  --security-group-ids $NIFI_SG_ID \
  --key-name tutorial-key \
  --user-data file://scripts/user-data-nifi.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=nifi-server}]' \
  --query 'Instances[0].InstanceId' --output text)

echo "NiFi instance: $NIFI_INSTANCE_ID"
```

### Step 5.3 — Wait for them to start, then grab the IPs

```bash
# This command literally waits until both are running
aws ec2 wait instance-running --instance-ids $KC_INSTANCE_ID $NIFI_INSTANCE_ID

KEYCLOAK_IP=$(aws ec2 describe-instances --instance-ids $KC_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

NIFI_IP=$(aws ec2 describe-instances --instance-ids $NIFI_INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "=================================================="
echo "Keycloak:      https://$KEYCLOAK_IP:8443"
echo "NiFi:          https://$NIFI_IP:8443/nifi"
echo "Redirect URI:  https://$NIFI_IP:8443/nifi-api/access/oidc/callback"
echo "Logout URI:    https://$NIFI_IP:8443/nifi-api/access/oidc/logout/callback"
echo "SSH Keycloak:  ssh -i ~/.ssh/tutorial-key ubuntu@$KEYCLOAK_IP"
echo "SSH NiFi:      ssh -i ~/.ssh/tutorial-key ubuntu@$NIFI_IP"
echo "=================================================="
```

⏰ "Running" means the computer is on — Docker is still installing. Give it **~5 more minutes** before opening the URLs.

**From here, continue with the normal steps:** create the `nifi` realm, client, and users in Keycloak (README steps 3–6 / GUIDE Part 5), then run `scripts/configure-nifi-oidc.sh` on the NiFi server (README steps 7–8).

---

## Part 6: Handy Inspection Commands

```bash
# List all your tutorial instances with name, state, and IP
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=keycloak-server,nifi-server" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value, State.Name, PublicIpAddress]' \
  --output table

# See a security group's rules
aws ec2 describe-security-groups --group-ids $NIFI_SG_ID \
  --query 'SecurityGroups[0].IpPermissions' --output table

# Read a server's first-boot log if something seems broken (run ON the server)
#   sudo cat /var/log/cloud-init-output.log

# Stop the servers overnight to save money (config is preserved; public IPs change!)
aws ec2 stop-instances  --instance-ids $KC_INSTANCE_ID $NIFI_INSTANCE_ID
aws ec2 start-instances --instance-ids $KC_INSTANCE_ID $NIFI_INSTANCE_ID
```

> ⚠️ **Stopped ≠ free, and IPs change.** Stopped instances still bill for disk (pennies), and when restarted they get NEW public IPs — meaning you'd need to update the Keycloak redirect URI and NiFi's discovery URL. For a lab, it's usually easier to destroy and rebuild.

---

## Part 7: Tear It All Down (CLI Style)

Deletion must happen in roughly **reverse order** — you can't delete a VPC that still has stuff in it. (With Terraform this whole part is one command. Feel the difference yet?)

```bash
# 1. Terminate the instances and WAIT until they're fully gone
aws ec2 terminate-instances --instance-ids $KC_INSTANCE_ID $NIFI_INSTANCE_ID
aws ec2 wait instance-terminated --instance-ids $KC_INSTANCE_ID $NIFI_INSTANCE_ID

# 2. Delete the security groups (must wait for instances first!)
aws ec2 delete-security-group --group-id $KC_SG_ID
aws ec2 delete-security-group --group-id $NIFI_SG_ID

# 3. Delete the key pair
aws ec2 delete-key-pair --key-name tutorial-key

# 4. Detach and delete the internet gateway
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID

# 5. Delete the subnet
aws ec2 delete-subnet --subnet-id $SUBNET_ID

# 6. Delete the route table
aws ec2 delete-route-table --route-table-id $RTB_ID

# 7. Finally, delete the VPC
aws ec2 delete-vpc --vpc-id $VPC_ID

echo "All gone! Double-check the EC2 console to be sure."
```

Lost your variables (closed the terminal)? Look the IDs up again:

```bash
aws ec2 describe-vpcs            --filters "Name=tag:Name,Values=tutorial-vpc" --query 'Vpcs[].VpcId' --output text
aws ec2 describe-instances       --filters "Name=tag:Name,Values=keycloak-server,nifi-server" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[].Instances[].InstanceId' --output text
aws ec2 describe-security-groups --filters "Name=group-name,Values=keycloak-sg,nifi-sg" --query 'SecurityGroups[].GroupId' --output text
```

---

## Part 8: What You Just Learned

- Every Terraform resource maps to one or more AWS API calls — `aws_vpc` → `create-vpc` + two `modify-vpc-attribute` calls, and so on.
- The CLI makes YOU the state file: you track IDs, ordering, and dependencies in your head (or your shell variables).
- Creation order matters (VPC before subnet before instance) and deletion order is the reverse.
- This is exactly why infrastructure-as-code exists. Both skills are worth having: the CLI for quick lookups and one-off fixes, Terraform for anything you'll build more than once.
