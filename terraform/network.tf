# ---------------------------------------------------------------
# 1. THE VPC - your private slice of AWS.
#    "10.0.0.0/16" = about 65,000 addresses, all "10.0.x.x".
# ---------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "tutorial-vpc" }
}

# ---------------------------------------------------------------
# 2. THE PUBLIC SUBNET - one street in the neighborhood.
#    map_public_ip_on_launch = true -> every computer on this
#    street gets a public address so the internet can reach it.
# ---------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "tutorial-public-subnet" }
}

# ---------------------------------------------------------------
# 3. THE INTERNET GATEWAY - the gate to the internet.
# ---------------------------------------------------------------
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "tutorial-igw" }
}

# ---------------------------------------------------------------
# 4. THE ROUTE TABLE - road signs: "anywhere -> through the gate".
# ---------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = { Name = "tutorial-public-routes" }
}

# ---------------------------------------------------------------
# 5. ATTACH the road signs to our street.
# ---------------------------------------------------------------
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
