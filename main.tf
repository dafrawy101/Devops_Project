#######################
# VPC + Subnets + IGW #
#######################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/20"
  availability_zone       = "us-east-1a"  # Changed to available AZ
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-1"
  }
}

resource "aws_subnet" "subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.16.0/20"
  availability_zone       = "us-east-1c"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-2"
  }
}

resource "aws_internet_gateway" "internet_gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gw.id
  }

  tags = {
    Name = "main-rt"
  }
}

resource "aws_route_table_association" "subnet_1_association" {
  subnet_id      = aws_subnet.subnet_1.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_route_table_association" "subnet_2_association" {
  subnet_id      = aws_subnet.subnet_2.id
  route_table_id = aws_route_table.route_table.id
}

#########################
# Security Groups
#########################

resource "aws_security_group" "instance_sg" {
  name        = "instance-sg"
  description = "Security group for LiveKit instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "RTP/RTCP Media Traffic"
    from_port   = 50000
    to_port     = 60000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "LiveKit TCP Ports"
    from_port   = 7880
    to_port     = 7881
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "LiveKit UDP Ports"
    from_port   = 10000
    to_port     = 20000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SIP TCP Ports"
    from_port   = 5060
    to_port     = 5061
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SIP UDP Ports"
    from_port   = 5060
    to_port     = 5061
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "instance-sg"
  }
}

#########################
# Nginx SG
#########################

resource "aws_security_group" "nginx_sg" {
  name        = "nginx-sg"
  description = "Security group for Nginx instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nginx-sg"
  }
}

#########################
# Nginx EC2 Instance
#########################

resource "aws_instance" "nginx" {
  ami                    = "ami-04b70fa74e45c3917"
  instance_type          = "t2.medium"
  key_name               = "lk"
  subnet_id              = aws_subnet.subnet_1.id
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    apt update -y
    apt install nginx -y
    systemctl enable nginx
    
    # Create LiveKit nginx configuration
    cat > /etc/nginx/sites-available/livekit << 'EOL'
    upstream livekit_backend {
        server ${aws_instance.initial.private_ip}:7880;
        # ASG instances will be added manually or via dynamic DNS
    }

    server {
        listen 80;
        server_name livekitsecret.gleeze.com;

        location / {
            proxy_pass http://livekit_backend;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            proxy_connect_timeout 7d;
            proxy_send_timeout 7d;
            proxy_read_timeout 7d;
        }

        location /health {
            access_log off;
            return 200 "healthy\\n";
            add_header Content-Type text/plain;
        }
    }
    EOL

    # Enable the site
    ln -sf /etc/nginx/sites-available/livekit /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test and reload nginx
    nginx -t && systemctl start nginx
  EOF

  tags = {
    Name = "nginx-instance"
  }
}
#########################
# Initial EC2 Instance (LiveKit)
#########################

