#  Crystal: Open and Extensible Software-Defined Storage for OpenStack Swift

Crystal is a transparent, dynamic and open Software-Defined Storage (SDS) system for [OpenStack Swift](http://swift.openstack.org). 

### Documentation

The Crystal documentation is auto-generated after every commit and available online at http://crystal-controller.readthedocs.io/en/latest/

### Crystal Source code

Crystal source code is structured in several components:

* **[Controller](https://github.com/Crystal-SDS/controller)**: The Crystal control plane that offers dynamic meta-programming facilities over the data plane.

* **[Metric middleware](https://github.com/Crystal-SDS/metric-middleware)**: the middleware (data plane) that executes metrics that enable controllers to dynamically respond to workload changes in real time.

* **[Filter middleware](https://github.com/Crystal-SDS/filter-middleware)**: the middleware (data plane) that executes storage filters that intercept object flows to run computations or perform transformations on them.

* **[Dashboard](https://github.com/Crystal-SDS/dashboard)**: A user-friendly dashboard to manage policies, filters and workload metrics.


# INSTALLATION

### Cluster deployment

Follow the instructions contained in each of the previous repositories.

### All-In-One Machine

For testing purposes, it is possible to install an All-In-One (AiO) machine with all the Crystal components and requirements.
We prepared a script for automating this task. The requirements of the machine are a clean installation of **Ubuntu Server 16.04**, and at least 6GB of RAM due to the quantity of services the AiO Crystal installation contains. It is preferable to upgrade your system to the latest version with `apt update && apt dist-upgrade` before starting the installation, and set the server name as `controller` in the `/etc/hostname` file. Then, download the `crystal_aio.sh` script and run it as sudo user:

```bash
wget https://raw.githubusercontent.com/Crystal-SDS/INSTALLATION/master/crystal_aio.sh
chmod 777 crystal_aio.sh
sudo ./crystal_aio.sh install
```

The script first installs Keystone, Swift and Horizon (Pike release), then it proceeds to install all the Crystal packages. Note that the script uses weak passwords for the installed services, so if you want more secure services, please change them at the top of the script.

By default, the script has low verbosity. To see the full installation log, run the following command in another terminal:

```bash
tail -f /tmp/crystal_aio_installation.log
```

The script takes long to complete (it depends of the network connection). Once completed, you can access to the Dashboard by typing the following URL in the web browser: `http://<node-ip>/horizon`

### Development VM

The easiest way to start using Crystal is to download the Development Virtual Machine.

The Development VM runs a Swift-all-in-one cluster together with Storlets and Crystal controller and middlewares.
It also includes an extended version of the OpenStack Dashboard that simplifies the management of Crystal filters, metrics and policies.

Download the Development VM from the following URL:

* ftp://ast2-deim.urv.cat/s2caio_vm

## Support

Please [open an issue](https://github.com/Crystal-SDS/INSTALLATION/issues/new) for support.

## Contributing

Please contribute using [Github Flow](https://guides.github.com/introduction/flow/). Create a branch, add commits, and [open a pull request](https://github.com/Crystal-SDS/INSTALLATION/compare/).
