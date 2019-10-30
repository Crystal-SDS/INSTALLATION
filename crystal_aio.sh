#!/bin/bash

OPENSTACK_RELEASE=pike

#########  PASSWORDS  #########
MYSQL_PASSWD=root
RABBITMQ_PASSWD=openstack
KEYSTONE_ADMIN_PASSWD=keystone
CRYSTAL_MANAGER_PASSWD=manager
###############################

LOG=/tmp/crystal_aio_installation.log

###### Upgrade System ######
upgrade_system(){
	echo controller > /etc/hostname
	echo -e "127.0.0.1 \t localhost" > /etc/hosts
	IP_ADRESS=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
	echo -e "$IP_ADRESS \t controller" >> /etc/hosts
	#ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

	add-apt-repository universe
	apt-get install software-properties-common -y
	add-apt-repository cloud-archive:$OPENSTACK_RELEASE -y
	apt-get update

	DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade
	unset DEBIAN_FRONTEND
	apt-get install python-openstackclient python-pip python-dev sshpass libssl-dev -y
}


###### Install Memcached ######
install_memcache_server(){
	apt-get install memcached python-memcache -y
	sed -i '/-l 127.0.0.1/c\-l controller' /etc/memcached.conf
	service memcached restart
}


###### Install RabbitMQ ######
install_rabbitmq_server(){
	apt-get install rabbitmq-server -y
	rabbitmqctl add_user openstack $RABBITMQ_PASSWD
	rabbitmqctl set_user_tags openstack administrator
	rabbitmqctl set_permissions openstack ".*" ".*" ".*"
	rabbitmq-plugins enable rabbitmq_management
}


###### Install MySQL ######
install_mysql_server(){

	export DEBIAN_FRONTEND=noninteractive
	debconf-set-selections <<< "mariadb-server-10.0 mysql-server/root_password password $MYSQL_PASSWD"
	debconf-set-selections <<< "mariadb-server-10.0 mysql-server/root_password_again password $MYSQL_PASSWD"
	apt-get install mariadb-server python-pymysql -y
	unset DEBIAN_FRONTEND
	
	mysql -uroot -p$MYSQL_PASSWD -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
	mysql -uroot -p$MYSQL_PASSWD -e "DELETE FROM mysql.user WHERE User=''"
	mysql -uroot -p$MYSQL_PASSWD -e "DROP DATABASE test"
	mysql -uroot -p$MYSQL_PASSWD -e "FLUSH PRIVILEGES"
	
	cat <<-EOF >> /etc/mysql/mariadb.conf.d/99-openstack.cnf
	[mysqld]
	bind-address = 0.0.0.0
	default-storage-engine = innodb
	innodb_file_per_table = on
	max_connections = 4096
	collation-server = utf8_general_ci
	character-set-server = utf8
	EOF
	
	service mysql restart
}


