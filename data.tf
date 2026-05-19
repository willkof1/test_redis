# --- Pega seu IP público para a regra de SSH ---
data "http" "my_ip" {
  url = "http://checkip.amazonaws.com"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}