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

For testing purposes, is possible to install an All-In-One (AiO) machine with all the Crystal components and requirements.
We prepared a script for automating this task, the only requirement is a clean installation of Ubuntu Server 16.04. Then, download the `install_aio.sh` script and run it as sudo user.

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