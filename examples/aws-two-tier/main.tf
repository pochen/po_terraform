# Specify the provider and access details
provider "aws" {
  region = "${var.aws_region}"
#  region = "us-west-2"
}

# Create a VPC to launch our instances into
resource "aws_vpc" "default_terraform_two_tier" {
  cidr_block = "10.0.0.0/16"
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default_terraform_two_tier" {
  vpc_id = "${aws_vpc.default_terraform_two_tier.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access_terraform_two_tier" {
  route_table_id         = "${aws_vpc.default_terraform_two_tier.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default_terraform_two_tier.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default_tf_two_tier" {
  availability_zone = "us-east-1d" # * aws_instance.web_terraform_two_tier: Error launching source instance: InvalidParameterValue: Value (us-east-1d) for parameter availabilityZone is invalid. Subnet 'subnet-6f988552' is in the availability zone us-east-1e # status code: 400, request id: 31134f59-41b2-4219-ac5c-6bafd2abd76a
  vpc_id                  = "${aws_vpc.default_terraform_two_tier.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "elb" {
  name        = "terraform_example_elb_two_tier"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.default_terraform_two_tier.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default_terraform_two_tier" {
  name        = "terraform_example_terraform_two_tier"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.default_terraform_two_tier.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_elb" "web_terraform_two_tier" {
  name = "terraform-example-elb"

  subnets         = ["${aws_subnet.default_tf_two_tier.id}"]
  security_groups = ["${aws_security_group.elb.id}"]
  instances       = ["${aws_instance.web_terraform_two_tier.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

}

resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

resource "aws_instance" "web_terraform_two_tier" {
  # The connection block tells our provisioner how to
  # communicate with the resource (instance)
  connection {
    # The default username for our AMI
    user = "ubuntu"

    # The connection will use the local SSH agent for authentication.
  }

  #instance_type = "m1.small"
  instance_type = "t1.micro"

  availability_zone = "us-east-1d" # * aws_instance.web_terraform_two_tier: Error launching source instance: Unsupported: Your requested instance type (t1.micro) is not supported in your requested Availability Zone (us-east-1e). Please retry your request by not specifying an Availability Zone or choosing us-east-1d, us-east-1a, us-east-1b.
	# status code: 400, request id: 42b14c78-840e-46b0-bdc1-43987c4981c4

  # Lookup the correct AMI based on the region
  # we specified
  ami = "${lookup(var.aws_amis, var.aws_region)}"

  # The name of our SSH keypair we created above.
  key_name = "${aws_key_pair.auth.id}"

  # Our Security group to allow HTTP and SSH access
  vpc_security_group_ids = ["${aws_security_group.default_terraform_two_tier.id}"]

  # We're going to launch into the same subnet as our ELB. In a production
  # environment it's more common to have a separate private subnet for
  # backend instances.
  subnet_id = "${aws_subnet.default_tf_two_tier.id}"

  # We run a remote provisioner on the instance after creating it.
  # In this case, we just install nginx and start it. By default,
  # this should be on port 80
  provisioner "remote-exec" {
    connection {
      type = "ssh"
      user = "ubuntu"
      private_key = "${file("~/.ssh/terraform_pc_test")}"
    }
    inline = [
      "sudo apt-get -y update",
      "sudo apt-get -y install nginx",
      "sudo service nginx start"
    ]
  }
}
