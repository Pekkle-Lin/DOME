#!/bin/bash

# install and start kubernetes master on centos 7 system
# openxxs@gmail.com
# http://domeos-script.bjctc.scs.sohucs.com/start_master_centos.sh

# update 2016-04-21: add cluster DNS nameserver and search into top of resolv.conf; format output; fix some bugs; change install package url
# update 2016-05-03: change install path from ${pwd} to "/usr/sbin/domeos/k8s/"; remove invalid log-dir parameter for Kubernetes
# update 2016-05-06: remove hostname check
# update 2016-05-23: chattr +i resolv.conf
# update 2016-05-24: replace install package url; add kernel version and docker version check
# update 2016-06-05: add kubernetes version setting; add flannel version setting, then seperate flanneld and mk-docker-opts.sh from domeos-k8s-master.tar.gz; master.tgz instead of domeos-k8s-master.tar.gz; add help info; remove kube-apiserver secure serve related parameters.
# update 2016-07-05: add authority configure.
# update 2017-05-11: support modifying the etcd path prefix

AVAILABLE_K8S_VERSION=("1.1.3" "1.1.7" "1.2.0" "1.2.0-ndots1" "1.2.4" "1.2.8" "1.2.8-ndots1" "1.3.11" "1.3.11-ndots1" "1.4.7" "1.4.7-ndots1" "1.5.5")
AVAILABLE_FLANNEL_VERSION=("0.5.5")
K8S_VERSION="1.4.7"
FLANNEL_VERSION="0.5.5"
K8S_INSTALL_PATH="/usr/sbin/domeos/k8s"
FLANNEL_INSTALL_PATH="/usr/sbin/domeos/flannel"
K8S_PACKAGE_URL_PREFIX="http://domeos-binpack.bjcnc.scs.sohucs.com/k8s/"
FLANNEL_BIN_URL_PREFIX="http://domeos-binpack.bjcnc.scs.sohucs.com/flannel/"
DOCKER_URL="https://get.docker.com/"
RESOLV_FILE="/etc/resolv.conf"
FLANNEL_PREFIX="/flannel/network"
DOCKER_REGISTRY_CRT_PATH="/etc/docker/certs.d"
DOCKER_REGISTRY_CRT_URL="/api/global/registry/private/certification"
DOCKER_OPTS="--log-level=warn --userland-proxy=false"
FLANNEL_OPTS=
KUBE_APISERVER_OPTS=
KUBE_CONTROLLER_MANAGER_OPTS="--cloud-provider="
KUBE_SCHEDULER_OPTS=
KUBE_PROXY_OPTS="--masquerade-all=true --proxy-mode=iptables"
SECURE_PORT=""
CERT_PATH="/var/run/kubernetes"
AUTH_CONFIG_FILE="/etc/sysconfig/kube-basic-auth.config"
KUBELET_CONFIG_PATH="/etc/sysconfig/kubelet.config"
K8S_PREFIX="/registry"
DOCKER_STARTUP_COMMAND="/usr/bin/dockerd"
DOCKER_EXEC_RELOAD="ExecReload=/bin/kill -s HUP \$MAINPID"

function command_exists ()
{
  command -v "$@" > /dev/null 2>&1
}
function device_exists ()
{
  ifconfig | grep $1 > /dev/null 2>&1
}
function service_exists ()
{
  systemctl list-unit-files | grep $1 > /dev/null 2>&1
}
# eg: 
#   17.05.0-ce > 1.12.3,
#   1.12.6 = 1.12.3,
#   1.10.3 < 1.12.3
function compare ()
{
  declare a=`echo "$1" | cut -d '.' -f 1,2`
  declare b=`echo "$2" | cut -d '.' -f 1,2`
  if [ "$a" = "$b" ]; then
    echo "="
    return
  fi
  max=`echo "$1
$2" | sort -t , -n -k 1,1 -k 2,2 -k 3,3 -k 4,4 | tail -n 1`
  if [ "$1" != "$max" ]; then
    echo "<"
  elif [ "$2" != "$max" ]; then
    echo ">"
  else
    echo "="
  fi
}