resource "aws_instance" "initial" {
  ami                    = "ami-04b70fa74e45c3917" # Ubuntu 22.04 LTS (us-east-1)
  instance_type          = "t3.medium"  # Changed to more available instance type
  key_name               = "lk"
  subnet_id              = aws_subnet.subnet_1.id
  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  user_data = <<-EOF
#!/bin/bash
set -e

echo "=== Updating environment ==="
apt-get update -y
apt-get install -y curl git ca-certificates gnupg lsb-release

echo "=== Installing Docker ==="
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu

echo "=== Installing Docker Compose ==="
mkdir -p /usr/local/lib/docker/cli-plugins
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/bin/docker-compose 2>/dev/null || true

echo "=== Starting Docker service ==="
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
echo "=== Waiting for Docker to be ready ==="
timeout=60
while [ $timeout -gt 0 ]; do
    if docker info >/dev/null 2>&1; then
        echo "Docker is ready!"
        break
    fi
    sleep 5
    timeout=$((timeout - 5))
    echo "Waiting for Docker to be ready..."
done

if [ $timeout -le 0 ]; then
    echo "ERROR: Docker failed to start within expected time"
    exit 1
fi

echo "=== Cloning and launching LiveKit ==="
sudo -u ubuntu bash -c "
  set -e
  cd /home/ubuntu
  
  echo 'Current user: \$(whoami)'
  echo 'Docker version:'
  docker --version
  echo 'Docker Compose version:'
  /usr/local/bin/docker-compose --version
  
  git clone https://github.com/mmzaboys/LiveKit.git livekit || echo 'Clone may have failed or already exists'
  cd livekit
  echo 'LIVEKIT_DOMAIN=livekitsecret.gleeze.com' >> .env
  echo 'LIVEKIT_API_KEY=APIMGpn7kZ7YUgU' >> .env
  echo 'LIVEKIT_API_SECRET=NUReZAOWK47i7tt26G8yKl8it8GcmyId8psiN7hhTXP' >> .env
  chmod +x configfiles.sh
  ./configfiles.sh
  
  echo '=== Starting LiveKit with Docker Compose ==='
  /usr/local/bin/docker-compose up -d
  echo '=== Docker Compose completed ==='
  
  # Wait for services to start
  sleep 30
  echo '=== Checking running containers ==='
  /usr/local/bin/docker-compose ps
"

echo "=== LiveKit setup completed successfully ==="

# Create startup script for ASG instances
cat > /etc/systemd/system/livekit.service << 'EOL'
[Unit]
Description=LiveKit Service
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/docker-compose -f /home/ubuntu/livekit/docker-compose.yml up -d
ExecStop=/usr/local/bin/docker-compose -f /home/ubuntu/livekit/docker-compose.yml down
WorkingDirectory=/home/ubuntu/livekit
User=ubuntu

[Install]
WantedBy=multi-user.target
EOL

systemctl enable livekit.service
  EOF

  tags = {
    Name = "initial-instance"
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

#########################
# Wait for Initial Setup
#########################

resource "null_resource" "wait_for_initial_setup" {
  depends_on = [aws_instance.initial]

  provisioner "local-exec" {
    command = "echo 'Waiting for initial instance to be ready...' && sleep 180"
  }

  triggers = {
    instance_id = aws_instance.initial.id
  }
}

#########################
# AMI from Initial EC2
#########################

resource "aws_ami_from_instance" "service_ami" {
  name               = "livekit-ami-${formatdate("YYYYMMDD-HHmmss", timestamp())}"
  source_instance_id = aws_instance.initial.id
  depends_on         = [null_resource.wait_for_initial_setup]

  tags = {
    Name = "livekit-ami"
  }
}

#########################
# Launch Template
#########################

resource "aws_launch_template" "service_lt" {
  name_prefix   = "livekit-lt-"
  image_id      = aws_ami_from_instance.service_ami.id
  instance_type = "t3.medium"  # Changed to more available instance type
  key_name      = "lk"
  vpc_security_group_ids = [aws_security_group.instance_sg.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Start Docker
    systemctl start docker
    sleep 30
    
    # Start LiveKit services
    sudo -u ubuntu bash -c "cd /home/ubuntu/livekit && /usr/local/bin/docker-compose down && /usr/local/bin/docker-compose up -d"
    
    # Health check endpoint
    echo 'OK' > /var/www/html/health.html
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "livekit-asg-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

#########################
# Auto Scaling Group
#########################

resource "aws_autoscaling_group" "service_asg" {
  name_prefix         = "livekit-asg-"
  desired_capacity    = 1
  max_size            = 2
  min_size            = 1
  health_check_type   = "EC2"
  health_check_grace_period = 400
  vpc_zone_identifier = [aws_subnet.subnet_1.id, aws_subnet.subnet_2.id]

  launch_template {
    id      = aws_launch_template.service_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "livekit-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [desired_capacity]
  }
}

#########################
# Outputs
#########################

output "nginx_public_ip" {
  description = "Public IP of Nginx instance"
  value       = aws_instance.nginx.public_ip
}

output "initial_instance_public_ip" {
  description = "Public IP of initial LiveKit instance"
  value       = aws_instance.initial.public_ip
}

output "ami_id" {
  description = "ID of the created AMI"
  value       = aws_ami_from_instance.service_ami.id
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.service_asg.name
}

output "access_instructions" {
  description = "Instructions to access LiveKit"
  value = <<-EOT
   
    LiveKit Setup Complete!
    
    Nginx Instance: http://${aws_instance.nginx.public_ip}
    Initial LiveKit Instance: ${aws_instance.initial.public_ip}:7880
    
    To access LiveKit directly:
    https://livekitsecret.gleeze.com  (point DNS to ASG instances)
    
    Or access via instance IPs:
    curl http://${aws_instance.initial.public_ip}:7880/rtc/
    
    ASG instances will be accessible on their public IPs on port 7880
  EOT
}