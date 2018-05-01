#/bin/bash

#一键安装脚本使用说明
#一键安装脚本适用于DomeOS系统快速部署测试，不适用正是环境下的使用。该脚本可以多次执行，也可以用于已存在DomeOS组件重启，执行过程中如果遇到问题，请仔细阅读提示信息。
#该脚本会启动以下容器（括号中指出了该容器所属服务）：
#1.mysql(domeos-server,open-falcon)
#2.k8s,包括etcd、apiserver、controller-manager、scheduer、skydns
#3.open-falcon,包括graph、transfer、query、hbs、judge、alarm、sender、nodata、redis
#4.domeos-server,包括server、shellinabox

#在正式环境下，k8s（kubernetes）master组件中etcd推荐采用集群化部署，apiserver、controller、scheduler可以部署在同一物理机上。open-falcon组件推荐容器化启动，graph、transfer推荐部署多个副本，详细信息请参考http://book.open-falcon.org。
# images to use
REGISTRY=
DOMEOS_PREFIX=domeos

# kubernetes apiserver ports
KUBE_PORT=8888

# virtual ip range allocated
SERVICE_IP_RANGE="172.16.0.0/13"
POD_IP_RANGE="172.24.0.0/13"
SUBNETLEN=22

# mysql configuration
MYSQL_USER=domeos
MYSQL_PASSWORD=domeos-mysql-pw
MYSQL_PORT=3306
MYSQL_ROOT_PASSWORD=root-mysql-pw

# domeos configuration
DOMEOS_PORT=8080

set +e

function check_container ()
{
    EXISTS=`docker ps -a |awk '{print $NF}' |grep "$1" |wc -l`
    if [ $EXISTS != 0 ]; then
    echo -e -n "\033[33m[WARN] Conatiner named $1 exist, want to delete[y/N]?\033[0m"
    read OPTION
    if [[ "$OPTION" = "y" ]] || [[ "$OPTION" = "Y" ]]; then
        echo -e "\033[36m[INFO] Remove $1...\033[0m"
        docker rm -f $1 &> /dev/null
        if [ $? -ne 0 ]; then
            echo -e "\033[31m[ERROR] Delete $1 from docker failed!\033[0m";
            exit 1;
        fi
        echo -e "\033[32m[OK] Remove $1 success.\033[0m"
        return 1;
    else
        echo -e "\033[36m[INFO] Do not remove $1, continue...\033[0m"
        docker start $1 &> /dev/null
            return 0;
    fi
     else
        return 1;
     fi
}

function pull_image ()
{
    docker pull $1
    if [ $? -ne 0 ]; then
        echo -e "\033[31m[ERROR] pull image $1 failed!\033[0m";
        exit 1;
    fi
    echo -e "\033[32m[OK] pull image $1 success.\033[0m"
    return 1;
}

function help ()
{
    return 0;
	echo ""
    echo "Options:"
    echo "    --image-registry           Registry to download images, default is docker public registry, pub.domeos.org is alternative."
    echo "    --domeos-port              Port of domeos, default is 8080."
    echo "    --local-ip                 IP of this host. If not set, this script will get ip from ipconfig automaticly. Please do not use 127.0.0.1 or localhost."
    echo "    --kube-apiserver-port      Port of kubernetes api server, make sure the port is not used by other process. Default is 8888."
    echo "    --service-cluster-ip-range IP range of kubernetes service, default is 172.16.0.0/13."
    echo "    --flannel-network-ip-range IP range of kubernetes pod, default is 172.24.0.0/13."
    echo "    --flannel-subnet-len       Subnet length of node, default is 22."
    echo "    --mysql-port               Port of mysql. If mysql-host is not null, this parameter must be set. Or else you can set this for mysql container, default is 3306."
    echo "    --mysql-user               User in mysql to create tables and data for domeos. If mysql-host is not null, this parameter must be set. Or else you can set this for mysql container, default is \"domeos\"."
    echo "    --mysql-password           Password of mysql-user. If mysql-host is not null, this parameter must be set. Or else you can set this for mysql container, default is \"domeos-mysql-pw\"."
    echo "    --mysql-root-password      Password of user root in mysql, this is used to create database. If mysql-host is not null, this parameter must be set. Or else you can set this for mysql container, default is \"root-mysql-pw\""
    echo ""
}

