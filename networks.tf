data "aws_availability_zones" "available" {}

data "aws_route53_zone" "domain" {
  name = local.domain
}

locals {
  name   = "ecs_fargate_demo"
  cidr   = "10.0.0.0/16"
  azs    = slice(data.aws_availability_zones.available.names, 0, 3)
  domain = "www.example.com"
}

module "aws_vpc__demo" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.cidr, 4, k + 3)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
}

module "aws_lb__demo" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name    = replace(local.name, "_", "-")
  vpc_id  = module.aws_vpc__demo.vpc_id
  subnets = module.aws_vpc__demo.public_subnets

  load_balancer_type         = "application"
  enable_deletion_protection = false

  security_group_ingress_rules = {
    all_http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.aws_vpc__demo.vpc_cidr_block
    }
  }

  listeners = {
    http_redirect = {
      port     = 80
      protocol = "HTTP"

      redirect = {
        host        = local.domain
        path        = "/"
        protocol    = "HTTP"
        status_code = "HTTP_302"
      }

      rules = {
        for key, value in local.service_map : key => {
          actions = [{
            target_group_key = key
            type             = "forward"
          }]

          conditions = [{
            host_header = {
              values = ["${key}.${local.domain}"]
            }
          }]
        }
      }
    }
  }

  target_groups = {
    for key, value in local.service_map : key => {
      name              = key
      backend_port      = value.port
      target_type       = "ip"
      create_attachment = false

      health_check = {
        path = "/"
      }
    }
  }

  route53_records = {
    for key, value in local.service_map : "${key}-A" => {
      name    = key
      type    = "A"
      zone_id = data.aws_route53_zone.domain.id
    }
  }
}
