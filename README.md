# *Autoscaling Moodle stack for Postgres and MySQL databases*

This work is mostly based on Paulo Teixeira's work here: 

This template set deploys the following infrastructure:
- Autoscaling web frontend layer (Nginx, php-fpm, Varnish)
- Private virtual network for frontend instances
- Controller instance running cron and handling syslog for the autoscaled site
- Load balancer to balance across the autoscaled instances
- Postgres or MySQL database
- Azure Redis instance for Moodle caching
- ObjectFS in Azure blobs (Moodle sitedata)
- Elasticsearch VM for search indexing in Moodle
- Dual gluster nodes for high availability access to Moodle files

## *Parameters for the deployment* 

These can all be customized in the azure.parameters.json file depending on the size of the stack needed.

- moodleVersion: The Moodle version you want to install. Only MOODLE_33_STABLE and MOODLE_34_STABLE are valid due to fixes in Moodle core.
- glusterTshirtSize: VM size for the gluster nodes (please check for more guidance below)
- applyScriptsSwitch: Use '1' ALWAYS; Switch to process or bypass all scripts/extensions; if you use '0' (zero), this template will only create the machines
- azureBackupSwitch: Switch to configure AzureBackup and enlist VM's; if you use '1', Azure Backup will be configured to backup postgresql and GlusterFS nodes; highly recommended. The backup schedule can be adjusted later in the portal.
- dbServerType: The type of database used. Valid entries are "mysql" and "postgres".
- blobStorageAccountType: The tier of blob storage. Valid entries are "Standard_LRS", "Standard_GRS", "Standard_ZRS", and "Premium_LRS"
- controllerVmSku: The size of your Controller VM
- elasticVmSku: The size of the VM used for elasticsearch.
- glusterVmSku: The size of the VM used for the Gluster storage VMs
- glusterDiskSize: The size of each individual gluster disk
- glusterDiskCount: The number of RAID0 disks on each gluster node
- location: The region in Azure you want to deploy to
- siteURL: The URL of your Moodle website
- skuCapacityDTU: The compute units of your database. Valid entries are 50, 100, 200, 400, and 800. Depends on skuTier.
- skuSizeMB: The disk size of the database instance, in megabytes.
- skuTier: The tier of database. Current valid entries are "Basic" and "Standard". In order to use higher skuCapacityDTU values you'll need to use Standard.
- postgresVersion: Version of Postgres. Valid entries are "9.5" and "9.6"
- mysqlVersion: Version of Mysql. Valid entries are "5.6" and "5.7"
- vNetAddressSpace: Address range for the Moodle virtual network - presumed /16 - further subneting during vnet creation

## *Sizing Considerations and Limitations*

Depending on what you're doing with Moodle, there are several considerations to make when configuring. The defaults included produce a cluster that is inexpensive but probably too low spec to use beyond single-user Moodle testing.

### Database Sizing

As of the time of this writing, Azure supports "Basic" and "Standard" tiers for database instances. In addition the skuCapacityDTU defines Compute Units, and the number of those you can use is limited by database tier:

Basic: 50, 100
Standard: 100, 200, 400, 800

This value also limits the maximum number of connections, as defined here: https://docs.microsoft.com/en-us/azure/mysql/concepts-limits

As the Moodle database will handle cron processes as well as the website, any public facing website with more than 20 users will likely require upgrading to 100. Once the site reaches 50+ users it will require upgrading to Standard for more compute units. This depends entirely on the individual site. As databases cannot change (or be restored to a different tier) once deployed it is a good idea to slightly overspec your database.

Standard instances have a minimum storage requirement of 128000MB. All database storage, regardless of tier, has a hard upper limit of 1 terrabyte.

### Controller instance sizing

The controller handles both syslog and cron duties. Depending on how big your Moodle cron runs are this may not be sufficient. If cron jobs are very delayed and cron processes are building up on the controller then an upgrade in tier is needed.

### Frontend instances

In general the frontend instances will not be the source of any bottlenecks unless they are severely undersized versus the rest of the cluster. More powerful instances will be needed should fpm processes spawn and exhaust memory during periods of heavy site load. This can also be mitigated against by modifying 

### The web layer

This script deploys a vm scale set (vmss) for the web layer. It's configured with Standard_DS2_v2 instances, with no data-disks, all connected to the GlusterFS cluster (mounted in the /moodle folder where source code, moodledata and ssl certificates resides).
The VMSS is also configured with auto-scale settings and will run, at minimum 02 instances up to 10 instances of the web application; the trigger for deploying additional instances is based on CPU usage. Those settings can be ajusted in Azure Portal or in the Azure Resources Editor (resources.azure.com).

## *Updating the source code or Apache SSL certificates* 

There's a jumpbox machine in the deployment that can be used to update Moodle's source code, or SSL certificates in the web layer. 
In order to proceed with this kind of update, connect to the machine using the root credentials provided during the template setup. 
- Moodle source code is located at /moodle/html/moodle
- Apache SSL certificates are located at /moodle/certs
- Moodledata content is located at /moodle/moodledata

## *Step by step video walkthrough* 

We also have a [step by step video](http://learningcontentdemo.azurewebsites.net/VideoHowToDemoMoodleOnAzure3) showing us how to deploy this template (Thanks to Ingo Laue for his contribution)

This template is aimed to have constant updates, and would include other improvements in the future. 

Hope it helps.

Feedbacks are welcome.


