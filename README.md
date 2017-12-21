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
- azureBackupSwitch: Switch to configure AzureBackup and enlist VM's; if you use '1', Azure Backup will be configured to backup GlusterFS nodes. The schedule can later be adjusted in the portal.
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
- autoscaleVmSku: The size of the VM used for autoscaling. Currently limited to Standard VMs.
- autoscaleVmCount: The maximum number (default 10) of instances to scale up to. The minimum is always 2.
- sshPublicKey: This is a REQUIRED parameter for accessing the controller VM. It should be your private key.

## *Sizing Considerations and Limitations*

Depending on what you're doing with Moodle, there are several considerations to make when configuring. The defaults included produce a cluster that is inexpensive but probably too low spec to use beyond single-user Moodle testing.

### *Database Sizing*

As of the time of this writing, Azure supports "Basic" and "Standard" tiers for database instances. In addition the skuCapacityDTU defines Compute Units, and the number of those you can use is limited by database tier:

Basic: 50, 100
Standard: 100, 200, 400, 800

This value also limits the maximum number of connections, as defined here: https://docs.microsoft.com/en-us/azure/mysql/concepts-limits

As the Moodle database will handle cron processes as well as the website, any public facing website with more than 10 users will likely require upgrading to 100. Once the site reaches 30+ users it will require upgrading to Standard for more compute units. This depends entirely on the individual site. As MySQL databases cannot change (or be restored to a different tier) once deployed it is a good idea to slightly overspec your database.

Standard instances have a minimum storage requirement of 128000MB. All database storage, regardless of tier, has a hard upper limit of 1 terrabyte. After 128GB you gain additional iops for each GB, so if you're expecting a heavy amount of traffic you will want to oversize your storage. The current maximum iops with a 1TB disk is 3000.

### *Controller instance sizing*

The controller handles both syslog and cron duties. Depending on how big your Moodle cron runs are this may not be sufficient. If cron jobs are very delayed and cron processes are building up on the controller then an upgrade in tier is needed.

### *Frontend instances*

In general the frontend instances will not be the source of any bottlenecks unless they are severely undersized versus the rest of the cluster. More powerful instances will be needed should fpm processes spawn and exhaust memory during periods of heavy site load. This can also be mitigated against by increasing the number of VMs but spawning new VMs is slower (and potentially more expensive) than having that capacity already available.

### *Observed Situations in Testing*

Running a load test simulating multiple simultaneous users going through typical Moodle activity, the following setups were noted as performing adequately:

## *Using the created stack*

In testing, stacks typically took between 1 and 2 hours to finish, depending on spec. Once this is done you will receive a JSON with outputs needed to continue setup. These outputs are also available by clicking on the deployment for your resource group when it finishes. They are:

- moodle-admin-password: The password for the "admin" user in your Moodle install.
- load-balancer-dns: This is the address of your load balancer. You'll need to add a DNS entry for the website URL you entered that CNAMEs to this.
- controller-instance-ip: This is the address of the controller. You will need to SSH into this to make changes to your moodle code or view logs.
- database-dns: This is the public DNS of your database instance. If you wish to set up local backups or access the db directly, you'll need to use this.
- database-admin-username: The master account (not Moodle) username for your database.
- database-admin-password: The master account password for your database.

### *Updating Moodle code/settings*

Your controller VM has Moodle code and data stored on /moodle. The code is stored in /moodle/html/moodle/. This is also mounted to your autoscaled frontends so all changes are instant. Depending on how large your Gluster disks are sized, it may be helpful to keep multiple older versions (/moodle/html1, /moodle/html2, etc) to roll back if needed.

### *Getting an SQL dump*

If your database is small enough to fit, you may be able to get an SQL dump of your Moodle db by dumping it to /moodle/. Otherwise, you'll want to do this remotely by connecting to the hostname shown in the database-dns output using the database-admin-username and database-admin-password. This is a good idea to do routinely in order to have an easily restored database backup.

Note: Azure does NOT currently back up Postgres/MySQL databases.

### *Azure Recovery Services*

If you have set azureBackupSwitch to 1 then Azure will provide VM backups of your Gluster node. This is recommended as it contains both your Moodle code and your sitedata. Restoring a backed up VM is outside the scope of this doc, but Azure's documentation on Recovery Services can be found here: https://docs.microsoft.com/en-us/azure/backup/backup-azure-vms-first-look-arm

### *Resizing your Database*

Note: This involves a lengthy site downtime.

As mentioned above, Azure does not currently support resizing databases. You can, however, create a new database instance and change your config to point to that. To get a different size database you'll need to:

1. Place your Moodle site into maintenance mode. You can do this either via the web interface or the command line on the controller VM.
2. Perform an SQL dump of your database, either to /moodle or remotely to your machine.
3. Create a new Azure database of the size you want inside your existing resource group.
4. Using the details in your /moodle/html/moodle/config.php create a new user and database matching the details in config.php. Make sure to grant all rights on the db to the user.
5. On the controller instance, change the db setting in /moodle/html/moodle/config.php to point to the new database.
6. Take Moodle site out of maintenance mode.
7. Once confirmed working, delete the previous database instance.

How long this takes depends entirely on the size of your database and the speed of your VM tier. It will always be a large enough window to make a noticeable outage.

### *Changing the SSL cert*

The self-signed cert generated by the template is suitable for very basic testing, but a public website will want a real cert. After purchasing a trusted certificate, it can be copied to the following files to be ready immediately:

- /moodle/certs/nginx.key: Your certificate's private key
- /moodle/certs/nginx.crt: Your combined signed certificate and trust chain certificates.

Once replaced these changes become effective immediately.

