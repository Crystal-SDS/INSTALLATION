#!/bin/bash
###### Install Common ######
apt install software-properties-common -y
add-apt-repository cloud-archive:ocata -y
apt update && apt dist-upgrade -y
apt install python-openstackclient -y

###### Install Memcahce ######
apt install memcached python-memcache -y
sed -i '/-l 127.0.0.1/c\-l controller' /etc/memcached.conf
service memcached restart

###### Install RabbitMQ ######
apt install rabbitmq-server -y
rabbitmqctl add_user openstack openstack
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

###### Install MySQL ######
export DEBIAN_FRONTEND=noninteractive
sudo debconf-set-selections <<< 'mariadb-server-10.0 mysql-server/root_password password root'
sudo debconf-set-selections <<< 'mariadb-server-10.0 mysql-server/root_password_again password root'
apt install mariadb-server python-pymysql -y
unset DEBIAN_FRONTEND

mysql -uroot -proot -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
mysql -uroot -proot -e "DELETE FROM mysql.user WHERE User=''"
mysql -uroot -proot -e "DROP DATABASE test"
mysql -uroot -proot -e "FLUSH PRIVILEGES"

cat << EOF >> /etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = 0.0.0.0
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF

service mysql restart

###### Install Keystone ######
mysql -uroot -proot -e "CREATE DATABASE keystone"
mysql -uroot -proot -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'keystone'"
mysql -uroot -proot -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'keystone'"

apt install keystone -y

sed -i '/connection =/c\connection = mysql+pymysql://keystone:keystone@controller/keystone' /etc/keystone/keystone.conf
sed -i '/#provider = fernet/c\provider = fernet' /etc/keystone/keystone.conf

su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password keystone --bootstrap-admin-url http://controller:35357/v3/ --bootstrap-internal-url http://controller:5000/v3/ --bootstrap-public-url http://controller:5000/v3/ --bootstrap-region-id RegionOne

echo "ServerName controller" >> /etc/apache2/apache2.conf
service apache2 restart
rm -f /var/lib/keystone/keystone.db

cat << EOF >> admin-openrc
export OS_USERNAME=admin
export OS_PASSWORD=keystone
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:35357/v3
export OS_IDENTITY_API_VERSION=3
EOF

source admin-openrc
openstack role create user
openstack project create --domain default --description "Service Project" service
openstack project create --domain default --description "Management Project" management
openstack user create --domain default --password manager manager
openstack role add --project management --user manager admin

cat << EOF >> manager-openrc
export OS_USERNAME=manager
export OS_PASSWORD=manager
export OS_PROJECT_NAME=management
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
EOF

###### Install Swift ######
source admin-openrc
openstack user create --domain default --password swift swift
openstack role add --project service --user swift admin
openstack service create --name swift --description "OpenStack Object Storage" object-store

openstack endpoint create --region RegionOne object-store public http://controller:8080/v1/AUTH_%\(tenant_id\)s
openstack endpoint create --region RegionOne object-store internal http://controller:8080/v1/AUTH_%\(tenant_id\)s
openstack endpoint create --region RegionOne object-store admin http://controller:8080/v1

apt install swift swift-proxy python-swiftclient python-keystoneclient python-keystonemiddleware memcached -y
apt install xfsprogs rsync -y
apt install swift swift-account swift-container swift-object -y

mkdir /etc/swift
curl -o /etc/swift/proxy-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/proxy-server.conf-sample?h=stable/ocata
curl -o /etc/swift/account-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/account-server.conf-sample?h=stable/ocata
curl -o /etc/swift/container-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/container-server.conf-sample?h=stable/ocata
curl -o /etc/swift/object-server.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/object-server.conf-sample?h=stable/ocata
curl -o /etc/swift/swift.conf https://git.openstack.org/cgit/openstack/swift/plain/etc/swift.conf-sample?h=stable/ocata

mkdir -p /srv/node/sda1
mkdir -p /var/cache/swift
chown -R root:swift /var/cache/swift
chmod -R 775 /var/cache/swift
chown -R swift:swift /srv/node

cd /etc/swift
swift-ring-builder account.builder create 10 1 1
swift-ring-builder account.builder add --region 1 --zone 1 --ip controller --port 6202 --device sda1 --weight 100
swift-ring-builder account.builder
swift-ring-builder account.builder rebalance

swift-ring-builder container.builder create 10 1 1
swift-ring-builder container.builder add --region 1 --zone 1 --ip controller --port 6201 --device sda1 --weight 100
swift-ring-builder container.builder
swift-ring-builder container.builder rebalance

swift-ring-builder object.builder create 10 1 1
swift-ring-builder object.builder add --region 1 --zone 1 --ip controller --port 6200 --device sda1 --weight 100
swift-ring-builder object.builder
swift-ring-builder object.builder rebalance

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

systemctl stop swift-account-auditor swift-account-reaper swift-account-replicator swift-container-auditor swift-container-replicator swift-container-sync swift-container-updater swift-object-auditor swift-object-reconstructor swift-object-replicator swift-object-updater
systemctl disable swift-account-auditor swift-account-reaper swift-account-replicator swift-container-auditor swift-container-replicator swift-container-sync swift-container-updater swift-object-auditor swift-object-reconstructor swift-object-replicator swift-object-updater
swift-init all stop
swift-init main restart

###### Horizon ######
apt install openstack-dashboard -y
# EDIT /etc/openstack-dashboard/local_settings.py

cat << EOF >> /etc/openstack-dashboard/local_settings.py
OPENSTACK_API_VERSIONS = {
    "identity": 3,
}
EOF

sed -i '/OPENSTACK_HOST = "127.0.0.1"/c\OPENSTACK_HOST = "controller"' /etc/openstack-dashboard/local_settings.py
sed -i '/OPENSTACK_KEYSTONE_URL = "http:\/\/%s:5000\/v2.0" % OPENSTACK_HOST/c\OPENSTACK_KEYSTONE_URL = "http:\/\/%s:5000\/v3" % OPENSTACK_HOST' /etc/openstack-dashboard/local_settings.py
sed -i '/OPENSTACK_KEYSTONE_DEFAULT_ROLE = "_member_"/c\OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"' /etc/openstack-dashboard/local_settings.py

chown www-data:www-data -R /var/lib/openstack-dashboard/secret_key
chown www-data:www-data -R /usr/share/openstack-dashboard
service apache2 restart

###### Install Python Env ######
apt install python-pip python-dev -y
pip install -U pip