locals {
  service_map = {
    alpha = {
      port = 80
    }
    bravo = {
      port = 80
    }
    charlie = {
      port = 80
    }
  }
}


module "aws_ecs_service__demo" {
  source   = "terraform-aws-modules/ecs/aws"
  version  = "~> 5.0"
  for_each = local.service_map

  cluster_name = each.key

  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        base   = 1
        weight = 100
      }
    }
  }

  services = {
    (each.key) = {
      container_definitions = {
        (each.key) = {
          image                    = "public.ecr.aws/docker/library/httpd:2.4"
          essential                = true
          readonly_root_filesystem = false

          entrypoint = [
            "sh",
            "-c",
          ]

          command = [
            join(" && ", [
              "cd htdocs",
              "mkdir -p nested",
              "echo '<!doctype html><html><head><title>${each.key}</title></head><body><a href=./nested>./nested</a> @ <script>document.write(window.location.host)</script></body></html>' > /usr/local/apache2/htdocs/index.html",
              "echo '<!doctype html><html><head><title>${each.key}/nested</title></head><body><a href=../>../(up)</a> @ <script>document.write(window.location.host)</script></body></html>' > /usr/local/apache2/htdocs/nested/index.html",
              "httpd-foreground",
            ]),
          ]

          port_mappings = [{
            name          = each.key
            containerPort = each.value.port
          }]
        }
      }

      subnet_ids             = module.aws_vpc__demo.private_subnets
      enable_execute_command = true

      security_group_rules = {
        ingress_alb = {
          type                     = "ingress"
          protocol                 = "tcp"
          from_port                = each.value.port
          to_port                  = each.value.port
          source_security_group_id = module.aws_lb__demo.security_group_id
        }

        egress_all = {
          type        = "egress"
          protocol    = "-1"
          from_port   = 0
          to_port     = 0
          cidr_blocks = ["0.0.0.0/0"]
        }
      }

      load_balancer = {
        service = {
          container_name   = each.key
          container_port   = each.value.port
          target_group_arn = module.aws_lb__demo.target_groups[each.key].arn
        }
      }
    }
  }

  depends_on = [module.aws_lb__demo]
}
