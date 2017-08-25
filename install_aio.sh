#!/bin/bash
printf "\nStarting Installation. The script takes long to complete, be patient!\n"
printf "See the full log at /tmp/crystal_aio.log\n\n"

#########  PASSWORDS  #########
MYSQL_PASSWD=root
RABBITMQ_PASSWD=openstack
KEYSTONE_ADMIN_PASSWD=keystone
MANAGER_PASSWD=manager
###############################

echo controller > /etc/hostname
echo -e "127.0.0.1 \t localhost" > /etc/hosts
IP_ADRESS=$(hostname -I | tr -d '[:space:]')
echo -e "$IP_ADRESS \t controller" >> /etc/hosts

###### Install Common ######
printf "Upgrading Server System\t\t ... \t2%%"
apt-get install software-properties-common -y >> /tmp/crystal_aio.log 2>&1
add-apt-repository cloud-archive:pike -y >> /tmp/crystal_aio.log 2>&1
apt-get update >> /tmp/crystal_aio.log
# apt dist-upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade >> /tmp/crystal_aio.log 2>&1
unset DEBIAN_FRONTEND
apt-get install python-openstackclient -y >> /tmp/crystal_aio.log 2>&1
printf "\tDone!\n"

###### Install Memcahce ######
printf "Installing Memcahce Server\t ... \t4%%"
apt-get install memcached python-memcache -y >> /tmp/crystal_aio.log 2>&1
sed -i '/-l 127.0.0.1/c\-l controller' /etc/memcached.conf
service memcached restart >> /tmp/crystal_aio.log 2>&1
printf "\tDone!\n"

###### Install RabbitMQ ######
printf "Installing RabbitMQ Server\t ... \t6%%"
apt-get install rabbitmq-server -y >> /tmp/crystal_aio.log 2>&1
rabbitmqctl add_user openstack $RABBITMQ_PASSWD >> /tmp/crystal_aio.log 2>&1
rabbitmqctl set_user_tags openstack administrator >> /tmp/crystal_aio.log 2>&1
rabbitmqctl set_permissions openstack ".*" ".*" ".*" >> /tmp/crystal_aio.log 2>&1
rabbitmq-plugins enable rabbitmq_management >> /tmp/crystal_aio.log 2>&1
printf "\tDone!\n"

###### Install MySQL ######
printf "Installing MySQL Server\t\t ... \t8%%"
export DEBIAN_FRONTEND=noninteractive
sudo debconf-set-selections <<< 'mariadb-server-10.0 mysql-server/root_password password $MYSQL_PASSWD'
sudo debconf-set-selections <<< 'mariadb-server-10.0 mysql-server/root_password_again password $MYSQL_PASSWD'
apt-get install mariadb-server python-pymysql -y >> /tmp/crystal_aio.log 2>&1
unset DEBIAN_FRONTEND

mysql -uroot -p$MYSQL_PASSWD -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')" >> /tmp/crystal_aio.log 2>&1
mysql -uroot -p$MYSQL_PASSWD -e "DELETE FROM mysql.user WHERE User=''" >> /tmp/crystal_aio.log 2>&1
mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE test" >> /tmp/crystal_aio.log 2>&1
mysql -uroot -p$MYSQL_PASSWD -e "FLUSH PRIVILEGES" >> /tmp/crystal_aio.log 2>&1

cat << EOF >> /etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = 0.0.0.0
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF

service mysql restart >> /tmp/crystal_aio.log 2>&1
printf "\tDone!\n"

###### Install Keystone ######
printf "Installing OpenStack Keystone\t ... \t10%%"
mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE keystone" >> /tmp/crystal_aio.log 2>&1
mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'keystone'" >> /tmp/crystal_aio.log 2>&1
mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'keystone'" >> /tmp/crystal_aio.log 2>&1

apt-get install keystone -y >> /tmp/crystal_aio.log 2>&1