function help ()
{
  echo "
Usage:
  start_master_centos.sh [options]
  start_master_centos.sh [command]

Available Commands:
  help    show the help information about start_master_centos.sh

Options:
  --cluster-dns                 IP address of cluster DNS, should be in range of --service-cluster-ip-range (default 172.16.40.1).
  --cluster-domain              search domain of cluster DNS (default domeos.local).
  --docker-graph-path           root of the Docker runtime (default /var/lib/docker).
  --domeos-server               DomeOS server address, it is required when --insecure-registry-crt=true.
  --etcd-servers                (REQUIRED) a comma-delimited list of etcd servers to watch (http://ip:port).
  --etcd-prefix                 the prefix for all resource paths in etcd.
  --flannel-network-ip-range    flannel network ip range (default 172.24.0.0/13).
  --flannel-subnet-len          flannel subnet length (default 22).
  --flannel-version             flannel version (default $FLANNEL_VERSION).
  --insecure-bind-address       IP address on which to serve kube-apiserver --insecure-port (default 0.0.0.0).
  --insecure-port               port on which to serve kube-apiserver unsecured, unauthenticated access (default 8080).
  --kube-apiserver-port         port on which to serve kube-apiserver access for kube-proxy, kube-scheduler and kube-controller-manager (default 8080).
  --kubernetes-version          Kubernetes version (default $K8S_VERSION).
  --service-cluster-ip-range    a CIDR notation IP range from which to assign Kubernetes service cluster IPs. This must not overlap with any IP ranges assigned to nodes for pods (default 172.16.0.0/13).
  --registry-type               (REQUIRED) Docker registry type (available value {'http', 'https'}).
  --registry-arg                (REQUIRED) Docker secure registry communication address for --registry-type=https; Docker insecure registry communication address for --registry-type=http.
  --insecure-registry-crt       if your docker registry use insecure crt, then you need set the argument to true, default false.
Security Options:
  --secure-port            The port on which to serve HTTPS with authentication and authorization for api-server. It should be a positive integer. If absent, do not serve HTTPS at all.
  --kube-user                   The user for authentication, and the user will own all priority (default admin).
  --kube-passwd                 Password for kube-user (default admin).
"
}

echo "
*************************************************************************
            Welcome to install DomeOS Kubernetes Master!
                Contact us: rdc-domeos@sohu-inc.com
*************************************************************************
This is a shell script for install, configure and start Kubernetes Master for DomeOS on CentOS 7. It will start flanneld, docker, kube-apiserver, kube-controller-manager, kube-scheduler and kube-proxy after successful execution.

Attention:
1. This shell will try to install the latest docker if docker has not been installed. You can install docker by yourself before execute this shell. Docker version must be 1.8.2 at minimum, version 1.10.3 is recommanded.
2. This shell will reset flannel and docker configure file.
3. Use 'bash start_master_centos.sh help' to get more information.

Usage Example:
1. Simple options, use default values:
sudo bash start_master_centos.sh --etcd-servers http://0.0.0.0:4012,http://0.0.0.1:4012,http://0.0.0.2:4012 --registry-type http --registry-arg 10.10.10.10:5000

2. Full options:
sudo bash start_master_centos.sh --cluster-dns 172.16.40.1 --cluster-domain domeos.local --docker-graph-path /opt/domeos/openxxs/docker --etcd-servers http://0.0.0.0:4012,http://0.0.0.1:4012,http://0.0.0.2:4012 --etcd-prefix domeos --flannel-network-ip-range 172.24.0.0/13 --flannel-subnet-len 22 --flannel-version 0.5.5 --insecure-bind-address 0.0.0.0 --insecure-port 8080 --kube-apiserver-port 8080 --kubernetes-version 1.2.0 --service-cluster-ip-range 172.16.0.0/13 --registry-type http --registry-arg 10.10.10.10:5000 --secure-port 443 --kube-user admin --kube-passwd admin
"

if [[ "$1" =~ "help" ]] || [ -z "$1" ]; then
  help
  exit 1
fi

# STEP 01: check linux kernel version and curl/wget tools
echo -e "\033[36m[INFO] STEP 01: Check Linux kernel version and curl/wget tools...\033[0m"
kernel_version=`uname -r`
if [ -z $kernel_version ]; then
  echo -e "\033[31m[ERROR] get kernel version error, kernel must be 3.10.0 at minimum\033[0m"
  exit 1
fi
kernel_parts_tmp=(${kernel_version//-/ })
kernel_parts=(${kernel_parts_tmp[0]//./ })
if [ ${kernel_parts[0]} -lt 3 ]; then
  echo -e "\033[31m[ERROR] Kernel version must be 3.10.0 at minimum, current version is ${kernel_parts_tmp[0]}\033[0m"
  exit 1
fi
if [ ${kernel_parts[0]} -eq 3 ] && [ ${kernel_parts[1]} -lt 10 ]; then
  echo -e "\033[31m[ERROR] Kernel version must be 3.10.0 at minimum, current version is ${kernel_parts_tmp[0]}\033[0m"
  exit 1
fi
echo -e "\033[32m[OK] Check kernel OK, current kernel version is ${kernel_parts_tmp[0]}\033[0m"
if ! command_exists curl; then
  yum install -y curl
fi
if ! command_exists wget; then
  yum install -y wget
fi
# STEP 02: check arguments
echo -e "\033[36m[INFO] STEP 02: Check input arguments...\033[0m"
OPTS=$(getopt -o : --long cluster-dns:,cluster-domain:,docker-graph-path:,domeos-server:,etcd-servers:,etcd-prefix:,flannel-network-ip-range:,flannel-subnet-len:,flannel-version:,insecure-bind-address:,insecure-port:,kube-apiserver-port:,kubernetes-version:,service-cluster-ip-range:,registry-type:,registry-arg:,insecure-registry-crt:,secure-port:,kube-user:,kube-passwd: -- "$@")
if [ $? != 0 ]
then
  echo -e "\033[31m[ERROR] start_master_centos.sh argument is illegal\033[0m"
  exit 1
fi
eval set -- "$OPTS"
cluster_dns=
cluster_domain=
docker_graph_path=
etcd_servers=
etcd_prefix=
flannel_network_ip_range=
flannel_subnet_len=
flannel_version=
insecure_bind_address=
insecure_port=
domeos_server=
kube_apiserver_port=
kubernetes_version=
service_cluster_ip_range=
registry_type=
registry_arg=
insecure_registry_crt=false
secure_port=
kube_user=
kube_passwd=
while true ; do
  case "$1" in
    --cluster-dns) cluster_dns=$2; shift 2;;
    --cluster-domain) cluster_domain=$2; shift 2;;
    --docker-graph-path) docker_graph_path=$2; shift 2;;
    --domeos-server) domeos_server=$2; shift 2;;
    --etcd-servers) etcd_servers=$2; shift 2;;
    --etcd-prefix) etcd_prefix=$2; shift 2;;
    --flannel-network-ip-range) flannel_network_ip_range=$2; shift 2;;
    --flannel-subnet-len) flannel_subnet_len=$2; shift 2;;
    --flannel-version) flannel_version=$2; shift 2;;
    --insecure-bind-address) insecure_bind_address=$2; shift 2;;
    --insecure-port) insecure_port=$2; shift 2;;
    --kube-apiserver-port) kube_apiserver_port=$2; shift 2;;
    --kubernetes-version) kubernetes_version=$2; shift 2;;
    --service-cluster-ip-range) service_cluster_ip_range=$2; shift 2;;
    --registry-type) registry_type=$2; shift 2;;
    --registry-arg) registry_arg=$2; shift 2;;
    --insecure-registry-crt) insecure_registry_crt=$2; shift 2;;
    --secure-port) secure_port=$2; shift 2;;
    --kube-user) kube_user=$2; shift 2;;
    --kube-passwd) kube_passwd=$2; shift 2;;
    --) shift; break;;
  esac
