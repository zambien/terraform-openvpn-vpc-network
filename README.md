# terraform-openvpn-vpc-network
Standard AWS VPC with public and private subnets with an OpenVPN EC2 server for access.

A vpc with private/public subnets which only has external access via an openvpn server

Requirements:
* AWS Account
* Terraform
* Ansible
* docker
* jq

Deploys:
* Standard public/private AWS VPC.  Uses the terraform registry module here: https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/1.30.0.
* An openvpn EC2 server with 1194/22 open
* After apply you will find a tf-ovpn.ovpn and other required files in your project root to drag into your favorite client (i.e. tunnelblick)

# Deployment Instructions

You will need to have your profile configured in ~/.aws/credentials.  

Take a look at the variables.tf to see if you want to change anything.  The default AWS profile is "myprofile".

Run the following:

`terraform init` # This will initialize your terraform environment

`terraform apply` # This will create the AWS resources and drop the openvpn config files in your project root.

To clean up:

`terraform destroy`

# Connecting to the network

I use tunnelblick on my Mac.  Simply drag the tf-ovpn.ovpn file which was created when you ran `terraform apply` into your tunnelblick profiles and you will be set.

# Troubleshooting

Check the IP information of the network you are on if you are having issues with internet or LAN access once connected to the VPN.  You may have an IP conflict.

# Credits:

I used the following OSS projects for this:

* https://github.com/mattvonrocketstein/openvpn-ubuntu-ansible-terraform
* https://github.com/terraform-aws-modules/terraform-aws-vpc