sed -i '/connection =/c\connection = mysql+pymysql://keystone:keystone@controller/keystone' /etc/keystone/keystone.conf
sed -i '/#provider = fernet/c\provider = fernet' /etc/keystone/keystone.conf

su -s /bin/sh -c "keystone-manage db_sync" keystone >> /tmp/crystal_aio.log 2>&1
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone >> /tmp/crystal_aio.log 2>&1
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone >> /tmp/crystal_aio.log 2>&1
keystone-manage bootstrap --bootstrap-password $KEYSTONE_ADMIN_PASSWD --bootstrap-admin-url http://controller:35357/v3/ --bootstrap-internal-url http://controller:5000/v3/ --bootstrap-public-url http://controller:5000/v3/ --bootstrap-region-id RegionOne >> /tmp/crystal_aio.log 2>&1

echo "ServerName controller" >> /etc/apache2/apache2.conf
service apache2 restart >> /tmp/crystal_aio.log 2>&1
rm -f /var/lib/keystone/keystone.db >> /tmp/crystal_aio.log 2>&1

cat << EOF >> admin-openrc
export OS_USERNAME=admin
export OS_PASSWORD=$KEYSTONE_ADMIN_PASSWD
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:35357/v3
export OS_IDENTITY_API_VERSION=3
EOF

source admin-openrc
openstack role create user >> /tmp/crystal_aio.log 2>&1
openstack project create --domain default --description "Service Project" service >> /tmp/crystal_aio.log 2>&1
openstack project create --domain default --description "Management Project" management >> /tmp/crystal_aio.log 2>&1
openstack user create --domain default --password $MANAGER_PASSWD manager >> /tmp/crystal_aio.log 2>&1
openstack role add --project management --user manager admin >> /tmp/crystal_aio.log 2>&1

cat << EOF >> manager-openrc
export OS_USERNAME=manager
export OS_PASSWORD=$MANAGER_PASSWD
export OS_PROJECT_NAME=management
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
EOF

# create Crystal tenant and user
openstack project create --domain default --description "Crystal Test Project" crystal >> /tmp/crystal_aio.log 2>&1
openstack user create --domain default --password crystal crystal >> /tmp/crystal_aio.log 2>&1
openstack role add --project crystal --user crystal admin >> /tmp/crystal_aio.log 2>&1
openstack role add --project crystal --user manager admin >> /tmp/crystal_aio.log 2>&1

cat << EOF >> crystal-openrc
export OS_USERNAME=crystal
export OS_PASSWORD=crystal
export OS_PROJECT_NAME=crystal
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
EOF
printf "\tDone!\n"

###### Install Swift ######
printf "Installing OpenStack Swift\t ... \t20%%"
source admin-openrc
openstack user create --domain default --password swift swift >> /tmp/crystal_aio.log 2>&1
openstack role add --project service --user swift admin >> /tmp/crystal_aio.log 2>&1
openstack service create --name swift --description "OpenStack Object Storage" object-store >> /tmp/crystal_aio.log 2>&1

openstack endpoint create --region RegionOne object-store public http://controller:8080/v1/AUTH_%\(tenant_id\)s >> /tmp/crystal_aio.log 2>&1
openstack endpoint create --region RegionOne object-store internal http://controller:8080/v1/AUTH_%\(tenant_id\)s >> /tmp/crystal_aio.log 2>&1
openstack endpoint create --region RegionOne object-store admin http://controller:8080/v1 >> /tmp/crystal_aio.log 2>&1

apt-get install swift swift-proxy python-swiftclient python-keystoneclient python-keystonemiddleware memcached -y >> /tmp/crystal_aio.log 2>&1
apt-get install xfsprogs rsync -y >> /tmp/crystal_aio.log 2>&1
apt-get install swift swift-account swift-container swift-object -y >> /tmp/crystal_aio.log 2>&1