###### Install Keystone ######
install_openstack_keystone(){
	mysql -uroot -p$MYSQL_PASSWD -e "CREATE DATABASE keystone"
	mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'keystone'"
	mysql -uroot -p$MYSQL_PASSWD -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'keystone'"
	
	apt-get install keystone apache2 libapache2-mod-wsgi python-keystoneclient python-keystonemiddleware -y
	
	sed -i '/connection =/c\connection = mysql+pymysql://keystone:keystone@controller/keystone' /etc/keystone/keystone.conf
	sed -i '/#provider = fernet/c\provider = fernet' /etc/keystone/keystone.conf
	
	
	su -s /bin/sh -c "keystone-manage db_sync" keystone
	keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
	keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
	keystone-manage bootstrap --bootstrap-password $KEYSTONE_ADMIN_PASSWD --bootstrap-admin-url http://controller:35357/v3/ --bootstrap-internal-url http://controller:5000/v3/ --bootstrap-public-url http://controller:5000/v3/ --bootstrap-region-id RegionOne
	
	echo "ServerName controller" >> /etc/apache2/apache2.conf
	rm -f /var/lib/keystone/keystone.db
	service apache2 restart
		
	cat <<-EOF >> admin-openrc
	export OS_USERNAME=admin
	export OS_PASSWORD=$KEYSTONE_ADMIN_PASSWD
	export OS_PROJECT_NAME=admin
	export OS_USER_DOMAIN_NAME=Default
	export OS_PROJECT_DOMAIN_NAME=Default
	export OS_AUTH_URL=http://controller:35357/v3
	export OS_IDENTITY_API_VERSION=3
	EOF
	
	source admin-openrc
	openstack role create user
	openstack role create ResellerAdmin
	openstack project create --domain default --description "Service Project" service
	openstack project create --domain default --description "Management Project" management
	openstack user create --domain default --password $CRYSTAL_MANAGER_PASSWD manager
	openstack role add --project management --user manager admin
	openstack role add --project management --user manager ResellerAdmin
	openstack role add --domain default --user manager ResellerAdmin
	
	cat <<-EOF >> manager-openrc
	export OS_USERNAME=manager
	export OS_PASSWORD=$CRYSTAL_MANAGER_PASSWD
	export OS_PROJECT_NAME=management
	export OS_USER_DOMAIN_NAME=Default
	export OS_PROJECT_DOMAIN_NAME=Default
	export OS_AUTH_URL=http://controller:5000/v3
	export OS_IDENTITY_API_VERSION=3
	EOF
	
	# create Crystal tenant and user
	openstack project create --domain default --description "Crystal Test Project" crystal
	openstack user create --domain default --password crystal crystal
	#openstack role add --project crystal --user crystal user
	openstack role add --project crystal --user crystal admin
	openstack role add --project crystal --user crystal ResellerAdmin
	openstack role add --project crystal --user manager admin
	openstack role add --project crystal --user manager ResellerAdmin
	
	cat <<-EOF >> crystal-openrc
	export OS_USERNAME=crystal
	export OS_PASSWORD=crystal
	export OS_PROJECT_NAME=crystal
	export OS_USER_DOMAIN_NAME=Default
	export OS_PROJECT_DOMAIN_NAME=Default
	export OS_AUTH_URL=http://controller:5000/v3
	export OS_IDENTITY_API_VERSION=3
	EOF
}

###### OpenStak Horizon ######
install_openstack_horizon() {
	apt-get install openstack-dashboard -y
	cat <<-EOF >> /etc/openstack-dashboard/local_settings.py
	
	OPENSTACK_API_VERSIONS = {
	    "identity": 3,
	}
	LANGUAGES = (
		('en', 'English'),
	)
	EOF
	
	sed -i '/OPENSTACK_HOST = "127.0.0.1"/c\OPENSTACK_HOST = "controller"' /etc/openstack-dashboard/local_settings.py
	sed -i '/OPENSTACK_KEYSTONE_URL = "http:\/\/%s:5000\/v2.0" % OPENSTACK_HOST/c\OPENSTACK_KEYSTONE_URL = "http:\/\/%s:5000\/v3" % OPENSTACK_HOST' /etc/openstack-dashboard/local_settings.py
	sed -i '/OPENSTACK_KEYSTONE_DEFAULT_ROLE = "_member_"/c\OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"' /etc/openstack-dashboard/local_settings.py
}

