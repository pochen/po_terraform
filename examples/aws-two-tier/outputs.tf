output "address" {
  value = "${aws_elb.web_terraform_two_tier.dns_name}"
}
