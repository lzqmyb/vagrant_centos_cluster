#! /bin/bash

# 在master1需要安装CFSSL工具，这将会用来建立 TLS certificates。
export CFSSL_URL="https://pkg.cfssl.org/R1.2"
wget "${CFSSL_URL}/cfssl_linux-amd64" -O /usr/local/bin/cfssl
chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson

# Etcd
# 在开始安装 Kubernetes 之前，需要先将一些必要系统创建完成，其中 Etcd 就是 Kubernetes 最重要的一环，Kubernetes 会将大部分信息储存于 Etcd 上，来提供给其他节点索取，以确保整个集群运作与沟通正常。

# 建立/etc/etcd/ssl文件夹，然后进入目录完成以下操作。
mkdir -p /etc/etcd/ssl && cd /etc/etcd/ssl
export PKI_URL="/home/vagrant/pki"

# 下载ca-config.json与etcd-ca-csr.json文件，并产生 CA 密钥：

cp ${PKI_URL}/ca-config.json .
cp ${PKI_URL}/etcd-ca-csr.json .
# cat etcd-ca-csr.json
# cat ca-config.json
cfssl gencert -initca etcd-ca-csr.json | cfssljson -bare etcd-ca
ls etcd-ca*.pem

# 下载etcd-csr.json文件，并产生 kube-apiserver certificate 证书：
cp ${PKI_URL}/etcd-csr.json .
cfssl gencert \
  -ca=etcd-ca.pem \
  -ca-key=etcd-ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  etcd-csr.json | cfssljson -bare etcd

ls etcd*.pem
rm -rf *.json


yum install etcd -y

export ETCD_CONF_URL="/home/vagrant/etcd"
cp ${ETCD_CONF_URL}/etcd.conf /etc/etcd/etcd.conf
# cp ${ETCD_CONF_URL}/etcd.service /lib/systemd/system/etcd.service

# 建立 var 存放信息，然后启动 Etcd 服务:
mkdir -p /var/lib/etcd && chown etcd:etcd -R /var/lib/etcd /etc/etcd
systemctl enable etcd.service && systemctl start etcd.service

# 通过简单指令验证：
export CA="/etc/etcd/ssl"
ETCDCTL_API=3 etcdctl \
    --cacert=${CA}/etcd-ca.pem \
    --cert=${CA}/etcd.pem \
    --key=${CA}/etcd-key.pem \
    --endpoints="https://172.1.1.12:2379" \
    endpoint health

# output
# https://172.16.35.12:2379 is healthy: successfully committed proposal: took = 641.36µs

# Master 是 Kubernetes 的大总管，主要创建apiserver、Controller manager与Scheduler来组件管理所有 Node。本步骤将下载 Kubernetes 并安装至 master1上，然后产生相关 TLS Cert 与 CA 密钥，提供给集群组件认证使用。
yum install kubernetes -y

link  /usr/bin/kubectl /usr/local/bin/kubectl
link  /usr/bin/kubelet /usr/local/bin/kubelet


# Download CNI
mkdir -p /opt/cni/bin && cd /opt/cni/bin
cp /home/vagrant/cni/cni-plugins-amd64-v0.6.0.tgz .
tar -zx cni-plugins-amd64-v0.6.0.tgz


# 创建pki文件夹，然后进入目录完成以下操作。
mkdir -p /etc/kubernetes/pki && cd /etc/kubernetes/pki
export PKI_URL="/home/vagrant/pki"
export KUBE_APISERVER="https://172.1.1.12:6443"


# 下载ca-config.json与ca-csr.json文件，并生成 CA 密钥：
cp ${PKI_URL}/ca-config.json
cp ${PKI_URL}/ca-csr.json
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
ls ca*.pem


# API server certificate

#  下载apiserver-csr.json文件，并生成 kube-apiserver certificate 证书：
cp ${PKI_URL}/apiserver-csr.json
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=172.1.1.12,127.0.0.1,kubernetes.default \
  -profile=kubernetes \
  apiserver-csr.json | cfssljson -bare apiserver