done
if [ -z "$cluster_dns" ]; then
  echo -e "\033[36m[INFO] --cluster-dns is absent, default '172.16.40.1'\033[0m"
  cluster_dns="172.16.40.1"
else
  cluster_dns_check=`echo $cluster_dns | grep ':' | wc | awk '{print $3}'`
  if [ $cluster_dns_check -gt 0 ]; then
    echo -e "\033[33m[WARN] --cluster-dns $cluster_dns includes port, it is illegal\033[0m"
    cluster_dns=`echo $cluster_dns | cut -f1 -d ':'`
    echo -e "\033[36m[INFO] use '--cluster-dns $cluster_dns' instead, DNS port always be 53\033[0m"
  else
    echo "--cluster-dns: $cluster_dns"
  fi
fi
if [ -z "$cluster_domain" ]; then
  echo -e "\033[36m[INFO] --cluster-domain is absent, default 'domeos.local'\033[0m"
  cluster_domain="domeos.local"
else
  echo "--cluster-domain: $cluster_domain"
fi
if [ -z "$docker_graph_path" ]; then
  echo -e "\033[36m[INFO] --docker-graph-path is absent, default '/var/lib/docker'\033[0m"
  docker_graph_path="/var/lib/docker"
else
  echo "--docker-graph-path: $docker_graph_path"
fi
if [ -z "$etcd_servers" ]; then
  echo -e "\033[31m[ERROR] --etcd-servers is absent\033[0m"
  exit 1
else
  echo "--etcd-servers: $etcd_servers"
fi
if [ -z "$etcd_prefix" ]; then
  echo -e "\033[36m[INFO] --etcd-prefix is absent\033[0m"
else
  etcd_prefix="/`echo $etcd_prefix | sed 's/\(^[\/]*\)//' | sed 's/\([\/]*$\)//'`"
  echo "--etcd-prefix: $etcd_prefix"
  KUBE_APISERVER_OPTS="$KUBE_APISERVER_OPTS --etcd-prefix=$etcd_prefix$K8S_PREFIX"
fi
if [ -z "$flannel_network_ip_range" ]; then
  echo -e "\033[36m[INFO] --flannel-network-ip-range is absent, default '172.24.0.0/13'\033[0m"
  flannel_network_ip_range='172.24.0.0/13'
else
  echo "--flannel-network-ip-range: $flannel_network_ip_range"
fi
if [ -z "$flannel_subnet_len" ]; then
  echo -e "\033[36m[INFO] --flannel-subnet-len is absent, default '22'\033[0m"
  flannel_subnet_len=22
else
  echo "--flannel-subnet-len: $flannel_subnet_len"
fi
if [ -z "$flannel_version" ]; then
  echo -e "\033[36m[INFO] --flannel-version is absent, default '$FLANNEL_VERSION'\033[0m"
  flannel_version=$FLANNEL_VERSION
else
  available="false"
  for i in ${AVAILABLE_FLANNEL_VERSION[@]} ; do
    if [ "$i" == "$flannel_version" ]; then
      available="true"
      break
    fi
  done
  if [ "$available" == "true" ]; then
    echo "--flannel-version: $flannel_version"
  else
    echo -e "\033[31m[ERROR] this shell script does not provide Flannel $flannel_version package\033[0m"
    exit 1
  fi
