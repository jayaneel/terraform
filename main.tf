terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "ap-south-1"
}

#Production DB
resource "aws_db_instance" "prod" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  identifier           = "proddb" 
  instance_class       = "db.t2.micro"
  name                 = "proddb"
  username             = var.prod_username
  password             = var.prod_password
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = ["sg-09d200c0659987e1c"]
  skip_final_snapshot  = true
}

#DR DB
resource "aws_db_instance" "DR" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  identifier           = "drdb" 
  instance_class       = "db.t2.micro"
  name                 = "drdb"
  username             = var.dr_username
  password             = var.dr_password
  parameter_group_name = "default.mysql8.0"
  vpc_security_group_ids = ["sg-09d200c0659987e1c"]
  skip_final_snapshot  = true
}


resource "aws_iam_role" "wprole" {
  name = "wprole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy_attachment" "test-attach" {
  name       = "test-attachment"
  roles      = [aws_iam_role.wprole.name]
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "ec2profile" {
  name = "ec2profile"
  role = aws_iam_role.wprole.name
}

#Creating Instances
resource "aws_instance" "ProdEC2" {
  ami           = "ami-00bf4ae5a7909786c"
  instance_type = "t2.micro"
  key_name = "04052021"
  user_data = file("user_data.sh")
  vpc_security_group_ids = ["sg-09d200c0659987e1c"]
  iam_instance_profile = aws_iam_instance_profile.ec2profile.name

  tags = {
    Name = "ProdEC2"
  }

}

resource "aws_instance" "DREC2" {
  ami           = "ami-00bf4ae5a7909786c"
  instance_type = "t2.micro"
  key_name = "04052021"
  user_data = file("user_data.sh")
  vpc_security_group_ids = ["sg-09d200c0659987e1c"]
  iam_instance_profile = aws_iam_instance_profile.ec2profile.name

  tags = {
    Name = "DREC2"
  }

}

resource "aws_s3_bucket" "sync" {
  bucket = "backup-bucket-07-2021"
  acl    = "public-read-write"

}

# Create a new load balancer
resource "aws_elb" "ProdLB" {
  name               = "ProdLB"
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
  security_groups = ["sg-09d200c0659987e1c"]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = data.aws_acm_certificate.amazon_issued.id
  }

  health_check {
    healthy_threshold   = 10
    unhealthy_threshold = 2
    timeout             = 5
    target              = "HTTP:80/healthy.html"
    interval            = 30
  }

  instances                   = [aws_instance.ProdEC2.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

}

resource "aws_elb" "DRLB" {
  name               = "DRLB"
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
  security_groups = ["sg-09d200c0659987e1c"]

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
    ssl_certificate_id = data.aws_acm_certificate.amazon_issued.id
  }

  health_check {
    healthy_threshold   = 10
    unhealthy_threshold = 2
    timeout             = 5
    target              = "HTTP:80/healthy.html"
    interval            = 30
  }

  instances                   = [aws_instance.DREC2.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

}

resource "aws_route53_zone" "wpress" {
  name = "jayaneel.tech"
}

data "aws_elb_hosted_zone_id" "ProdLB" {}

resource "aws_route53_record" "prod" {
  zone_id = aws_route53_zone.wpress.zone_id
  name    = "jayaneel.tech"
  type    = "A"

  alias {
    name                   = aws_elb.ProdLB.dns_name
    zone_id                = data.aws_elb_hosted_zone_id.ProdLB.id
    evaluate_target_health = true
  }
}

data "aws_elb_hosted_zone_id" "DRLB" {}

resource "aws_route53_record" "DR" {
  zone_id = aws_route53_zone.wpress.zone_id
  name    = "dr.jayaneel.tech"
  type    = "A"

  alias {
    name                   = aws_elb.DRLB.dns_name
    zone_id                = data.aws_elb_hosted_zone_id.DRLB.id
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "jayaneel" {
  domain_name               = "jayaneel.tech"
  subject_alternative_names = ["dr.jayaneel.tech"]
  validation_method         = "DNS"
}

data "aws_route53_zone" "jayaneel_tech" {
  name         = "jayaneel.tech"
  private_zone = false
}

resource "aws_route53_record" "jayaneel" {
  for_each = {
    for dvo in aws_acm_certificate.jayaneel.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.jayaneel_tech.zone_id
}

data "aws_acm_certificate" "amazon_issued" {
  domain      = "jayaneel.tech"
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}