ls apiserver*.pem

# Front proxy certificate

# 下载front-proxy-ca-csr.json文件，并生成 Front proxy CA 密钥，Front proxy 主要是用在 API aggregator 上:

cp ${PKI_URL}/front-proxy-ca-csr.json
cfssl gencert \
  -initca front-proxy-ca-csr.json | cfssljson -bare front-proxy-ca

ls front-proxy-ca*.pem

# 下载front-proxy-client-csr.json文件，并生成 front-proxy-client 证书：
cp ${PKI_URL}/front-proxy-client-csr.json
cfssl gencert \
  -ca=front-proxy-ca.pem \
  -ca-key=front-proxy-ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  front-proxy-client-csr.json | cfssljson -bare front-proxy-client

ls front-proxy-client*.pem



# 与教程中启动命令位置保持一致
link /usr/bin/kubelet /usr/local/bin/kubelet

# Bootstrap Token
#
# 由于通过手动创建 CA 方式太过繁杂，只适合少量机器，因为每次签证时都需要绑定 Node IP，随机器增加会带来很多困扰，因此这边使用 TLS Bootstrapping 方式进行授权，由 apiserver 自动给符合条件的 Node 发送证书来授权加入集群。
#
# 主要做法是 kubelet 启动时，向 kube-apiserver 传送 TLS Bootstrapping 请求，而 kube-apiserver 验证 kubelet 请求的 token 是否与设定的一样，若一样就自动产生 kubelet 证书与密钥。具体作法可以参考 TLS bootstrapping。
#
# 首先建立一个变量来产生BOOTSTRAP_TOKEN，并建立 bootstrap.conf 的 kubeconfig 文件：

export BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
cat <<EOF > /etc/kubernetes/token.csv
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

# bootstrap set-cluster
kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../bootstrap.conf

# bootstrap set-credentials
kubectl config set-credentials kubelet-bootstrap \
    --token=${BOOTSTRAP_TOKEN} \
    --kubeconfig=../bootstrap.conf

# bootstrap set-context
kubectl config set-context default \
    --cluster=kubernetes \
    --user=kubelet-bootstrap \
   --kubeconfig=../bootstrap.conf

# bootstrap set default context
kubectl config use-context default --kubeconfig=../bootstrap.conf


# Admin certificate
#
# 下载admin-csr.json文件，并生成 admin certificate 证书：

cp ${PKI_URL}/admin-csr.json
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin

ls admin*.pem

# 接着通过以下指令生成名称为 admin.conf 的 kubeconfig 文件：

# admin set-cluster
kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../admin.conf

# admin set-credentials
kubectl config set-credentials kubernetes-admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \
    --embed-certs=true \
    --kubeconfig=../admin.conf

# admin set-context
kubectl config set-context kubernetes-admin@kubernetes \
    --cluster=kubernetes \
    --user=kubernetes-admin \
    --kubeconfig=../admin.conf

# admin set default context
kubectl config use-context kubernetes-admin@kubernetes \
    --kubeconfig=../admin.conf

# Controller manager certificate

# 下载manager-csr.json文件，并生成 kube-controller-manager certificate 证书：

cp ${PKI_URL}/manager-csr.json
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  manager-csr.json | cfssljson -bare controller-manager

ls controller-manager*.pem

# 接着通过以下指令生成名称为controller-manager.conf的 kubeconfig 文件：

# controller-manager set-cluster
kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../controller-manager.conf

# controller-manager set-credentials
kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=controller-manager.pem \
    --client-key=controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=../controller-manager.conf

# controller-manager set-context
kubectl config set-context system:kube-controller-manager@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-controller-manager \
    --kubeconfig=../controller-manager.conf

# controller-manager set default context
kubectl config use-context system:kube-controller-manager@kubernetes \
    --kubeconfig=../controller-manager.conf

# Scheduler certificate