echo -e "***************************************************************************

                   ██████╗  ██████╗ ███╗   ███╗███████╗
                   ██╔══██╗██╔═══██╗████  ████║██╔════╝
                   ██║  ██║██║   ██║██╔████╔██║█████╗
                   ██║  ██║██║   ██║██║╚██╔╝██║██╔══╝
                   ██████╔╝╚██████╔╝██║ ╚═╝ ██║███████╗
                   ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚══════╝

***************************************************************************
Version: 18May.1

Default port usage:
    DOME server           8080 can change
    etcd server           2379
    kubernetes api server 8888 can change
    skydns                53
    mysql server          3306 can change
    open-falcon transfer  8433/6060
    open-falcon graph     6070/6071
    open-falcon query     9966
    open-falcon hbs       6030/6031
    open-falcon judge     6080/6081
    open-falcon alarm     9912
    open-falcon sender    6066
    open-falcon nodata    6090
    open-falcon redis     6379"

sleep 2

if [[ "$1" =~ "help" ]]; then
    help
    exit 1;
else
    help
fi
OPTS=$(getopt -o : --long local-ip:,domeos-port:,kube-apiserver-port:,service-cluster-ip-range:,flannel-network-ip-range:,flannel-subnet-len:,mysql-port:,mysql-user:,mysql-password:,mysql-root-password:,image-registry: -- "$@")
if [ $? != 0 ]
then
    echo -e "\033[31m[ERROR] Argument is illegal\033[0m"
    exit 1
fi
eval set -- "$OPTS"
local_ip=
domeos_port=
kube_apiserver_port=
service_cluster_ip_range=
flannel_network_ip_range=
flannel_subnet_len=
mysql_port=
mysql_user=
mysql_password=
mysql_root_password=
image_registry=
while true ; do
  case "$1" in
    --local-ip) local_ip=$2; shift 2;;
    --domeos-port) domeos_port=$2; shift 2;;
    --kube-apiserver-port) kube_apiserver_port=$2; shift 2;;
    --service-cluster-ip-range) service_cluster_ip_range=$2; shift 2;;
    --flannel-network-ip-range) flannel_network_ip_range=$2; shift 2;;
    --flannel-subnet-len) flannel_subnet_len=$2; shift 2;;
    --mysql-host) mysql_host=$2; shift 2;;
    --mysql-port) mysql_port=$2; shift 2;;
    --mysql-user) mysql_user=$2; shift 2;;
    --mysql-password) mysql_password=$2; shift 2;;
    --mysql-root-password) mysql_root_password=$2; shift 2;;
    --image-registry) image_registry=$2; shift 2;;
    --) shift; break;;
  esac
done
if [ -n "$local_ip" ]; then
    LOCAL_IP=$local_ip
fi
if [ -n "$domeos_port" ]; then
    DOMEOS_PORT=$domeos_port
fi
if [ -n "$kube_apiserver_port" ]; then
    KUBE_PORT=$kube_apiserver_port
fi
if [ -n "$service_cluster_ip_range" ]; then
    SERVICE_IP_RANGE=$service_cluster_ip_range
fi
if [ -n "$flannel_network_ip_range" ]; then
    POD_IP_RANGE=$flannel_network_ip_range
fi
if [ -n "$flannel_subnet_len" ]; then
    SUBNETLEN=$flannel_subnet_len
fi
if [ -n "$mysql_host" ]; then
    MYSQL_HOST=$mysql_host
fi
if [ -n "$mysql_port" ]; then
    MYSQL_PORT=$mysql_port
fi
if [ -n "$mysql_user" ]; then
    MYSQL_USER=$mysql_user
fi
if [ -n "$mysql_password" ]; then
    MYSQL_PASSWORD=$mysql_password
fi
if [ -n "$mysql_root_password" ]; then
    MYSQL_ROOT_PASSWORD=$mysql_root_password
fi

