#!/bin/bash

# START constants for Ansible
ansible_group='ansible'
ansible_user='ansible'
let ansible_id=710
# END constants for Ansible


swarm_master_port=2377

while getopts a:e:f:r:s: opt
do
   case $opt in
      a) ansible_server_addr=${OPTARG};;
	  e) environment=${OPTARG};;
	  f) friendly_name=${OPTARG};;
	  r) region=${OPTARG};;
      s) appstack=${OPTARG};;
	  *);;
   esac
done

#add DNS search suffix to /etc/resolv.conf
sed -i -e 's/^PEERDNS=.*/PEERDNS=no/' /etc/sysconfig/network-scripts/ifcfg-*
sed -i -e "s/^\(search.*\)/\1 $appstack.$environment.cashnet.pvt/"  /etc/resolv.conf

# update and install python-pip, docker, and git
yum -y update
yum install -y python-pip git docker-18.03.1ce-5.0.amzn1

# install docker-compose
curl -L https://github.com/docker/compose/releases/download/1.19.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# add ec2-user to docker group
usermod -aG docker ec2-user

# start docker service and wait random 0-90 sec.
service docker start
chkconfig docker on

#delay > 150s to ensure dockermaster has registered
sleep 160s

master_host=`aws ssm get-parameter --region $region --name $friendly_name-master-host --output text --query "Parameter.Value"`
worker_join_token=`aws ssm get-parameter --region $region --name $friendly_name-worker-join-token --output text --query "Parameter.Value"`
docker swarm join --token $worker_join_token $master_host:$swarm_master_port

#Install Rexray 3dfs pligin - tscs-14170
s3fs_accesskey=`aws ssm get-parameter --region $region --name $environment-rexrays3-accesskey --output text --query "Parameter.Value"`
s3fs_secretkey=`aws ssm get-parameter --region $region --name $environment-rexrays3-secretkey --output text --query "Parameter.Value"`

docker plugin install rexray/s3fs:0.11.4 --grant-all-permissions \
S3FS_ACCESSKEY=$s3fs_accesskey \
S3FS_SECRETKEY=$s3fs_secretkey

# convert cn-images-XXX1-cnxxx to cn-images-xxx1-cnxxx in .env files for CNG/CNI
sed -i -e 's/images-ENG1/images-eng1/g' /install/cashnetg/.env
sed -i -e 's/images-PRD1/images-prd1/g' /install/cashnetg/.env
sed -i -e 's/images-ENG1/images-eng1/g' /install/cashneti/.env
sed -i -e 's/images-PRD1/images-prd1/g' /install/cashneti/.env

#make sure ec2-user owens home dir
chown -R ec2-user ~ec2-user

## Setup Nagios checks specific to docker ASG
echo "command[check_docker]=/usr/lib64/nagios/plugins/check_procs -C dockerd" >> /etc/nrpe.d/extra_checks.cfg
echo "command[check_docker_container]=/usr/bin/docker container ls --filter name=\$ARG1\$" >> /etc/nrpe.d/extra_checks.cfg
echo "command[check_docker_service_replicas]=/usr/bin/docker service ls --format='{{.Replicas}},{{.Name}}'" >> /etc/nrpe.d/extra_checks.cfg
echo "command[check_docker_service_count]=/usr/bin/docker service ls --format='{{.Replicas}}' --filter 'NAME=\$ARG1\$'" >> /etc/nrpe.d/extra_checks.cfg

# allow the npre account to use docker commands and restart the service to put in effect
usermod -G docker nrpe
service nrpe restart

# 20180322 MCaplin
# START config for Ansible
## Create a service account for ansible
groupadd -g ${ansible_id} ${ansible_group}
useradd  -g ${ansible_group} -u ${ansible_id} ${ansible_user}
chage -E -1 -M -1 ${ansible_user}

## Permit SSH for that user
sed -ie "s/\(^AllowGroups .*\)/\1 ${ansible_group}/" /etc/ssh/sshd_config
service sshd restart

## Configure a pre-shared public SSH key
su - $ansible_user -c "mkdir ~/.ssh && chmod go= ~/.ssh"
cat > /home/${ansible_user}/.ssh/authorized_keys << EOF
from="127.0.0.1/32,${ansible_server_addr}/32" ${anisible_ssh_key}
EOF
chmod go= /home/${ansible_user}/.ssh/authorized_keys
chown ansible:ansible /home/${ansible_user}/.ssh/authorized_keys

## Grant privilege via sudoers
echo "${ansible_user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansible && chmod 440 /etc/sudoers.d/ansible

# Download check_mem.sh
aws s3 cp s3://cashnet-software/nagios/check_mem.sh /usr/lib64/nagios/plugins/check_mem.sh
chmod 755 /usr/lib64/nagios/plugins/check_mem.sh

# END config for Ansible
