# aws_ec2_image_create
Scripts to provision and security harden an AWS EC2 image

Playing around with setting up Amazon AWS EC2 virtual machine.
When making an instance, under the Advanced settings, one can enter 'User Data'.
The User Data can be a bash script to run after the instance loads in order to customize
packages and the environment for user.
Here is a bash script I use to install and secure apache on a stock Ubuntu 22.04 LTS image
The bash script has no error control, testing, or checking. Things are specific to this version
of apache and Ubuntu, and are expected to break.