if [ -n "$image_registry" ]; then
    echo ${image_registry}
    REGISTRY=${image_registry}/
fi

IMAGE_MYSQL=${REGISTRY}domeos/mysql-domeos:5.8
IMAGE_K8S=${REGISTRY}domeos/k8s-domeos:1.4.7
IMAGE_OPENFALCON=${REGISTRY}domeos/openfalcon-domeos:0.5
#IMAGE_SERVER=${REGISTRY}domeos/server:1.6.0
IMAGE_SERVER=hub.c.163.com/pekkle/dome:1.0

# confirm local ip
echo -e "\033[36m[INFO] Confirming local ip...\033[0m"
if [ -z "$LOCAL_IP" ]; then
    host_ips=(`ip addr show | grep inet | grep -v inet6 | grep brd | awk '{print $2}' | cut -f1 -d '/'`)
    if [ "$host_ips" == "" ]; then
      echo -e "\033[31m[ERROR] Get host ip address error\033[0m"
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
    if [ "$host_ip" == "" ]; then
      host_ip=${host_ips[0]}
    fi
    LOCAL_IP=$host_ip
    echo -e "\033[36m[INFO] Local IP address: $LOCAL_IP\033[0m"
fi
if [ -z "LOCAL_IP" ]; then
        echo -e "\033[31m[ERROR] LOCAL_IP must be set, we cannot get this parameter from your linux system.\033[0m"
        exit 1;
fi

# confirm docker setting
docker_version=(`docker version | grep Version | awk '{print $2}'`)
if [ -z "$docker_version" ]; then
    echo -e "\033[31m[ERROR] Get docker version error, your docker must be 1.8.2 at minimum\033[0m"
    exit 1