mkdir /etc/swift >> /tmp/crystal_aio.log 2>&1
curl -o /etc/swift/proxy-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/proxy-server.conf-sample?h=stable/ocata >> /tmp/crystal_aio.log 2>&1
curl -o /etc/swift/account-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/account-server.conf-sample?h=stable/ocata >> /tmp/crystal_aio.log 2>&1
curl -o /etc/swift/container-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/container-server.conf-sample?h=stable/ocata >> /tmp/crystal_aio.log 2>&1
curl -o /etc/swift/object-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/object-server.conf-sample?h=stable/ocata >> /tmp/crystal_aio.log 2>&1
curl -o /etc/swift/swift.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/swift.conf-sample?h=stable/ocata >> /tmp/crystal_aio.log 2>&1

mkdir -p /srv/node/sda1 >> /tmp/crystal_aio.log 2>&1
mkdir -p /var/cache/swift >> /tmp/crystal_aio.log 2>&1
chown -R root:swift /var/cache/swift
chmod -R 775 /var/cache/swift
chown -R swift:swift /srv/node

cd /etc/swift
swift-ring-builder account.builder create 10 1 1 >> /tmp/crystal_aio.log 2>&1
swift-ring-builder account.builder add --region 1 --zone 1 --ip controller --port 6202 --device sda1 --weight 100 >> /tmp/crystal_aio.log 2>&1
swift-ring-builder account.builder >> /tmp/crystal_aio.log 2>&1
swift-ring-builder account.builder rebalance >> /tmp/crystal_aio.log 2>&1

swift-ring-builder container.builder create 10 1 1 >> /tmp/crystal_aio.log 2>&1
swift-ring-builder container.builder add --region 1 --zone 1 --ip controller --port 6201 --device sda1 --weight 100 >> /tmp/crystal_aio.log 2>&1
swift-ring-builder container.builder >> /tmp/crystal_aio.log 2>&1
swift-ring-builder container.builder rebalance >> /tmp/crystal_aio.log 2>&1

swift-ring-builder object.builder create 10 1 1 >> /tmp/crystal_aio.log 2>&1
swift-ring-builder object.builder add --region 1 --zone 1 --ip controller --port 6200 --device sda1 --weight 100 >> /tmp/crystal_aio.log 2>&1
swift-ring-builder object.builder >> /tmp/crystal_aio.log 2>&1
swift-ring-builder object.builder rebalance >> /tmp/crystal_aio.log 2>&1
cd ~

sed -i '/^pipeline =/ d' /etc/swift/proxy-server.conf
sed -i 's/#pipeline/pipeline/p' /etc/swift/proxy-server.conf
sed -i '/# account_autocreate = false/c\account_autocreate = True' /etc/swift/proxy-server.conf
sed -i '/# \[filter:authtoken]/c\[filter:authtoken]' /etc/swift/proxy-server.conf
sed -i '/# paste.filter_factory = keystonemiddleware.auth_token:filter_factory/c\paste.filter_factory = keystonemiddleware.auth_token:filter_factory' /etc/swift/proxy-server.conf
sed -i '/# auth_uri = http:\/\/keystonehost:5000/c\auth_uri = http://controller:5000' /etc/swift/proxy-server.conf
sed -i '/# auth_url = http:\/\/keystonehost:35357/c\auth_url = http://controller:35357' /etc/swift/proxy-server.conf
sed -i '/# auth_plugin = password/c\auth_type = password' /etc/swift/proxy-server.conf
sed -i '/# project_domain_id = default/c\project_domain_name = default' /etc/swift/proxy-server.conf
sed -i '/# user_domain_id = default/c\user_domain_name = default' /etc/swift/proxy-server.conf
sed -i '/# project_name = service/c\project_name = service' /etc/swift/proxy-server.conf
sed -i '/# username = swift/c\username = swift' /etc/swift/proxy-server.conf
sed -i '/# password = password/c\password = swift' /etc/swift/proxy-server.conf
sed -i '/# delay_auth_decision = False/c\delay_auth_decision = True \nmemcached_servers = controller:11211' /etc/swift/proxy-server.conf
sed -i '/# \[filter:keystoneauth]/c\[filter:keystoneauth]' /etc/swift/proxy-server.conf
sed -i '/# use = egg:swift#keystoneauth/c\use = egg:swift#keystoneauth' /etc/swift/proxy-server.conf
sed -i '/# operator_roles = admin, swiftoperator/c\operator_roles = admin, user' /etc/swift/proxy-server.conf
sed -i '/# memcache_servers = 127.0.0.1:11211/c\memcache_servers = controller:11211' /etc/swift/proxy-server.conf

