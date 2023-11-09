data "aws_availability_zones" "available" {}

data "aws_route53_zone" "domain" {
  name = local.domain
}

locals {
  name   = "ecs_fargate_demo"
  cidr   = "10.0.0.0/16"
  azs    = slice(data.aws_availability_zones.available.names, 0, 3)
  domain = "sub.domain.io"
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

      forward = {
        target_group_key = local.services[0].name
      }

      rules = {
        for service in local.services : service.name => {
          actions = [{
            target_group_key = service.name
            type             = "forward"
          }]

          conditions = [{
            host_header = {
              values = ["${service.name}.${local.domain}"]
            }
          }]
        }
      }
    }
  }

  target_groups = {
    for service in local.services : service.name => {
      name              = service.name
      backend_port      = service.port
      target_type       = "ip"
      create_attachment = false

      health_check = {
        path = "/"
      }
    }
  }

  route53_records = {
    for service in local.services : "${service.name}-A" => {
      name    = service.name
      type    = "A"
      zone_id = data.aws_route53_zone.domain.id
    }
  }
}
