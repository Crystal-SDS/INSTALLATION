#  Crystal: Open and Extensible Software-Defined Storage for OpenStack Swift

Crystal is a transparent, dynamic and open Software-Defined Storage (SDS) system for [OpenStack Swift](http://swift.openstack.org). 

### Documentation

The Crystal documentation is auto-generated after every commit and available online at http://crystal-controller.readthedocs.io/en/latest/

### Crystal Source code

Crystal source code is structured in several components:

* **[Controller](https://github.com/Crystal-SDS/controller)**: The Crystal control plane that offers dynamic meta-programming facilities over the data plane.

* **[Metric middleware](https://github.com/Crystal-SDS/metric-middleware)**: the middleware (data plane) that executes metrics that enable controllers to dynamically respond to workload changes in real time.

* **[Filter middleware](https://github.com/Crystal-SDS/filter-middleware)**: the middleware (data plane) that executes storage filters that intercept object flows to run computations or perform transformations on them.

* **[Dashboard]((https://github.com/Crystal-SDS/dashboard)**: A user-friendly dashboard to manage policies, filters and workload metrics.


# INSTALLATION
Crystal installation instructions
