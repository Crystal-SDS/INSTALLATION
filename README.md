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
We prepared a script for automating this task. The requirements of the machine are a clean installation of **Ubuntu Server 16.04**, and at least **6GB** of RAM due to the quantity of services the AiO Crystal installation contains. It is preferable to upgrade your system to the latest version with `apt update && apt dist-upgrade` before starting the installation, and set the server name as `controller` in the `/etc/hostname` file. Then, download the `crystal_aio.sh` script and run it as sudo:

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

The script takes long to complete (it depends of the network connection). Once completed, you can access to the dashboard by typing the following URL in the web browser: `http://<node-ip>/horizon`. Once logged into the dashboard, follow these steps to finish the installation:
1. Go to the left menu, `Swift Cluster --> Nodes`, and "Edit" the controller proxy node. Write the credentials of your default user to enable ssh access to Crystal (The user must be sudoer: `usermod -aG sudo username`).
2. Go to the left menu, `Swift Cluster --> Storage policies`, and click "Load Swift Policies" button. This will load your current storage policies from `/etc/swift/swift.conf`
3. Go to the left menu, `SDS Management --> Projects`, and "Enable Crystal" to the crystal test project (or any other project you want to use Crystal).
4. Download the `crystal_dashboard.json` file from this repository. Then, go to the left menu, `Monitoring --> kibana`. Within the kibana dashboard, go to `Management --> Saved Objects`, click on "Import" and select the `crystal_dashboard.json` file. Once imported, go to the left kibana menu `Dashboard` and open the `Crystal-system-overview`. Then, in the top meu, click `share -> Share snapshoot -> Embedded iframe --> Short url`. From the provided `iframe src url`, for example: `http://192.168.1.10:5601/goto/2ebe2fe8c1a6bb694af4e4c104730c04?embed=true` copy the last hashtag and paste it into `/etc/openstack-dashboard/local_settings.py` in the variable `CRYSTAL_MONITORING_DASHBOARD` located at the end of the document, for example: `CRYSTAL_MONITORING_DASHBOARD="2ebe2fe8c1a6bb694af4e4c104730c04"`.


### Development VM

The easiest way to start using Crystal is to download the Development Virtual Machine.

The Development VM runs a Swift-all-in-one cluster together with Storlets and Crystal controller and middlewares.
It also includes an extended version of the OpenStack Dashboard that simplifies the management of Crystal filters, metrics and policies.

Download the Development VM from the following URL:

* [http://cloudlab.urv.cat/crystal/vm/crystal_aio.ova](http://cloudlab.urv.cat/crystal/vm/crystal_aio.ova)

Once downloaded, follow thsee steps:
1. Create a VM with at least 6Gb of RAM from the .ova file.
2. Start the VM and use the following credentials to login: - user: **crystal** | - password: **crystal**
3. Run the next script to update the IP adddress: `sudo ./set_current_ip.sh`
4. Once the script completes the process, you will see in the screen the instructions for accessing to the dashboard.


## Support

Please [open an issue](https://github.com/Crystal-SDS/INSTALLATION/issues/new) for support.

## Contributing

Please contribute using [Github Flow](https://guides.github.com/introduction/flow/). Create a branch, add commits, and [open a pull request](https://github.com/Crystal-SDS/INSTALLATION/compare/).
