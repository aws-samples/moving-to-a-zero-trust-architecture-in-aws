# ---------- network/firewall_policy.tf ----------

# Network Firewall policy
resource "aws_networkfirewall_firewall_policy" "anfw_policy" {
  name = "firewall-policy-network"

  firewall_policy {
    # Stateless configuration
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateless_rule_group_reference {
      priority     = 10
      resource_arn = aws_networkfirewall_rule_group.drop_remote.arn
    }

    # Stateful configuration
    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }
    stateful_default_actions = ["aws:drop_strict", "aws:alert_strict"]
    stateful_rule_group_reference {
      priority     = 10
      resource_arn = aws_networkfirewall_rule_group.allow_traffic.arn
    }
  }
}

# Stateless Rule Group - Dropping any SSH or RDP connection
resource "aws_networkfirewall_rule_group" "drop_remote" {
  capacity = 2
  name     = "drop-remote-network"
  type     = "STATELESS"
  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {

        stateless_rule {
          priority = 1
          rule_definition {
            actions = ["aws:drop"]
            match_attributes {
              protocols = [6]
              source {
                address_definition = "0.0.0.0/0"
              }
              source_port {
                from_port = 22
                to_port   = 22
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
              destination_port {
                from_port = 22
                to_port   = 22
              }
            }
          }
        }
      }
    }
  }
}

# Stateful Rule Group - Allowing ICMP traffic
resource "aws_networkfirewall_rule_group" "allow_traffic" {
  capacity = 100
  name     = "allow-icmp-network"
  type     = "STATEFUL"
  rule_group {
    rule_variables {
      ip_sets {
        key = "NETWORK"
        ip_set {
          definition = ["10.0.0.0/8"]
        }
      }
    }
    rules_source {
      rules_string = <<EOF
      pass tls any any -> any 443 (tls.sni; dotprefix; content:".pablosc.people.aws.dev"; endswith; msg:"Allowed HTTPS domain"; sid:1; rev:1;)
      pass tcp any any <> any 443 (flow:not_established; sid:2; rev:1;)
      pass ip any any <> any any (sid:3;rev:1;)
      EOF
    }
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }
}