# 下载scheduler-csr.json文件，并生成 kube-scheduler certificate 证书：
cp ${PKI_URL}/scheduler-csr.json
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  scheduler-csr.json | cfssljson -bare scheduler

ls scheduler*.pem

# scheduler set-cluster
kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../scheduler.conf

# scheduler set-credentials
kubectl config set-credentials system:kube-scheduler \
    --client-certificate=scheduler.pem \
    --client-key=scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=../scheduler.conf

# scheduler set-context
kubectl config set-context system:kube-scheduler@kubernetes \
    --cluster=kubernetes \
    --user=system:kube-scheduler \
    --kubeconfig=../scheduler.conf

# scheduler set default context
kubectl config use-context system:kube-scheduler@kubernetes \
    --kubeconfig=../scheduler.conf

#  Kubelet master certificate

#  下载kubelet-csr.json文件，并生成 master node certificate 证书：
cp ${PKI_URL}/kubelet-csr.json
sed -i 's/$NODE/master1/g' kubelet-csr.json
cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=master1,172.16.35.12,172.16.35.12 \
  -profile=kubernetes \
  kubelet-csr.json | cfssljson -bare kubelet

ls kubelet*.pem

# 接着通过以下指令生成名称为 kubelet.conf 的 kubeconfig 文件：

# kubelet set-cluster
$ kubectl config set-cluster kubernetes \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=${KUBE_APISERVER} \
    --kubeconfig=../kubelet.conf

# kubelet set-credentials
$ kubectl config set-credentials system:node:master1 \
    --client-certificate=kubelet.pem \
    --client-key=kubelet-key.pem \
    --embed-certs=true \
    --kubeconfig=../kubelet.conf

# kubelet set-context
$ kubectl config set-context system:node:master1@kubernetes \
    --cluster=kubernetes \
    --user=system:node:master1 \
    --kubeconfig=../kubelet.conf

# kubelet set default context
$ kubectl config use-context system:node:master1@kubernetes \
    --kubeconfig=../kubelet.conf

#  Service account key
#  Service account 不是通过 CA 进行认证，因此不要通过 CA 来做 Service account key 的检查，这边建立一组 Private 与 Public 密钥提供给 Service account key 使用：

 openssl genrsa -out sa.key 2048
 openssl rsa -in sa.key -pubout -out sa.pub
 ls sa.*

 # 完成后删除不必要文件：
 rm -rf *.json *.csr

# 确认/etc/kubernetes与/etc/kubernetes/pki有以下文件：
 ls /etc/kubernetes/
 ls /etc/kubernetes/pki

#  安装 Kubernetes 核心组件
#
# 首先下载 Kubernetes 核心组件 YAML 文件，这边我们不透过 Binary 方案来创建 Master 核心组件，而是利用 Kubernetes Static Pod 来创建，因此需下载所有核心组件的Static Pod文件到/etc/kubernetes/manifests目录：

# 生成一个用来加密 Etcd 的 Key：

export ETCD_KEY=$(head -c 32 /dev/urandom | base64)

# 在/etc/kubernetes/目录下，创建encryption.yml的加密 YAML 文件：
cat <<EOF > /etc/kubernetes/encryption.yml
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ETCD_KEY}
      - identity: {}
EOF

# 在/etc/kubernetes/目录下，创建audit-policy.yml的进阶审核策略 YAML 文件：

cat <<EOF > /etc/kubernetes/audit-policy.yml
apiVersion: audit.k8s.io/v1beta1
kind: Policy
rules:
- level: Metadata
EOF

# 下载kubelet.service相关文件来管理 kubelet：
export KUBELET_URL=/home/vagrant/service
mkdir -p /etc/systemd/system/kubelet.service.d
cp ${KUBELET_URL}/kubelet.service  /lib/systemd/system/kubelet.service
cp ${KUBELET_URL}/10-kubelet.conf  /etc/systemd/system/kubelet.service.d/10-kubelet.conf