fi
if [ -z "$insecure_bind_address" ]; then
  echo -e "\033[36m[INFO] --insecure-bind-address is absent, default '0.0.0.0'\033[0m"
  insecure_bind_address='0.0.0.0'
else
  echo "--insecure-bind-address: $insecure_bind_address"
fi
if [ -z "$insecure_port" ]; then
  echo -e "\033[36m[INFO] --insecure-port is absent, default '8080'\033[0m"
  insecure_port=8080
else
  echo "--insecure-port: $insecure_port"
fi
if [ -z "$kube_apiserver_port" ]; then
  echo -e "\033[36m[INFO] --kube-apiserver-port is absent, default '8080'\033[0m"
  kube_apiserver_port=8080
else
  echo "--kube-apiserver-port: $kube_apiserver_port"
fi
if [ -z "$kubernetes_version" ]; then
  echo -e "\033[36m[INFO] --kubernetes-version is absent, default '$K8S_VERSION'\033[0m"
  kubernetes_version=$K8S_VERSION
else
  available="false"
  for i in ${AVAILABLE_K8S_VERSION[@]} ; do
    if [ "$i" == "$kubernetes_version" ]; then
      available="true"
      break
    fi
  done
  if [ "$available" == "true" ]; then
    echo "--kubernetes-version: $kubernetes_version"
  else
    echo -e "\033[31m[ERROR] this shell script does not provide Kubernetes $kubernetes_version package\033[0m"
    exit 1
  fi
fi
if [ -z "$service_cluster_ip_range" ]; then
  echo -e "\033[36m[INFO] --service-cluster-ip-range is absent, default '172.16.0.0/13'\033[0m"
  service_cluster_ip_range='172.16.0.0/13'
else
  echo "--service-cluster-ip-range: $service_cluster_ip_range"
fi
if [ -z "$domeos_server" ]; then
  if [ $insecure_registry_crt = true ]; then
    echo -e "\033[31m[ERROR] --domeos-server is absent. This shell needs to curl docker registry certification from DomeOS server if you set '--insecure-registry-crt true'\033[0m"
    exit 1
  fi
else
  echo "--domeos-server: $domeos_server"
fi
if [ -z "$registry_type" ]; then
  echo -e "\033[31m[ERROR] --registry-type is absent\033[0m"
  exit 1
else
  echo "--registry-type: $registry_type"
fi
if [ -z "$registry_arg" ]; then
  echo -e "\033[31m[ERROR] --registry-arg is absent\033[0m"
  exit 1
else
  echo "--registry-arg: $registry_arg"
fi

if [ -n "$secure_port" ]; then
    if [ $secure_port -le 0 ]; then
        echo -e "\033[31m[ERROR] --secure-port $secure_port is not a positive integer\033[0m"
        exit 1
    fi
    echo -e "\033[36m[INFO] --secure-port: $secure_port\033[0m"
    if [ -z "$kube_user" ]; then
        echo -e "\033[36m[INFO] --kube-user is absent, default 'admin'\033[0m"
        kube_user='admin'
    else
        echo -e "\033[36m[INFO] --kube-user: $kube_user\033[0m"
    fi
    if [ -z "$kube_passwd" ]; then
        echo -e "\033[36m[INFO] --kube-passwd is absent, default 'admin'\033[0m"
        kube_passwd='admin'
    else
        echo -e "\033[36m[INFO] --kube-passwd: $kube_passwd\033[0m"
    fi
fi
echo -e "\033[32m[OK] start_master_centos.sh arguments are legal\033[0m"

# STEP 03: check host IP
echo -e "\033[36m[INFO] STEP 03: Check host IP...\033[0m"
host_hostname=`hostname`
current_path=$(pwd)
host_ips=(`ip addr show | grep inet | grep -v inet6 | grep brd | awk '{print $2}' | cut -f1 -d '/'`)
if [ -z "$host_ips" ]; then
  echo -e "\033[31m[ERROR] get host ip address error\033[0m"
  exit 1
