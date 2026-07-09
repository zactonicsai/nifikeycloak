# ================================================================
# SSM (AWS Systems Manager) — keyless, portless server access
# ----------------------------------------------------------------
# What is this? SSM Session Manager lets you open a terminal on
# your servers WITHOUT SSH keys and WITHOUT opening port 22.
# Instead of you knocking on the server's door, a small agent on
# the server phones home to AWS, and AWS connects you through
# that call. Think of it as the server holding a walkie-talkie
# that only AWS can use.
#
# Why it's great:
#   - Lost your SSH key? Doesn't matter.
#   - IP address changed? Doesn't matter.
#   - Works from the AWS Console in your browser, zero setup.
#
# For this to work, the server needs PERMISSION to talk to the
# SSM service. Permissions in AWS are handled by IAM:
#   1. A ROLE   = a costume the server wears ("I am an
#                 SSM-managed instance")
#   2. A POLICY = the list of things the costume allows
#                 (AWS provides a ready-made one)
#   3. An INSTANCE PROFILE = the hanger that attaches the
#                 costume to an EC2 instance
# ================================================================

# ---------------------------------------------------------------
# 1. THE ROLE — who is allowed to wear this costume?
#    The "assume role policy" says: only the EC2 service may
#    wear it (not people, not other services).
# ---------------------------------------------------------------
resource "aws_iam_role" "ssm" {
  name = "tutorial-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = { Name = "tutorial-ssm-role" }
}

# ---------------------------------------------------------------
# 2. THE POLICY — attach AWS's ready-made SSM permission list.
#    "AmazonSSMManagedInstanceCore" is the official minimal set
#    of permissions the SSM agent needs to phone home.
# ---------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------------------------------------------------------------
# 3. THE INSTANCE PROFILE — the hanger EC2 uses to attach the
#    role to our two servers (see iam_instance_profile in
#    servers.tf).
# ---------------------------------------------------------------
resource "aws_iam_instance_profile" "ssm" {
  name = "tutorial-ssm-profile"
  role = aws_iam_role.ssm.name
}