fi
docker_version_invalid="false"
for i in ${docker_version[@]}; do
  version_parts=(${i//./ })
  if [ ${version_parts[0]} -lt 1 ]; then
    docker_version_invalid="true"
    break
  fi
  if [ ${version_parts[0]} -eq 1 ] && [ ${version_parts[1]} -lt 8 ]; then
    docker_version_invalid="true"
    break
  fi
  if [ ${version_parts[0]} -eq 1 ] && [ ${version_parts[1]} -eq 8 ] && [ ${version_parts[2]} -lt 2 ]; then
    docker_version_invalid="true"
    break
  fi
done
if [ $docker_version_invalid == "true" ]; then
  echo -e "\033[31m[ERROR] Docker server and client version must be 1.8.2 at minimum, current version is $i\033[0m"
  exit 1
fi
echo -e "\033[32m[OK] Check docker server and client version OK, current version is ${docker_version[0]}\033[0m"

# clear iptables
echo -e "\033[36m[INFO] clear iptalbes: \033[0m"
iptables -F
if [ $? -ne 0 ]; then
   echo -e "\033[31m[ERROR] clear iptables failed! please try 'iptables -F'\033[0m";
   exit 1;
fi
echo -e "\033[32m[OK] clear iptables success.\033[0m"

# query /etc/reslove.conf
NAME_SERVER=`cat /etc/resolv.conf | grep nameserver | head -n 1 | awk '{print $2}'`
NAME_SERVER=${NAME_SERVER}:53
echo -e "\033[36m[INFO] NAME_SERVER=${NAME_SERVER}\033[0m"

pull_image ${IMAGE_MYSQL}
pull_image ${IMAGE_K8S}
pull_image ${IMAGE_OPENFALCON}
pull_image ${IMAGE_SERVER}

# start mysql
echo -e "\033[36m[INFO] Confirming mysql setting..."
check_container ${DOMEOS_PREFIX}_mysql
if [ $? = 1 ]; then
    docker run --restart=on-failure:3 --name=${DOMEOS_PREFIX}_mysql -p ${MYSQL_PORT}:3306 -e MYSQL_USER=${MYSQL_USER} -e MYSQL_PASSWORD=${MYSQL_PASSWORD} -e MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} -e LOCAL_IP=${LOCAL_IP} -e DOMEOS_PREFIX=${DOMEOS_PREFIX} -e KUBE_PORT=${KUBE_PORT} -e DOMEOS_PORT=${DOMEOS_PORT} -d ${IMAGE_MYSQL}
    if [ $? -ne 0 ]; then
        docker rm -f ${DOMEOS_PREFIX}_mysql &>/dev/null
        echo -e "\033[31m[ERROR] MySQL start failed!\033[0m";
        exit 1;
    fi
    echo -e "\033[36m[INFO] Waiting 30s for mysql to setup...\033[0m"
    echo -e "\033[36m[INFO] This is because mysql container could not be used immediately after started. It is related to your system. We think 30s is enough.\033[0m"
    sleep 30
fi

# confirm k8s
echo -e "\033[36m[INFO] Confirming k8s master setting...\033[0m"

check_container ${DOMEOS_PREFIX}_k8s
if [ $? = 1 ]; then
    docker run --restart=on-failure:3 --name=${DOMEOS_PREFIX}_k8s -d --net=host -e LOCAL_IP=${LOCAL_IP} -e SERVICE_IP_RANGE=${SERVICE_IP_RANGE} -e KUBE_PORT=${KUBE_PORT} -e DOMEOS_PREFIX=${DOMEOS_PREFIX} -e NAME_SERVER=${NAME_SERVER} ${IMAGE_K8S}
    if [ $? -ne 0 ]; then
        echo -e "\033[31m[ERROR] k8s master start failed!\033[0m";
        exit 1;
    fi
    sleep 10
fi

# check etcd server
RESULT=`curl -L ${LOCAL_IP}:2379/health`
if ! [[ $RESULT =~ "true" ]]; then
    echo -e "\033[31m[ERROR] Etcd not ready, please check docker logs ${DOMEOS_PREFIX}_k8s or curl -L ${LOCAL_IP}:2379/health\033[0m"
    exit 1;
else
    echo -e "\033[32m[OK] K8S start success!\033[0m"
fi

sleep 3

# add etcd network info into etcd
echo -e "\033[36m[INFO] Adding network info into etcd...\033[0m"
flannel_command="{\"Network\": \"${POD_IP_RANGE}\",\"SubnetLen\": ${SUBNETLEN},\"Backend\": {\"Type\": \"vxlan\", \"VNI\": 1 }}"
curl -L ${LOCAL_IP}:2379/v2/keys/flannel/network/config -XPUT -d value="${flannel_command}" &> /dev/null
echo -e "\033[32m[OK] add success."

# comfirm open-falcon components
echo -e "\033[36m[INFO] Confirming open-falcon components...\033[0m"
check_container ${DOMEOS_PREFIX}_openfalcon
if [ $? = 1 ]; then
    docker run --restart=on-failure:3 --name=${DOMEOS_PREFIX}_openfalcon \
    --net=host \
    -e DB_DATABASE="\"${MYSQL_USER}:${MYSQL_PASSWORD}@tcp(${LOCAL_IP}:${MYSQL_PORT})/graph?loc=Local&parseTime=true\"" \
    -d ${IMAGE_OPENFALCON}
fi


# confirm domeos server
echo -e "\033[36m[INFO] Comfirming domeos server...\033[0m"
check_container ${DOMEOS_PREFIX}_server
if [ $? = 1 ]; then
    docker run --restart=on-failure:3 -d --name=${DOMEOS_PREFIX}_server \
    -p ${DOMEOS_PORT}:8080 \
    -e MYSQL_HOST=${LOCAL_IP} \
    -e MYSQL_PORT=${MYSQL_PORT} \
    -e MYSQL_USERNAME=${MYSQL_USER} \
    -e MYSQL_PASSWORD=${MYSQL_PASSWORD} \
    -e MYSQL_DB="domeos" \
    ${IMAGE_SERVER}

    if [ $? -ne 0 ];then
        echo -e "\033[31m[ERROR] Server start failed! Please check docker logs ${DOMEOS_PREFIX}_server for reason.\033[0m"
        exit 1;
    fi
fi

iptables -P FORWARD ACCEPT
sleep 10

echo -e "\033[32m[OK] DomeOS start successfully, please use browser to visit http://${LOCAL_IP}:${DOMEOS_PORT}\033[0m"