sed -i '/# mount_check = true/c\mount_check = false' /etc/swift/account-server.conf
sed -i '/# mount_check = true/c\mount_check = false' /etc/swift/container-server.conf
sed -i '/# mount_check = true/c\mount_check = false' /etc/swift/object-server.conf

systemctl stop swift-account-auditor swift-account-reaper swift-account-replicator swift-container-auditor swift-container-replicator swift-container-sync swift-container-updater swift-object-auditor swift-object-reconstructor swift-object-replicator swift-object-updater >> /tmp/crystal_aio.log 2>&1
systemctl disable swift-account-auditor swift-account-reaper swift-account-replicator swift-container-auditor swift-container-replicator swift-container-sync swift-container-updater swift-object-auditor swift-object-reconstructor swift-object-replicator swift-object-updater >> /tmp/crystal_aio.log 2>&1
swift-init all stop >> /tmp/crystal_aio.log 2>&1
#usermod -u 1010 swift
#groupmod -g 1010 swift
swift-init main restart >> /tmp/crystal_aio.log 2>&1
printf "\tDone!\n"

###### Horizon ######
printf "Installing OpenStack Horizon\t ... \t30%%"
apt-get install openstack-dashboard -y >> /tmp/crystal_aio.log 2>&1
cat << EOF >> /etc/openstack-dashboard/local_settings.py
OPENSTACK_API_VERSIONS = {
    "identity": 3,
}
EOF

sed -i '/OPENSTACK_HOST = "127.0.0.1"/c\OPENSTACK_HOST = "controller"' /etc/openstack-dashboard/local_settings.py
sed -i '/OPENSTACK_KEYSTONE_URL = "http:\/\/%s:5000\/v2.0" % OPENSTACK_HOST/c\OPENSTACK_KEYSTONE_URL = "http:\/\/%s:5000\/v3" % OPENSTACK_HOST' /etc/openstack-dashboard/local_settings.py
sed -i '/OPENSTACK_KEYSTONE_DEFAULT_ROLE = "_member_"/c\OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"' /etc/openstack-dashboard/local_settings.py

chown www-data:www-data -R /var/lib/openstack-dashboard/secret_key
service apache2 restart >> /tmp/crystal_aio.log 2>&1
printf "\tDone!\n"

#### Crystal Controller #####
printf "Installing Crystal Controller\t ... \t40%%"
apt-get install python-pip python-dev -y >> /tmp/crystal_aio.log 2>&1
pip install -U pip >> /tmp/crystal_aio.log 2>&1

apt-get install redis-server -y >> /tmp/crystal_aio.log 2>&1
sed -i '/bind 127.0.0.1/c\bind 0.0.0.0' /etc/redis/redis.conf
service redis restart >> /tmp/crystal_aio.log 2>&1

git clone https://github.com/Crystal-SDS/controller -b dev /usr/share/crystal-controller >> /tmp/crystal_aio.log 2>&1
pip install pyactor redis pika pytz eventlet djangorestframework django-bootstrap3 >> /tmp/crystal_aio.log 2>&1
cp /usr/share/crystal-controller/etc/apache2/sites-available/crystal_controller.conf /etc/apache2/sites-available/
a2ensite crystal_controller >> /tmp/crystal_aio.log 2>&1
service apache2 restart >> /tmp/crystal_aio.log 2>&1