###### Install Swift ######
install_openstack_swift(){
	source admin-openrc
	openstack user create --domain default --password swift swift
	openstack role add --project service --user swift admin
	openstack service create --name swift --description "OpenStack Object Storage" object-store
	
	openstack endpoint create --region RegionOne object-store public http://controller:8080/v1/AUTH_%\(tenant_id\)s
	openstack endpoint create --region RegionOne object-store internal http://controller:8080/v1/AUTH_%\(tenant_id\)s
	openstack endpoint create --region RegionOne object-store admin http://controller:8080/v1
	
	apt-get install swift swift-proxy swift-account swift-container swift-object python-swiftclient -y
	#apt-get install python-keystoneclient python-keystonemiddleware memcached -y
	apt-get install xfsprogs rsync -y
	
	mkdir /etc/swift
	curl -o /etc/swift/proxy-server.conf https://opendev.org/openstack/swift/raw/branch/stable/$OPENSTACK_RELEASE/etc/proxy-server.conf-sample
	curl -o /etc/swift/account-server.conf https://opendev.org/openstack/swift/raw/branch/stable/$OPENSTACK_RELEASE/etc/account-server.conf-sample
	curl -o /etc/swift/container-server.conf https://opendev.org/openstack/swift/raw/branch/stable/$OPENSTACK_RELEASE/etc/container-server.conf-sample
	curl -o /etc/swift/object-server.conf https://opendev.org/openstack/swift/raw/branch/stable/$OPENSTACK_RELEASE/etc/object-server.conf-sample
	curl -o /etc/swift/swift.conf https://opendev.org/openstack/swift/raw/branch/stable/$OPENSTACK_RELEASE/etc/swift.conf-sample
	
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
	sed -i '/# password = password/c\password = swift \nservice_token_roles_required = True' /etc/swift/proxy-server.conf
	sed -i '/# delay_auth_decision = False/c\delay_auth_decision = True \nmemcached_servers = controller:11211' /etc/swift/proxy-server.conf
	sed -i '/# \[filter:keystoneauth]/c\[filter:keystoneauth]' /etc/swift/proxy-server.conf
	sed -i '/# use = egg:swift#keystoneauth/c\use = egg:swift#keystoneauth' /etc/swift/proxy-server.conf
	sed -i '/# operator_roles = admin, swiftoperator/c\operator_roles = admin, swiftoperator' /etc/swift/proxy-server.conf
	sed -i '/# memcache_servers = 127.0.0.1:11211/c\memcache_servers = controller:11211' /etc/swift/proxy-server.conf
	
	sed -i '/# mount_check = true/c\mount_check = false' /etc/swift/account-server.conf
	sed -i '/# mount_check = true/c\mount_check = false' /etc/swift/container-server.conf
	sed -i '/# mount_check = true/c\mount_check = false' /etc/swift/object-server.conf
	
	sed -i '/# workers = auto/c\workers = 1' /etc/swift/proxy-server.conf
	sed -i '/# workers = auto/c\workers = 1' /etc/swift/object-server.conf
	
	sed -i '/name = Policy-0/c\name = AiO' /etc/swift/swift.conf
	
	systemctl stop swift-account-auditor swift-account-reaper swift-account-replicator swift-container-auditor swift-container-replicator swift-container-sync swift-container-updater swift-object-auditor swift-object-reconstructor swift-object-replicator swift-object-updater
	systemctl disable swift-account-auditor swift-account-reaper swift-account-replicator swift-container-auditor swift-container-replicator swift-container-sync swift-container-updater swift-object-auditor swift-object-reconstructor swift-object-replicator swift-object-updater
	swift-init all stop
	#usermod -u 1010 swift
	#groupmod -g 1010 swift
	current_user=`who am i | awk '{print $1}'`
	chown -R $current_user:$current_user /etc/swift
	
}

