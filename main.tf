provider "aws" {
  region = "us-east-1"
  profile = "${var.aws_profile}"
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "1.30.0"

  name = "terraform-openvpn-vpc"

  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.4.0/24", "10.0.6.0/24", "10.0.7.0/24"]
  public_subnets  = ["10.0.104.0/24", "10.0.105.0/24", "10.0.106.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    module_version = "${var.module_version}"
    application = "${var.stack_item_fullname}"
    account_id = "${data.aws_caller_identity.current.account_id}"
    caller_arn = "${data.aws_caller_identity.current.arn}"
    caller_id  = "${data.aws_caller_identity.current.user_id}"
    terraform  = "true"
    Name        = "${var.stack_item_label}"
  }
}

resource "null_resource" "check_requirements" {

  provisioner "local-exec" {
    command = <<EOT
      set -e
      ansible --version
      terraform --version
      jq --version
EOT
  }

}

resource "tls_private_key" "keypair" {
  algorithm = "RSA"
}

resource "aws_key_pair" "terraformer" {
  key_name   = "terraform-openvpn-key"
  public_key = "${tls_private_key.keypair.public_key_openssh}"
}

resource "local_file" "key" {
  content     = "${tls_private_key.keypair.private_key_pem}"
  filename = "${path.module}/${var.keyfile_name}"
}

resource "local_file" "pub" {
  content     = "${tls_private_key.keypair.public_key_openssh}"
  filename = "${path.module}/${var.keyfile_name}.pub"
}

resource "null_resource" "chmod_privatekey" {
  depends_on = ["local_file.key"]

  provisioner "local-exec" {
    command = "chmod 400 ${path.module}/${var.keyfile_name}"
  }
}

resource "null_resource" "install_requirements" {
  depends_on = ["null_resource.check_requirements"]

  provisioner "local-exec" {
    command = "ANSIBLE_ROLES_PATH=ansible/.roles ansible-galaxy install -r ansible/requirements.yml"
  }
}


data "aws_ami" "ubuntu_ue1_latest" {
  provider    = "aws"
  most_recent = true
  name_regex  = "^ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-\\d+"
  owners      = ["099720109477"]
}

resource "aws_instance" "openvpn" {
  ami               = "${data.aws_ami.ubuntu_ue1_latest.id}"
  instance_type     = "t2.nano"
  monitoring        = false
  key_name          = "${aws_key_pair.terraformer.key_name}"
  subnet_id = "${module.vpc.public_subnets[2]}"
  tags {
    module_version = "${var.module_version}"
    application = "${var.stack_item_fullname}"
    account_id = "${data.aws_caller_identity.current.account_id}"
    caller_arn = "${data.aws_caller_identity.current.arn}"
    caller_id  = "${data.aws_caller_identity.current.user_id}"
    terraform  = "true"
    Name        = "${var.stack_item_label}"
  }
  vpc_security_group_ids = ["${aws_security_group.openvpn.id}"]
}

resource "aws_security_group" "openvpn" {
  name = "openvpn"
  description = "openvpn security groups"
  vpc_id      = "${module.vpc.vpc_id}"
}

resource "aws_security_group_rule" "vpn-clients" {
  type            = "ingress"
  from_port       = 1194
  to_port         = 1194
  protocol        = "udp"
  cidr_blocks     = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.openvpn.id}"
}

resource "aws_security_group_rule" "main_egress" {
  type            = "egress"
  from_port       = 0
  to_port         = 0
  protocol        = "-1"
  cidr_blocks     = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.openvpn.id}"
}

resource "aws_security_group_rule" "ssh" {
  type            = "ingress"
  from_port       = 22
  to_port         = 22
  protocol        = "tcp"
  cidr_blocks     = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.openvpn.id}"
}

resource "aws_eip" "openvpn" {
  instance = "${aws_instance.openvpn.id}"
}

resource "null_resource" "ansible_provisioner" {

  provisioner "local-exec" {

    command = <<EOT
      export ANSIBLE_ROLES_PATH=ansible/.roles
      export ANSIBLE_CONFIG=ansible/ansible.cfg
      ansible-playbook \
      --key-file=${var.keyfile_name} \
      -e vpn_name=${var.vpn_name} \
      -e vpn_user=${var.vpn_user} \
      -e vpn_password=${var.vpn_password} \
      -i ${aws_eip.openvpn.public_ip}, \
      ./ansible/openvpn.yml
EOT
  }
}

# This is just to test that routing is working and everything.  By default it is not deployed.
resource "aws_instance" "test_instance" {
  count = "${var.provision_test_instance == true ? 1 : 0}"
  ami               = "${data.aws_ami.ubuntu_ue1_latest.id}"
  instance_type     = "t2.nano"
  monitoring        = false
  key_name          = "${aws_key_pair.terraformer.key_name}"
  associate_public_ip_address = false
  subnet_id = "${module.vpc.private_subnets[2]}"
  tags {
    module_version = "${var.module_version}"
    application = "${var.stack_item_fullname}"
    account_id = "${data.aws_caller_identity.current.account_id}"
    caller_arn = "${data.aws_caller_identity.current.arn}"
    caller_id  = "${data.aws_caller_identity.current.user_id}"
    terraform  = "true"
    Name        = "${var.stack_item_label}_testinstance"
  }
  vpc_security_group_ids = ["${aws_security_group.test_instance.id}"]
}

resource "aws_security_group" "test_instance" {
  count = "${var.provision_test_instance == true ? 1 : 0}"
  name = "test_instance"
  description = "test_instance security groups"
  vpc_id      = "${module.vpc.vpc_id}"
}

resource "aws_security_group_rule" "test_ssh" {
  count = "${var.provision_test_instance == true ? 1 : 0}"
  type            = "ingress"
  from_port       = 22
  to_port         = 22
  protocol        = "tcp"
  cidr_blocks     = ["10.0.0.0/8"]
  security_group_id = "${aws_security_group.test_instance.id}"
}