fi
host_ip=
for i in ${host_ips[@]}
do
  ip_parts=(${i//./ })
  if [ ${ip_parts[0]} -eq 10 ]; then
    host_ip=$i
    break
  fi
  if [ ${ip_parts[0]} -eq 172 ] && [ ${ip_parts[1]} -ge 16 ]; then
    host_ip=$i
    break
  fi
  if [ ${ip_parts[0]} -eq 192 ] && [ ${ip_parts[1]} -eq 168 ]; then
    host_ip=$i
    break
  fi
done
if [ -z "$host_ip" ]; then
  host_ip=${host_ips[0]}
fi
echo -e "\033[32m[OK] use host IP address: $host_ip\033[0m"

# STEP 04: download and decompress installation package
echo -e "\033[36m[INFO] STEP 04: Download and decompress installation package...\033[0m"
set -e
wget -c -O master.tgz "$K8S_PACKAGE_URL_PREFIX$kubernetes_version/master.tgz"
tar -zxvf master.tgz --no-same-owner
wget -c -O flanneld "$FLANNEL_BIN_URL_PREFIX$flannel_version/flanneld"
wget -c -O mk-docker-opts.sh "$FLANNEL_BIN_URL_PREFIX$flannel_version/mk-docker-opts.sh"
chmod +x $current_path/master/kube-apiserver
chmod +x $current_path/master/kube-controller-manager
chmod +x $current_path/master/kube-scheduler
chmod +x $current_path/master/kube-proxy
chmod +x $current_path/master/kubectl
chmod +x $current_path/flanneld
chmod +x $current_path/mk-docker-opts.sh
mkdir -p $K8S_INSTALL_PATH/$kubernetes_version
mkdir -p $FLANNEL_INSTALL_PATH/$flannel_version
mkdir -p /usr/libexec/flannel
mkdir -p /run/flannel
mkdir -p /usr/lib/systemd/system/docker.service.d
mv $current_path/master/kube-apiserver $K8S_INSTALL_PATH/$kubernetes_version/
mv $current_path/master/kube-controller-manager $K8S_INSTALL_PATH/$kubernetes_version/
mv $current_path/master/kube-scheduler $K8S_INSTALL_PATH/$kubernetes_version/
mv $current_path/master/kube-proxy $K8S_INSTALL_PATH/$kubernetes_version/
mv $current_path/master/kubectl $K8S_INSTALL_PATH/$kubernetes_version/
ln -fsn $K8S_INSTALL_PATH/$kubernetes_version $K8S_INSTALL_PATH/current
mv $current_path/flanneld $FLANNEL_INSTALL_PATH/$flannel_version/
ln -fsn $FLANNEL_INSTALL_PATH/$flannel_version $FLANNEL_INSTALL_PATH/current
mv $current_path/mk-docker-opts.sh /usr/libexec/flannel/mk-docker-opts.sh
set +e
echo -e "\033[32m[OK] Download and place required files\033[0m"

# STEP 05: check iface for flannel
echo -e "\033[36m[INFO] STEP 05: Check iface for flannel...\033[0m"
flannel_iface=(`ip addr show | grep $host_ip | awk '{print $NF}'`)
if [ -z "$flannel_iface" ]; then
  echo -e "\033[31m[ERROR] get ip iface error\033[0m"
  exit 1
else
  flannel_iface=${flannel_iface[0]}
  echo -e "\033[32m[OK] use flannel iface: $flannel_iface\033[0m"
fi

# STEP 06: add DNS server into resolv.conf 
echo -e "\033[36m[INFO] STEP 06: Cluster DNS nameserver and search will be added into top of $RESOLV_FILE\033[0m"
echo -e "\033[36mYou may press Ctrl+C now to abort this script.\033[0m"
echo -e "\033[36mwaiting for 10 seconds...\033[0m"
sleep 10
cluster_dns_search="default.svc.$cluster_domain svc.$cluster_domain $cluster_domain"
host_self_dns=
host_self_dns_p=0
while IFS='' read -r line || [[ -n "$line" ]]; do
  name_tmp=$(echo $line | cut -f1 -d ' ')
  value_tmp=$(echo $line | cut -f2- -d ' ')
  if [ "$name_tmp" == "nameserver" ]; then
    if [ "$cluster_dns" != "$value_tmp" ]; then
      host_self_dns[$host_self_dns_p]="$line"
      let host_self_dns_p++
    fi
  elif [ "$name_tmp" == "search" ]; then
    if [ "$cluster_dns_search" != "$value_tmp" ]; then
      host_self_dns[$host_self_dns_p]="$line"
      let host_self_dns_p++
    fi
  else
    host_self_dns[$host_self_dns_p]="$line"
    let host_self_dns_p++
  fi
done < $RESOLV_FILE
set -e
chattr -i $RESOLV_FILE
echo "search $cluster_dns_search" > $RESOLV_FILE
echo "nameserver $cluster_dns" >> $RESOLV_FILE
for i in "${host_self_dns[@]}"
do
  echo $i >> $RESOLV_FILE
done
chattr +i $RESOLV_FILE
set +e
echo -e "\033[32m[OK] Add DNS nameserver and search into $RESOLV_FILE\033[0m"

# STEP 07: add hostname and IP address to /etc/hosts
echo -e "\033[36m[INFO] STEP 07: Add hostname and IP address to /etc/hosts...\033[0m"
exist_hosts="false"
while IFS='' read -r line || [[ -n "$line" ]]; do
  ip_tmp=$(echo $line | cut -f1 -d ' ')
  hostname_tmp=$(echo $line | cut -f2 -d ' ')
  if [ "$host_ip" == "$ip_tmp" ]; then
    if [ "$host_hostname" == "$hostname_tmp" ]; then
      exist_hosts="true"
      break
    fi
  fi
done < /etc/hosts
set -e
if [ $exist_hosts == "false" ]; then
  echo "$host_ip $host_hostname" >> /etc/hosts
fi
set +e
echo -e "\033[32m[OK] Add hostname and IP address to /etc/hosts\033[0m"

# STEP 08: Configure flannel
echo -e "\033[36m[INFO] STEP 08: Configure Flannel...\033[0m"
flannel_k8s_config="{\"Network\": \"${flannel_network_ip_range}\", \"SubnetLen\": ${flannel_subnet_len}, \"Backend\": {\"Type\": \"vxlan\", \"VNI\": 1}}"
single_etcd_server=$(echo $etcd_servers | cut -f1 -d ',')
curl -L $single_etcd_server/v2/keys$etcd_prefix$FLANNEL_PREFIX/config -XPUT -d value="${flannel_k8s_config}"
if command_exists flanneld && [ -e /usr/libexec/flannel/mk-docker-opts.sh ]; then
  echo -e "\033[36m[INFO] flanneld command already exists on this system.\033[0m"
  echo -e "\033[36m/etc/sysconfig/flanneld /usr/lib/systemd/system/docker.service.d/flannel.conf and /lib/systemd/system/flanneld.service files will be reset\033[0m"
  echo -e "\033[36mYou may press Ctrl+C now to abort this script.\033[0m"
  echo -e "\033[36mwaiting for 10 seconds...\033[0m"
  sleep 10
fi
  # check http:// prefix of etcd address
flannel_etcd_servers=
flannel_etcds=(${etcd_servers//,/ })
for i in ${flannel_etcds[@]}
do
  if [[ $i =~ "http://" ]] || [[ $i =~ "https://" ]]; then
    if [ -z "$flannel_etcd_servers" ]; then
      flannel_etcd_servers="$i"
    else
      flannel_etcd_servers="$flannel_etcd_servers,$i"
    fi
  else
    if [ -z "$flannel_etcd_servers" ]; then
      flannel_etcd_servers="http://$i"
    else
      flannel_etcd_servers="$flannel_etcd_servers,http://$i"
    fi
  fi
done
echo "FLANNEL_ETCD=\"$flannel_etcd_servers\"
FLANNEL_ETCD_KEY=\"$etcd_prefix$FLANNEL_PREFIX\"
FLANNEL_IFACE=\"$flannel_iface\"
FLANNEL_OPTIONS=\"$FLANNEL_OPTS\"
" > /etc/sysconfig/flanneld
echo "[Service]
EnvironmentFile=-/run/flannel/docker" > /usr/lib/systemd/system/docker.service.d/flannel.conf
echo "[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/flanneld
EnvironmentFile=-/etc/sysconfig/docker-network
ExecStart=$FLANNEL_INSTALL_PATH/current/flanneld -etcd-endpoints=\${FLANNEL_ETCD} -etcd-prefix=\${FLANNEL_ETCD_KEY} -iface=\${FLANNEL_IFACE} \$FLANNEL_OPTIONS
ExecStartPost=/usr/libexec/flannel/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d /run/flannel/docker
Restart=always

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
" > /lib/systemd/system/flanneld.service
if [ -e $FLANNEL_INSTALL_PATH/current/flanneld ] && [ -e /usr/libexec/flannel/mk-docker-opts.sh ]; then
  echo -e "\033[32m[OK] flannel environment is ready\033[0m"
else
  echo -e "\033[31m[ERROR] flannel environment is not ready\033[0m"
  exit 1
fi

# STEP 09: install and configure docker
if command_exists docker; then
  echo -e "\033[36m[INFO] STEP 09: docker command alrealy exists on this system.\033[0m"
  echo -e "\033[36m/etc/sysconfig/docker and /lib/systemd/system/docker.service files will be reset.\033[0m"
  echo -e "\033[36mYou may press Ctrl+C now to abort this script.\033[0m"
  echo -e "\033[36mwaiting for 10 seconds...\033[0m"
  sleep 10
else
  #yum install -y docker-engine-selinux-1.10.2-1.el7.centos.noarch.rpm
  #yum install -y docker-engine-1.10.2-1.el7.centos.x86_64.rpm
  echo -e "\033[36m[INFO] STEP 09: Install and configure docker...\033[0m"
  curl -sSL $DOCKER_URL | sh
fi
current_version=`docker --version | awk '{print $3}' | cut -d ',' -f 1`
if [ "`compare $current_version 1.12.0`" = "<" ]; then
  DOCKER_STARTUP_COMMAND="/usr/bin/docker daemon"
  DOCKER_EXEC_RELOAD=""
fi
docker_opts="DOCKER_OPTS=\"$DOCKER_OPTS\""
echo $docker_opts > /etc/sysconfig/docker
if [ -n "$docker_graph_path" ]; then
  docker_storage_options="DOCKER_STORAGE_OPTIONS=\"--graph $docker_graph_path\""
  echo $docker_storage_options >> /etc/sysconfig/docker
fi
if [ "$registry_type" == "http" ]; then
  registry_arg=$(echo $registry_arg | sed -e 's/https:\/\///g')
  registry_arg=$(echo $registry_arg | sed -e 's/http:\/\///g')
  if [ -n "$registry_arg" ]; then
    docker_insecure_registry="INSECURE_REGISTRY=\"--insecure-registry $registry_arg\""
    echo $docker_insecure_registry >> /etc/sysconfig/docker
  fi
elif [ "$registry_type" == "https" ]; then
  registry_arg=$(echo $registry_arg | sed -e 's/https:\/\///g')
  if [ $insecure_registry_crt = true ]; then
    mkdir -p $DOCKER_REGISTRY_CRT_PATH/$registry_arg
    registry_crt="$DOCKER_REGISTRY_CRT_PATH/$registry_arg/registry.crt"
    registry_crt_url="$domeos_server$DOCKER_REGISTRY_CRT_URL"
    #cp $current_path/registry.crt $registry_crt
    wget -c -O $registry_crt $registry_crt_url
    if [ -f $registry_crt ]; then
      echo -e "\033[32m[OK] install docker registry certification\033[0m"
    else
      echo -e "\033[31m[ERROR] install docker secure registry certification failed\033[0m"
      exit 1
    fi
    echo -e "\033[32m[OK] install docker registry certification\033[0m"
  fi
fi
sed -i '/\[Service\]/, $d' /lib/systemd/system/docker.service
echo "[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/docker
ExecStart=$DOCKER_STARTUP_COMMAND \$DOCKER_OPTS \\
\$DOCKER_STORAGE_OPTIONS \\
\$DOCKER_NETWORK_OPTIONS \\
\$ADD_REGISTRY \\
\$BLOCK_REGISTRY \\
\$INSECURE_REGISTRY
$DOCKER_EXEC_RELOAD

MountFlags=slave
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes

[Install]
WantedBy=multi-user.target
" >> /lib/systemd/system/docker.service
if command_exists docker ; then
  echo -e "\033[32m[OK] docker environment is ready\033[0m"
else
  echo -e "\033[31m[ERROR] docker environment is not ready\033[0m"
  exit 1
fi

# STEP 10: start flannel
echo -e "\033[36m[INFO] STEP 10: Start Flannel...\033[0m"
systemctl daemon-reload
systemctl stop docker
systemctl stop flanneld
if device_exists docker0; then
  ip link delete docker0
fi
if device_exists flannel.1; then
  ip link delete flannel.1
fi
if service_exists iptables; then
  systemctl disable iptables
  systemctl stop iptables
fi
if service_exists firewalld; then
  systemctl disable firewalld
  systemctl stop firewalld
fi
iptables -P FORWARD ACCEPT
systemctl start flanneld
systemctl enable flanneld
sleep 5
systemctl status -l flanneld

# STEP 11: start docker
echo -e "\033[36m[INFO] STEP 11: Start Docker...\033[0m"
systemctl start docker
systemctl enable docker
sleep 8
systemctl status -l docker

# STEP 12: start kube-apiserver
echo -e "\033[36m[INFO] STEP 12: Start kube-apiserver...\033[0m"
if service_exists kube-apiserver; then
  systemctl stop kube-apiserver
fi
echo "# configure file for kube-apiserver

# --etcd-servers
ETCD_SERVERS='--etcd-servers=$etcd_servers'
# --service-cluster-ip-range
SERVICE_CLUSTER_IP_RANGE='--service-cluster-ip-range=$service_cluster_ip_range'
# other parameters
KUBE_APISERVER_OPTS='$KUBE_APISERVER_OPTS'
" >> /etc/sysconfig/kube-apiserver
if [ -n "$secure_port" ]; then
    mkdir -p $CERT_PATH
    mkdir -p $(dirname AUTH_CONFIG_FILE)
    exist_config="false"
    kube_auth_config="$kube_user,$kube_passwd,1"
    while IFS='' read -r line || [[ -n "$line" ]]; do
        if [ "$line" == "$kube_auth_config" ]; then
            exist_config="true"
            break
        fi
    done < $AUTH_CONFIG_FILE
    if [ $exist_config == "false" ]; then
        echo $kube_auth_config >> $AUTH_CONFIG_FILE
    fi
    echo "# --secure-port
SECURE_PORT='--secure-port=$secure_port'
# --cert-dir
CERT_DIR='--cert-dir=$CERT_PATH'
# --basic-auth-file
BASIC_AUTH_CONFIG='--basic-auth-file=$AUTH_CONFIG_FILE'
" >> /etc/sysconfig/kube-apiserver
    #create config file
    mkdir -p $(dirname $KUBELET_CONFIG_PATH)
    echo "
apiVersion: v1
kind: Config
preferences:
  colors: true
current-context: federal-context
contexts:
- context:
    cluster: horse-cluster
    user: green-user
  name: federal-context
users:
- name: green-user
  user:
    username: $kube_user
    password: $kube_passwd
clusters:
- cluster:
    api-version: v1
    insecure-skip-tls-verify: true
    server: https://$host_ip:$secure_port
  name: horse-cluster
    " > $KUBELET_CONFIG_PATH
else
echo "
# --insecure-bind-address
INSECURE_BIND_ADDRESS='--insecure-bind-address=$insecure_bind_address'
# --insecure-port
INSECURE_PORT='--insecure-port=$insecure_port'
" >> /etc/sysconfig/kube-apiserver
fi

echo "[Unit]
Description=kube-apiserver
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/etc/sysconfig/kube-apiserver
ExecStart=$K8S_INSTALL_PATH/current/kube-apiserver \$ETCD_SERVERS \\
          \$SERVICE_CLUSTER_IP_RANGE \\
          \$INSECURE_BIND_ADDRESS \\
          \$INSECURE_PORT \\
          \$KUBE_APISERVER_OPTS \\
          \$SECURE_PORT \\
          \$CERT_DIR \\
          \$BASIC_AUTH_CONFIG
Restart=always

[Install]
WantedBy=multi-user.target
" > /lib/systemd/system/kube-apiserver.service
systemctl daemon-reload
systemctl start kube-apiserver
systemctl enable kube-apiserver
sleep 8
systemctl status -l kube-apiserver

# STEP 13: start kube-controller-manager
echo -e "\033[36m[INFO] STEP 13: Start kube-controller-manager...\033[0m"
if service_exists kube-controller; then
  systemctl stop kube-controller
fi

if [ -n "$secure_port" ]; then
KUBE_CONTROLLER_MANAGER_OPTS="$KUBE_CONTROLLER_MANAGER_OPTS --kubeconfig=$KUBELET_CONFIG_PATH"
    echo "
# --master
KUBE_MASTER='--master=https://$host_ip:$secure_port'
" > /etc/sysconfig/kube-controller
else
    echo "
# --master
KUBE_MASTER='--master=http://$host_ip:$kube_apiserver_port'
" > /etc/sysconfig/kube-controller
fi
echo "# configure file for kube-controller-manager

# other parameters
KUBE_CONTROLLER_OPTS='$KUBE_CONTROLLER_MANAGER_OPTS'
" >> /etc/sysconfig/kube-controller

echo "[Unit]
Description=kube-controller-manager
After=kube-apiserver.service
Wants=kube-apiserver.service

[Service]
EnvironmentFile=/etc/sysconfig/kube-controller
ExecStart=$K8S_INSTALL_PATH/current/kube-controller-manager \$KUBE_MASTER \\
          \$KUBE_CONTROLLER_OPTS
Restart=always

[Install]
WantedBy=multi-user.target
" > /lib/systemd/system/kube-controller.service
systemctl daemon-reload
systemctl start kube-controller
systemctl enable kube-controller
sleep 5
systemctl status -l kube-controller

# STEP 14: start kube-scheduler
echo -e "\033[36m[INFO] STEP 14: Start kube-scheduler...\033[0m"
if service_exists kube-scheduler; then
  systemctl stop kube-scheduler
fi
if [ -n "$secure_port" ]; then
KUBE_SCHEDULER_OPTS="$KUBE_SCHEDULER_OPTS --kubeconfig=$KUBELET_CONFIG_PATH"
    echo "
# --master
KUBE_MASTER='--master=https://$host_ip:$secure_port'
" > /etc/sysconfig/kube-scheduler
else
    echo "
# --master
KUBE_MASTER='--master=http://$host_ip:$kube_apiserver_port'
" > /etc/sysconfig/kube-scheduler
fi
echo "# configure file for kube-scheduler

# other parameters
KUBE_SCHEDULER_OPTS='$KUBE_SCHEDULER_OPTS'
" >> /etc/sysconfig/kube-scheduler

echo "[Unit]
Description=kube-scheduler
After=kube-apiserver.service
Wants=kube-apiserver.service

[Service]
EnvironmentFile=/etc/sysconfig/kube-scheduler
ExecStart=$K8S_INSTALL_PATH/current/kube-scheduler \$KUBE_MASTER \\
          \$KUBE_SCHEDULER_OPTS
Restart=always

[Install]
WantedBy=multi-user.target
" > /lib/systemd/system/kube-scheduler.service
systemctl daemon-reload
systemctl start kube-scheduler
systemctl enable kube-scheduler
sleep 5
systemctl status -l kube-scheduler

# STEP 15: start kube-proxy
echo -e "\033[36m[INFO] STEP 15: Start kube-proxy...\033[0m"
if service_exists kube-proxy; then
  systemctl stop kube-proxy
fi
if [ -n "$secure_port" ]; then
KUBE_PROXY_OPTS="$KUBE_PROXY_OPTS --kubeconfig=$KUBELET_CONFIG_PATH"
    echo "
KUBE_MASTER='--master=https://$host_ip:$secure_port'
" > /etc/sysconfig/kube-proxy
else
    echo "
KUBE_MASTER='--master=http://$host_ip:$kube_apiserver_port'
" > /etc/sysconfig/kube-proxy
fi
echo "# configure file for kube-proxy
# other parameters
KUBE_PROXY_OPTS='$KUBE_PROXY_OPTS'
" >> /etc/sysconfig/kube-proxy

echo "[Unit]
Description=kube-proxy

[Service]
EnvironmentFile=/etc/sysconfig/kube-proxy
ExecStart=$K8S_INSTALL_PATH/current/kube-proxy \$KUBE_MASTER \\
          \$KUBE_PROXY_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
" > /lib/systemd/system/kube-proxy.service
systemctl daemon-reload
systemctl start kube-proxy
systemctl enable kube-proxy
sleep 5
systemctl status -l kube-proxy