##### Install Storlets #####
install_storlets(){
	# Install Java
	add-apt-repository -y ppa:webupd8team/java
	apt-get update
	apt-get install openjdk-8-jdk openjdk-8-jre -y

	# Install Docker
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable"
	apt-get update
	apt-get install aufs-tools linux-image-generic apt-transport-https docker-ce ansible ant -y
	
	cat <<-EOF >> /etc/docker/daemon.json
	{
	"data-root": "/home/docker_device/docker"
	}
	EOF
	
	mkdir /home/docker_device
	chmod 777 /home/docker_device
	service docker stop
	service docker start
	
	# Install Storlets
	git clone https://github.com/openstack/storlets -b stable/$OPENSTACK_RELEASE
	pip install storlets/
	cd storlets
	./install_libs.sh
	
	# Install host-side scripts
	mkdir /home/docker_device/scripts
	chown swift:swift /home/docker_device/scripts
	cp scripts/restart_docker_container /home/docker_device/scripts/
	cp scripts/send_halt_cmd_to_daemon_factory.py /home/docker_device/scripts/
	chown root:root /home/docker_device/scripts/*
	chmod 04755 /home/docker_device/scripts/*
	
	# Create Storlet docker runtime
	current_user=`who am i | awk '{print $1}'`
	usermod -aG docker $current_user
	sed -i "/ansible-playbook \-s \-i deploy\/prepare_host prepare_storlets_install.yml/c\ansible-playbook \-s \-i deploy\/prepare_host prepare_storlets_install.yml --connection=local" install/storlets/prepare_storlets_install.sh
	install/storlets/prepare_storlets_install.sh dev host

	cd install/storlets/
	SWIFT_UID=$(id -u swift)
	SWIFT_GID=$(id -g swift)
	sed -i '/- role: docker_client/c\  #- role: docker_client' docker_cluster.yml
	sed -i '/- role: docker_base_jre_image/c\  #- role: docker_base_jre_image' docker_cluster.yml
	sed -i '/"swift_user_id": "1003"/c\\t"swift_user_id": "'$SWIFT_UID'",' deploy/cluster_config.json
	sed -i '/"swift_group_id": "1003"/c\\t"swift_group_id": "'$SWIFT_GID'",' deploy/cluster_config.json
	sed -i '/ - http:\/\/www.slf4j.org\/dist\/slf4j-1.7.7.tar.gz/c\    - https://src.fedoraproject.org/lookaside/extras/slf4j/slf4j-1.7.7.tar.gz/e3f7ab85c0efa2248228baccb4f64442/slf4j-1.7.7.tar.gz' roles/docker_base_jre_image/tasks/ubuntu_16.04_jre8.yml
	sed -i '/ - http:\/\/logback.qos.ch\/dist\/logback-1.1.2.tar.gz/c\    - https://src.fedoraproject.org/lookaside/extras/logback/logback-1.1.2.tar.gz/f23e3b9151d4d9d61aeb49b0288a1a8e/logback-1.1.2.tar.gz' roles/docker_base_jre_image/tasks/ubuntu_16.04_jre8.yml
	
	docker pull jsampe/ubuntu_16.04_jre8
	docker tag jsampe/ubuntu_16.04_jre8 ubuntu_16.04_jre8
	ansible-playbook -s -i storlets_dynamic_inventory.py docker_cluster.yml --connection=local
	docker rmi jsampe/ubuntu_16.04_jre8 ubuntu_16.04_jre8 ubuntu:16.04 -f
	cd ~
	
	cat <<-EOF >> /etc/swift/storlet_docker_gateway.conf
	[DEFAULT]
	lxc_root = /home/docker_device/scopes
	cache_dir = /home/docker_device/cache/scopes
	log_dir = /home/docker_device/logs/scopes
	script_dir = /home/docker_device/scripts
	storlets_dir = /home/docker_device/storlets/scopes
	pipes_dir = /home/docker_device/pipes/scopes
	docker_repo = 
	restart_linux_container_timeout = 8
	storlet_timeout = 40
	EOF
	
	cp /etc/swift/proxy-server.conf /etc/swift/storlet-proxy-server.conf
	sed -i '/^pipeline =/ d' /etc/swift/storlet-proxy-server.conf
	sed -i '/\[pipeline:main\]/a pipeline = proxy-logging cache slo proxy-logging proxy-server' /etc/swift/storlet-proxy-server.conf
	rm -r storlets
}

####   ELK Stack  ####
install_elk(){	
	wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
	echo "deb https://artifacts.elastic.co/packages/5.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-5.x.list
	apt-get update
	apt-get install elasticsearch logstash kibana metricbeat -y
	
	sed -i '/#server.host: "localhost"/c\server.host: "0.0.0.0"' /etc/kibana/kibana.yml
	sed -i '/#logging.dest: stdout/c\logging.dest: /var/log/kibana/kibana.log' /etc/kibana/kibana.yml
	
	cat <<-EOF >> /etc/logstash/conf.d/logstash.conf
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
	
	mkdir /var/log/kibana
	chown kibana:kibana /var/log/kibana
	
	systemctl enable elasticsearch 
	systemctl enable logstash
	systemctl enable kibana
	systemctl enable metricbeat
	
	service elasticsearch restart
	service logstash restart
	service kibana restart
	service metricbeat restart
	
}

#### Crystal Controller #####
install_crystal_controller() {	
	apt-get install redis-server -y
	sed -i '/bind 127.0.0.1/c\bind 0.0.0.0' /etc/redis/redis.conf
	service redis restart
	
	git clone https://github.com/Crystal-SDS/controller /usr/share/crystal-controller
	pip install -r /usr/share/crystal-controller/requirements.txt
	cp /usr/share/crystal-controller/etc/apache2/sites-available/crystal_controller.conf /etc/apache2/sites-available/
	a2ensite crystal_controller
	
	mkdir /opt/crystal
	mkdir -p /opt/crystal/controllers
	mkdir -p /opt/crystal/swift/tmp
	mkdir -p /opt/crystal/swift/deploy
}

#### Crystal Dashboard #####
install_crystal_dashboard() {
	git clone https://github.com/Crystal-SDS/dashboard
	cp dashboard/crystal_dashboard/enabled/_50_sdscontroller.py /usr/share/openstack-dashboard/openstack_dashboard/enabled/
	cat dashboard/crystal_dashboard/local/local_settings.py >> /etc/openstack-dashboard/local_settings.py
	pip install dashboard/
	
	rm -r dashboard
}

#### ACL middleware #####
install_crystal_acl_middleware(){
	git clone https://github.com/Crystal-SDS/acl-middleware
	pip install acl-middleware/
	
	cat <<-EOF >> /etc/swift/proxy-server.conf
	
	[filter:crystal_acl]
	use = egg:swift_crystal_acl_middleware#crystal_acl
	EOF
	
	rm -r acl-middleware
}

#### Filter middleware #####
install_crystal_filter_middleware(){
	git clone https://github.com/Crystal-SDS/filter-middleware
	pip install filter-middleware/
	
	cat <<-EOF >> /etc/swift/proxy-server.conf
	
	[filter:crystal_filters]
	use = egg:swift_crystal_filter_middleware#crystal_filter_handler
	storlet_container = .storlet
	storlet_dependency = .dependency
	storlet_logcontainer = storletlog
	storlet_execute_on_proxy_only = false
	storlet_gateway_module = docker
	storlet_gateway_conf = /etc/swift/storlet_docker_gateway.conf
	execution_server = proxy
	EOF
	
	cat <<-EOF >> /etc/swift/object-server.conf
	
	[filter:crystal_filters]
	use = egg:swift_crystal_filter_middleware#crystal_filter_handler
	storlet_container = .storlet
	storlet_dependency = .dependency
	storlet_logcontainer = storletlog
	storlet_execute_on_proxy_only = false
	storlet_gateway_module = docker
	storlet_gateway_conf = /etc/swift/storlet_docker_gateway.conf
	execution_server = object
	EOF

	mkdir /opt/crystal/native_filters
	mkdir /opt/crystal/storlet_filters
	rm -r filter-middleware
}


#### Metric middleware #####
install_crystal_metric_middleware(){
	git clone https://github.com/Crystal-SDS/metric-middleware
	pip install metric-middleware/
	
	cat <<-EOF >> /etc/swift/proxy-server.conf
	
	[filter:crystal_metrics]
	use = egg:swift_crystal_metric_middleware#crystal_metric_handler
	execution_server = proxy
	region_id = 1
	zone_id = 1
	rabbit_username = openstack
	rabbit_password = $RABBITMQ_PASSWD
	EOF
	
	cat <<-EOF >> /etc/swift/object-server.conf
	
	[filter:crystal_metrics]
	use = egg:swift_crystal_metric_middleware#crystal_metric_handler
	execution_server = object
	region_id = 1
	zone_id = 1
	rabbit_username = openstack
	rabbit_password = $RABBITMQ_PASSWD
	EOF
	
	mkdir /opt/crystal/workload_metrics
	cp metric-middleware/metric_samples/* /opt/crystal/workload_metrics
	rm -r metric-middleware
}

##### Initialize Crystal #####
initialize_crystal(){
	# Activate Middlewares
	sed -i '/^pipeline =/ d' /etc/swift/proxy-server.conf
	sed -i '/\[pipeline:main\]/a pipeline = catch_errors gatekeeper healthcheck proxy-logging cache container_sync bulk tempurl ratelimit authtoken crystal_acl keystoneauth copy container-quotas account-quotas crystal_metrics crystal_filters copy slo dlo versioned_writes proxy-logging proxy-server' /etc/swift/proxy-server.conf
	
	sed -i '/^pipeline =/ d' /etc/swift/object-server.conf
	sed -i '/\[pipeline:main\]/a pipeline = healthcheck recon crystal_metrics crystal_filters object-server' /etc/swift/object-server.conf
	swift-init main restart

	. crystal-openrc
	swift post .storlet
	swift post .dependency
	#swift post -r '*:manager' .storlet
	#swift post -w '*:manager' .storlet
	#swift post dependency
	#swift post -r '*:manager' .dependency
	#swift post -w '*:manager' .dependency
	swift post -H "X-account-meta-storlet-enabled:True"
	swift post -H "X-account-meta-crystal-enabled:True"

	# Create storlets runtime
	PROJECT_ID=$(openstack token issue | grep -w project_id | awk '{print $4}')
	docker tag ubuntu_16.04_jre8_storlets ${PROJECT_ID:0:13}
	
	# Load default dashboards to kibana
	/usr/share/metricbeat/scripts/import_dashboards
	echo -n '{"container": "crystal/data", "metric_name": "bandwidth", "@timestamp": "2017-09-15T18:00:18.331492+02:00", "value": 16.4375, "project": "crystal", "host": "controller", "method": "GET", "server_type": "proxy"}' >/dev/udp/localhost/5400
	curl -XPUT http://localhost:9200/.kibana/index-pattern/logstash-* -d '{"title" : "logstash-*",  "timeFieldName": "@timestamp"}'
	KIBANA_VERSION=$(dpkg -s kibana | grep -i version | awk '{print $2}')
	curl -XPUT http://localhost:9200/.kibana/config/$KIBANA_VERSION -d '{"defaultIndex" : "logstash-*"}'
	
	# Load default data
	cp /usr/share/crystal-controller/controller_samples/static_bandwidth.py /opt/crystal/controllers/
		
	git clone https://github.com/Crystal-SDS/filter-samples
	cp filter-samples/Native_bandwidth_differentiation/bandwidth_control_filter.py /opt/crystal/native_filters/
	cp filter-samples/Native_cache/caching_filter.py /opt/crystal/native_filters/
	cp filter-samples/Native_noop/noop_filter.py /opt/crystal/native_filters/
	cp filter-samples/Native_recycle_bin/recyclebin_filter.py /opt/crystal/native_filters/
	cp filter-samples/Native_tag/tagging_filter.py /opt/crystal/native_filters/
	cp filter-samples/Native_crypto/crypto_filter.py /opt/crystal/native_filters/
	
	cp filter-samples/Storlet_compression/bin/compress-1.0.jar /opt/crystal/storlet_filters/
	cp filter-samples/Storlet_crypto/bin/crypto-1.0.jar /opt/crystal/storlet_filters/
	cp filter-samples/Storlet_noop/bin/noop-1.0.jar /opt/crystal/storlet_filters/
	rm -r filter-samples
	
	chown -R www-data:www-data /opt/crystal
	
	service redis-server stop
	wget https://raw.githubusercontent.com/Crystal-SDS/INSTALLATION/master/dump.rdb
	mv dump.rdb /var/lib/redis/
	chmod 655 /var/lib/redis/dump.rdb
	chown redis:redis /var/lib/redis/dump.rdb
	service redis-server start
	
}


##### Restart Main Services #####
restart_services(){
	swift-init main restart
	service apache2 restart
}


install_crystal(){
	printf "\nStarting Installation. The script takes long to complete, be patient!\n"
	printf "See the full log at $LOG\n\n"
	
	printf "Upgrading Server System\t\t ... \t2%%"
	upgrade_system >> $LOG 2>&1; printf "\tDone!\n"
	
	printf "Installing Memcache Server\t ... \t4%%"
	install_memcache_server >> $LOG 2>&1; printf "\tDone!\n"
	printf "Installing RabbitMQ Server\t ... \t6%%"
	install_rabbitmq_server >> $LOG 2>&1; printf "\tDone!\n"
	printf "Installing MySQL Server\t\t ... \t8%%"
	install_mysql_server >> $LOG 2>&1; printf "\tDone!\n"
	
	printf "Installing OpenStack Keystone\t ... \t10%%"
	install_openstack_keystone >> $LOG 2>&1; printf "\tDone!\n"
	printf "Installing OpenStack Horizon\t ... \t20%%"
	install_openstack_horizon >> $LOG 2>&1; printf "\tDone!\n"
	printf "Installing OpenStack Swift\t ... \t30%%"
	install_openstack_swift >> $LOG 2>&1; printf "\tDone!\n"

	printf "Installing Storlets\t\t ... \t45%%"
	install_storlets >> $LOG 2>&1; printf "\tDone!\n"
	printf "Installing ELK stack\t\t ... \t60%%"
	install_elk >> $LOG 2>&1; printf "\tDone!\n"

	printf "Installing Crystal Controller\t ... \t70%%"
	install_crystal_controller >> $LOG 2>&1; printf "\tDone!\n"
	printf "Installing Crystal Dashboard\t ... \t75%%"
	install_crystal_dashboard >> $LOG 2>&1; printf "\tDone!\n"
	printf "Installing ACL Middleware\t ... \t80%%"
	install_crystal_acl_middleware >> $LOG 2>&1; printf "\tDone!\n"
	printf "Installing Filter Middleware\t ... \t85%%"
	install_crystal_filter_middleware >> $LOG 2>&1; printf "\tDone!\n"
	printf "Installing Metric middleware\t ... \t90%%"
	install_crystal_metric_middleware >> $LOG 2>&1; printf "\tDone!\n"
	printf "Initializing Crystal\t\t ... \t95%%"
	initialize_crystal >> $LOG 2>&1; printf "\tDone!\n"
	
	restart_services >> $LOG 2>&1;
	printf "Crystal AiO installation\t ... \t100%%\tCompleted!\n\n"
	printf "Access the Dashboard with the following URL: http://$IP_ADRESS/horizon\n"
	printf "Login with user: manager | password: $CRYSTAL_MANAGER_PASSWD\n\n"
}


update_crystal(){
	printf "\nUpdating Crystal Installation. The script takes long to complete, be patient!\n"
	printf "See the full log at $LOG\n\n"
	
	printf "Updating Crystal Controller\t ... \t10%%"
	install_crystal_controller >> $LOG 2>&1; printf "\tDone!\n"
	printf "Updating Crystal Dashboard\t ... \t30%%"
	install_crystal_dashboard >> $LOG 2>&1; printf "\tDone!\n"
	
	printf "Updating ACL Middleware\t ... \t50%%"
	git clone https://github.com/Crystal-SDS/acl-middleware  >> $LOG 2>&1;
	pip install acl-middleware/  >> $LOG 2>&1;
	rm -r acl-middleware  >> $LOG 2>&1;
	
	printf "Updating Filter Middleware\t ... \t75%%"
	git clone https://github.com/Crystal-SDS/filter-middleware  >> $LOG 2>&1;
	pip install filter-middleware/  >> $LOG 2>&1;
	rm -r filter-middleware  >> $LOG 2>&1;
	
	printf "Updating Metric Middleware\t ... \t90%%"
	git clone https://github.com/Crystal-SDS/metric-middleware  >> $LOG 2>&1;
	pip install metric-middleware/  >> $LOG 2>&1;
	rm -r metric-middleware  >> $LOG 2>&1;
	
	printf "Updating Crystal AiO\t ... \t100%%\tCompleted!\n\n"
}


usage(){
    echo "Usage: sudo ./crystal_aio.sh install|update"
    exit 1
}


COMMAND="$1"
main(){
	if [[ `lsb_release -rs` == "16.04" ]] && [[ `uname -m` == "x86_64" ]]
	then
		case $COMMAND in
		  "install" )
		    install_crystal
		    ;;
		
		  "update" )
		    update_crystal
		    ;;
		  * )
		    install_crystal
		esac
	else
		printf "\nERROR: Crystal can't be installed in this operating system version.\n\n"
	fi
}

main