mkdir /opt/crystal
mkdir /opt/crystal/global_controllers
printf "\tDone!\n"

#### Crystal Dashboard #####
printf "Installing Crystal Dashboard\t ... \t50%%"
git clone https://github.com/Crystal-SDS/dashboard /usr/share/crystal-dashboard >> /tmp/crystal_aio.log 2>&1
cp /usr/share/crystal-dashboard/crystal_dashboard/enabled/_50_sdscontroller.py /usr/share/openstack-dashboard/openstack_dashboard/enabled/
cat /usr/share/crystal-dashboard/crystal_dashboard/local/local_settings.py >>  /etc/openstack-dashboard/local_settings.py
pip install /usr/share/crystal-dashboard >> /tmp/crystal_aio.log 2>&1
service apache2 restart >> /tmp/crystal_aio.log 2>&1
printf "\tDone!\n"

#### Filter middleware #####
printf "Installing Filter Middleware\t ... \t60%%"
git clone https://github.com/Crystal-SDS/filter-middleware >> /tmp/crystal_aio.log 2>&1
pip install filter-middleware/ >> /tmp/crystal_aio.log 2>&1

cat << EOF >> /etc/swift/proxy-server.conf

[filter:crystal_filter_handler]
use = egg:swift_crystal_filter_middleware#crystal_filter_handler
os_identifier = proxy_controller
storlet_gateway_module = storlet_gateway.gateways.docker:StorletGatewayDocker
execution_server = proxy
EOF

cat << EOF >> /etc/swift/object-server.conf

[filter:crystal_filter_handler]
use = egg:swift_crystal_filter_middleware#crystal_filter_handler
os_identifier = object_controller
storlet_gateway_module = storlet_gateway.gateways.docker:StorletGatewayDocker
execution_server = object
EOF

mkdir /opt/crystal/global_native_filters
mkdir /opt/crystal/native_filters
mkdir /opt/crystal/storlet_filters
printf "\tDone!\n"

#### Metric middleware #####
printf "Installing Metric middleware\t ... \t70%%"
git clone https://github.com/Crystal-SDS/metric-middleware >> /tmp/crystal_aio.log 2>&1
pip install metric-middleware/ >> /tmp/crystal_aio.log 2>&1

cat << EOF >> /etc/swift/proxy-server.conf

[filter:crystal_metric_handler]
use = egg:swift_crystal_metric_middleware#crystal_metric_handler
execution_server = proxy
rabbit_username = openstack
rabbit_password = $RABBITMQ_PASSWD
EOF

cat << EOF >> /etc/swift/object-server.conf

[filter:crystal_metric_handler]
use = egg:swift_crystal_metric_middleware#crystal_metric_handler
execution_server = object
rabbit_username = openstack
rabbit_password = $RABBITMQ_PASSWD
EOF

sed -i '/^pipeline =/ d' /etc/swift/proxy-server.conf
sed  -i '/\[pipeline:main\]/a pipeline = catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk ratelimit authtoken keystoneauth container-quotas account-quotas crystal_metric_handler crystal_filter_handler slo dlo proxy-logging proxy-server' /etc/swift/proxy-server.conf

sed -i '/^pipeline =/ d' /etc/swift/object-server.conf
sed  -i '/\[pipeline:main\]/a pipeline = healthcheck recon crystal_metric_handler crystal_filter_handler object-server' /etc/swift/object-server.conf

swift-init main restart >> /tmp/crystal_aio.log 2>&1

mkdir /opt/crystal/workload_metrics
printf "\tDone!\n"

####   ELK Stack  ####
printf "Installing ELK stack\t\t ... \t80%%"
add-apt-repository -y ppa:webupd8team/java >> /tmp/crystal_aio.log 2>&1
apt-get update >> /tmp/crystal_aio.log 2>&1
#echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
#echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
#apt-get -y install oracle-java8-installer >> /tmp/crystal_aio.log 2>&1
apt-get -y install openjdk-8-jdk openjdk-8-jre >> /tmp/crystal_aio.log 2>&1

wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add - >> /tmp/crystal_aio.log 2>&1
echo "deb https://artifacts.elastic.co/packages/5.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-5.x.list >> /tmp/crystal_aio.log 2>&1
apt-get update >> /tmp/crystal_aio.log 2>&1
apt-get install -y elasticsearch logstash kibana metricbeat >> /tmp/crystal_aio.log 2>&1

sed -i '/#server.host: "localhost"/c\server.host: "0.0.0.0"' /etc/kibana/kibana.yml

cat << EOF >> /etc/logstash/conf.d/logstash.conf
input {
  udp{
    port => 5400
    codec => json
  }
}
output {
   elasticsearch {
       hosts => ["localhost:9200"]
   }
}
EOF

systemctl enable elasticsearch  >> /tmp/crystal_aio.log 2>&1
systemctl enable logstash >> /tmp/crystal_aio.log 2>&1
systemctl enable kibana >> /tmp/crystal_aio.log 2>&1
systemctl enable metricbeat >> /tmp/crystal_aio.log 2>&1

service elasticsearch restart >> /tmp/crystal_aio.log 2>&1
service logstash restart >> /tmp/crystal_aio.log 2>&1
service kibana restart >> /tmp/crystal_aio.log 2>&1
service metricbeat restart >> /tmp/crystal_aio.log 2>&1

printf "\tDone!\n"

##### Install Storlets #####
printf "Installing Storlets\t\t ... \t90%%"
# Install Docker
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D >> /tmp/crystal_aio.log 2>&1
apt-add-repository 'deb https://apt.dockerproject.org/repo ubuntu-xenial main' >> /tmp/crystal_aio.log 2>&1
apt-get update >> /tmp/crystal_aio.log 2>&1
apt-get install aufs-tools linux-image-generic-lts-xenial apt-transport-https docker-engine ansible ant -y >> /tmp/crystal_aio.log 2>&1

cat << EOF >> /etc/docker/daemon.json
{
"data-root": "/home/docker_device/docker"
}
EOF

service docker stop >> /tmp/crystal_aio.log 2>&1
service docker start >> /tmp/crystal_aio.log 2>&1

