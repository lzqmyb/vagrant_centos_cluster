#! /bin/bash

# # vi /etc/selinux/config
# SELINUX=permissive

setenforce 0

# 下载使用本地repo的工具
mkdir -p /data/softs/localyum
cp -R /home/vagrant/softs/* /data/softs/localyum
yum install -y createrepo
createrepo -v /data/softs/localyum

# 创建本地repo
cat <<EOF>> /etc/yum.repos.d/local.repo
[local]
name=local
baseurl=file:///data/softs/localyum
enabled=1
gpgcheck=0
EOF

yum clean all
yum makecache

yum install docker -y

# 设置docker

systemctl enable docker && systemctl start docker

sed -i '/ExecStart/i\ExecStartPost=/sbin/iptables -I FORWARD -s 0.0.0.0/0 -j ACCEPT' /lib/systemd/system/docker.service

systemctl daemon-reload && systemctl restart docker

# 所有节点需要设定/etc/sysctl.d/k8s.conf的系统参数。
cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl -p /etc/sysctl.d/k8s.conf
