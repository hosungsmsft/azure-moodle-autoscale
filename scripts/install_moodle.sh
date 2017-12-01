#!/bin/bash

# The MIT License (MIT)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#parameters 
{
    moodleVersion=$1
    glusterNode=$2
    glusterVolume=$3 
    siteFQDN=$4
    postgresIP=$5
    moodledbname=$6
    moodledbuser=$7
    moodledbpass=$8
       adminpass=$9

	echo $moodleVersion  >> /tmp/vars.txt
	echo $glusterNode    >> /tmp/vars.txt
	echo $glusterVolume  >> /tmp/vars.txt
	echo $siteFQDN       >> /tmp/vars.txt
	echo $postgresIP      >> /tmp/vars.txt
	echo $moodledbname   >> /tmp/vars.txt
	echo $moodledbuser   >> /tmp/vars.txt
	echo $moodledbpass   >> /tmp/vars.txt
	echo    $adminpass   >> /tmp/vars.txt

    # create gluster mount point
    mkdir -p /moodle

    #configure gluster repository & install gluster client
    sudo add-apt-repository ppa:gluster/glusterfs-3.8 -y                     >> /tmp/apt1.log
    sudo apt-get -y update                                                   >> /tmp/apt2.log
    sudo apt-get -y --force-yes install glusterfs-client postgresql-client git    >> /tmp/apt3.log



    # mount gluster files system
    echo -e '\n\rInstalling GlusterFS on '$glusterNode':/'$glusterVolume '/moodle\n\r' 
    sudo mount -t glusterfs $glusterNode:/$glusterVolume /moodle

    #create html directory for storing moodle files
    sudo mkdir -p /moodle/html

    # create directory for apache ssl certs
    sudo mkdir -p /moodle/certs

    # create moodledata directory
    sudo mkdir -p /moodle/moodledata

    # install pre-requisites
    sudo apt-get install -y --fix-missing python-software-properties unzip

    # install the entire stack
    sudo apt-get -y  --force-yes install nginx php-fpm varnish pound >> /tmp/apt5a.log
    sudo apt-get -y  --force-yes install php php-cli php-curl php-zip >> /tmp/apt5b.log

    # Moodle requirements
    sudo apt-get -y update > /dev/null
    sudo apt-get install -y --force-yes graphviz aspell php-common php-soap php-json php-redis > /tmp/apt6.log
    sudo apt-get install -y --force-yes php-bcmath php-gd php-pgsql php-xmlrpc php-intl php-xml php-bz2 >> /tmp/apt6.log

    # install Moodle 
    echo '#!/bin/bash
    cd /tmp

    # downloading moodle 
    curl -k --max-redirs 10 https://github.com/moodle/moodle/archive/'$moodleVersion'.zip -L -o moodle.zip
    unzip -q moodle.zip
    echo -e \n\rMoving moodle files to Gluster\n\r 
    mv -v moodle-'$moodleVersion' /moodle/html/moodle

    # install Office 365 plugins
    #if [ "$installOfficePlugins" = "True" ]; then
            curl -k --max-redirs 10 https://github.com/Microsoft/o365-moodle/archive/'$moodleVersion'.zip -L -o o365.zip
            unzip -q o365.zip
            cp -r o365-moodle-'$moodleVersion'/* /moodle/html/moodle
            rm -rf o365-moodle-'$moodleVersion'
    #fi
    ' > /tmp/setup-moodle.sh 
    sudo chmod +x /tmp/setup-moodle.sh
    sudo /tmp/setup-moodle.sh                  >> /tmp/apt7.log

    # create cron entry
    # It is scheduled for once per day. It can be changed as needed.
    echo '0 0 * * * php /moodle/html/moodle/admin/cli/cron.php > /dev/null 2>&1' > cronjob
    sudo crontab cronjob


    # Build nginx config
    cat <<EOF >> /etc/nginx/nginx.conf
user www-data;
worker_processes 2;
pid /run/nginx.pid;

events {
	worker_connections 768;
}

http {

  sendfile on;
  tcp_nopush on;
  tcp_nodelay on;
  keepalive_timeout 65;
  types_hash_max_size 2048;
  client_max_body_size 0;
  proxy_max_temp_file_size 0;
  limit_conn_zone $server_name zone=pervhost:5M;
  limit_conn_zone $binary_remote_addr zone=perip:10m;
  server_names_hash_bucket_size  128;
  fastcgi_buffers 16 16k; 
  fastcgi_buffer_size 32k;
  proxy_buffering off;
  include /etc/nginx/mime.types;
  default_type application/octet-stream;

  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;

  set_real_ip_from   127.0.0.1;
  real_ip_header      X-Forwarded-For;
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
  ssl_prefer_server_ciphers on;

  gzip on;
  gzip_disable "msie6";
  gzip_vary on;
  gzip_proxied any;
  gzip_comp_level 6;
  gzip_buffers 16 8k;
  gzip_http_version 1.1;
  gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;

  map $http_x_forwarded_proto $fastcgi_https {                                                                                          
    default $https;                                                                                                                   
    http '';                                                                                                                          
    https on;                                                                                                                         
  }   

  log_format moodle_combined '$remote_addr - $upstream_http_x_moodleuser [$time_local] '
                             '"$request" $status $body_bytes_sent '
                             '"$http_referer" "$http_user_agent"';


  include /etc/nginx/conf.d/*.conf;
  include /etc/nginx/sites-enabled/*;
}
EOF

    cat <<EOF >> /etc/nginx/sites-enabled/${siteFQDN}.conf
server {
        listen 81;
        listen 443 ssl;
        root /moodle/html/moodle;
	index index.php index.html index.htm;

        ssl on;
        ssl_certificate /moodle/certs/nginx.crt
        ssl_certificate_key /moodle/certs/nginx.key

        # Log to syslog
        error_log syslog:server=localhost,facility=local1,severity=error,tag=${siteFQDN};
        access_log syslog:server=localhost,facility=local1,severity=notice,tag=${siteFQDN} moodle_combined;

        # Log XFF IP instead of varnish
        set_real_ip_from    10.0.0.0/8;
        set_real_ip_from    127.0.0.1;
        set_real_ip_from    172.16.0.0/12;
        set_real_ip_from    192.168.0.0/16;
        real_ip_header      X-Forwarded-For;
        real_ip_recursive   on;


        # Redirect to https
        if ($http_x_forwarded_proto = http) {
                return 301 https://$server_name$request_uri;
        }
        rewrite ^/(.*\.php)(/)(.*)$ /$1?file=/$3 last;


        # Filter out php-fpm status page
        location ~ ^/server-status {
            return 404;
        }

	location / {
		try_files $uri $uri/index.php?$query_string;
	}
 
        location ~ [^/]\.php(/|$) {
          fastcgi_split_path_info ^(.+?\.php)(/.*)$;
          if (!-f $document_root$fastcgi_script_name) {
                  return 404;
          }
 
          fastcgi_buffers 16 16k;
          fastcgi_buffer_size 32k;
          fastcgi_param   SCRIPT_FILENAME $document_root$fastcgi_script_name;
          fastcgi_pass unix:/run/php/php7.0-fpm.sock;
          fastcgi_read_timeout 3600;
          fastcgi_index index.php;
          include fastcgi_params;
        }
}
EOF

    echo -e "Generating SSL self-signed certificate"
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /moodle/certs/nginx.key -out /moodle/certs/nginx.crt -subj "/C=BR/ST=SP/L=SaoPaulo/O=IT/CN=$siteFQDN"

   # php config 
   PhpIni=/etc/php/7.0/fpm/php.ini
   sed -i "s/memory_limit.*/memory_limit = 512M/" $PhpIni
   sed -i "s/max_execution_time.*/max_execution_time = 18000/" $PhpIni
   sed -i "s/max_input_vars.*/max_input_vars = 100000/" $PhpIni
   sed -i "s/max_input_time.*/max_input_time = 600/" $PhpIni
   sed -i "s/upload_max_filesize.*/upload_max_filesize = 1024M/" $PhpIni
   sed -i "s/post_max_size.*/post_max_size = 1056M/" $PhpIni
   sed -i "s/;opcache.use_cwd.*/opcache.use_cwd = 1/" $PhpIni
   sed -i "s/;opcache.validate_timestamps.*/opcache.validate_timestamps = 1/" $PhpIni
   sed -i "s/;opcache.save_comments.*/opcache.save_comments = 1/" $PhpIni
   sed -i "s/;opcache.enable_file_override.*/opcache.enable_file_override = 0/" $PhpIni
   sed -i "s/;opcache.enable.*/opcache.enable = 1/" $PhpIni
   sed -i "s/;opcache.memory_consumption.*/opcache.memory_consumption = 256/" $PhpIni
   sed -i "s/;opcache.max_accelerated_files.*/opcache.max_accelerated_files = 8000/" $PhpIni
    
    sudo chown -R www-data /moodle/html/moodle
    sudo chown -R www-data /moodle/certs
    sudo chown -R www-data /moodle/moodledata
    sudo chmod -R 770 /moodle/html/moodle
    sudo chmod -R 770 /moodle/certs
    sudo chmod -R 770 /moodle/moodledata


   # restart Nginx
    sudo service nginx restart 
    
    # Fire off moodle setup
    echo -e "sudo -u www-data /usr/bin/php /moodle/html/moodle/admin/cli/install.php --chmod=770 --lang=pt_br --wwwroot=https://"$siteFQDN" --dataroot=/moodle/moodledata --dbhost="$postgresIP" --dbname="$moodledbname" --dbuser="$moodledbuser" --dbpass="$moodledbpass" --dbtype=mariadb --fullname='Moodle LMS' --shortname='Moodle' --adminuser=admin --adminpass="$adminpass" --adminemail=admin@"$siteFQDN" --non-interactive --agree-license --allow-unstable || true "
	         sudo -u www-data /usr/bin/php /moodle/html/moodle/admin/cli/install.php --chmod=770 --lang=en_us --wwwroot=https://$siteFQDN   --dataroot=/moodle/moodledata --dbhost=$postgresIP   --dbname=$moodledbname   --dbuser=$moodledbuser   --dbpass=$moodledbpass   --dbtype=mariadb --fullname='Moodle LMS' --shortname='Moodle' --adminuser=admin --adminpass=$adminpass   --adminemail=admin@$siteFQDN   --non-interactive --agree-license --allow-unstable || true

    echo -e "\n\rDone! Installation completed!\n\r"
}  > /tmp/install.log