# Install Storlets
git clone https://github.com/openstack/storlets >> /tmp/crystal_aio.log 2>&1
pip install storlets/ >> /tmp/crystal_aio.log 2>&1
cd storlets
./install_libs.sh >> /tmp/crystal_aio.log 2>&1
mkdir /home/docker_device/scripts >> /tmp/crystal_aio.log 2>&1
chown swift:swift /home/docker_device/scripts >> /tmp/crystal_aio.log 2>&1
cp scripts/restart_docker_container /home/docker_device/scripts/ >> /tmp/crystal_aio.log 2>&1
cp scripts/send_halt_cmd_to_daemon_factory.py /home/docker_device/scripts/ >> /tmp/crystal_aio.log 2>&1
chown root:root /home/docker_device/scripts/* >> /tmp/crystal_aio.log 2>&1
chmod 04755 /home/docker_device/scripts/* >> /tmp/crystal_aio.log 2>&1

# Create Storlet docker runtime
usermod -aG docker $(whoami) >> /tmp/crystal_aio.log 2>&1
sed -i "/ansible-playbook \-s \-i deploy\/prepare_host prepare_storlets_install.yml/c\ansible-playbook \-s \-i deploy\/prepare_host prepare_storlets_install.yml --connection=local" install/storlets/prepare_storlets_install.sh >> /tmp/crystal_aio.log 2>&1
install/storlets/prepare_storlets_install.sh dev host >> /tmp/crystal_aio.log 2>&1

cd install/storlets/
SWIFT_UID=$(id -u swift)
SWIFT_GID=$(id -g swift)
sed -i '/- role: docker_client/c\  #- role: docker_client' docker_cluster.yml >> /tmp/crystal_aio.log 2>&1
sed -i '/"swift_user_id": "1003"/c\\t"swift_user_id": "'$SWIFT_UID'",' deploy/cluster_config.json >> /tmp/crystal_aio.log 2>&1
sed -i '/"swift_group_id": "1003"/c\\t"swift_group_id": "'$SWIFT_GID'",' deploy/cluster_config.json >> /tmp/crystal_aio.log 2>&1
ansible-playbook -s -i storlets_dynamic_inventory.py docker_cluster.yml --connection=local >> /tmp/crystal_aio.log 2>&1
docker rmi ubuntu_16.04_jre8 ubuntu:16.04 ubuntu_16.04 -f >> /tmp/crystal_aio.log 2>&1
printf "\tDone!\n"
cd ~

##### Initialize Crystal #####
printf "Initializating Crystal\t\t ... \t95%%"

# Initialize Crystal test tenant
. crystal-openrc >> /tmp/crystal_aio.log 2>&1
PROJECT_ID=$(openstack token issue | grep -w project_id | awk '{print $4}') >> /tmp/crystal_aio.log 2>&1
docker tag ubuntu_16.04_jre8_storlets ${PROJECT_ID:0:13} >> /tmp/crystal_aio.log 2>&1
swift post storlet >> /tmp/crystal_aio.log 2>&1
swift post dependency >> /tmp/crystal_aio.log 2>&1
swift post -H "X-account-meta-storlet-enabled:True" >> /tmp/crystal_aio.log 2>&1
swift post -H "X-account-meta-crystal-enabled:True" >> /tmp/crystal_aio.log 2>&1

# Load default dashboards to kibana
/usr/share/metricbeat/scripts/import_dashboards >> /tmp/crystal_aio.log 2>&1
echo -n '{"@timestamp":"2017-08-02T17:10:04.700Z","metric_name":"get_ops","host":"controller","@version":"1","metric_target":"management","value":0}' >/dev/udp/localhost/5400
curl -XPUT http://localhost:9200/.kibana/index-pattern/logstash-* -d '{"title" : "logstash-*",  "timeFieldName": "@timestamp"}' >> /tmp/crystal_aio.log 2>&1
KIBANA_VERSION=$(dpkg -s kibana | grep -i version | awk '{print $2}')
curl -XPUT http://localhost:9200/.kibana/config/$KIBANA_VERSION -d '{"defaultIndex" : "logstash-*"}' >> /tmp/crystal_aio.log 2>&1

# Load default data
cp controller/bandwidth_controller_samples/static_bandwidth.py /opt/crystal/global_controllers/
cp controller/bandwidth_controller_samples/static_replication_bandwidth.py /opt/crystal/global_controllers/

cp metric-middleware/metric_samples/container/* /opt/crystal/workload_metrics
cp metric-middleware/metric_samples/tenant/* /opt/crystal/workload_metrics

git clone https://github.com/Crystal-SDS/filter-samples
cp filter-samples/Native_bandwidth_differentiation/crystal_bandwidth_control.py /opt/crystal/global_native_filters/
cp filter-samples/Native_noop/crystal_noop_filter.py /opt/crystal/native_filters/
cp filter-samples/Native_cache/crystal_cache_control.py /opt/crystal/native_filters/

sudo service redis-server stop
wget https://raw.githubusercontent.com/Crystal-SDS/INSTALLATION/master/dump.rdb
mv dump.rdb /var/lib/redis/
chmod 655 /var/lib/redis/dump.rdb
chown redis:redis /var/lib/redis/dump.rdb
sudo service redis-server start

printf "\tDone!\n"

printf "Crystal AiO installation\t ... \t100%%\tCompleted!\n\n"
printf "Access to the Dashboard with the following URL: http://$IP_ADRESS/horizon\n"
printf "Log in with user: manager | password: $MANAGER_PASSWD\n\n"

