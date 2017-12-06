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
yum install -y kubernetes-1.8.1-1.el7.x86_64 

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

# 在master1需要安装CFSSL工具，这将会用来建立 TLS certificates。
export CFSSL_URL="https://pkg.cfssl.org/R1.2"
wget "${CFSSL_URL}/cfssl_linux-amd64" -O /usr/local/bin/cfssl
wget "${CFSSL_URL}/cfssljson_linux-amd64" -O /usr/local/bin/cfssljson
chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
