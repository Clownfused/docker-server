#!/bin/bash

# Check if running as root

if [ "$(id -u)" != "0" ]; then
echo "This script must be run as root" 1>&2
exit 1
fi

# Inputs

read -p "User for containers and basic authentication?  " user
while true
do
read -s -p "Create password " password
echo
read -s -p "Verify password " password2
[ "$password" = "$password2" ] && break
echo "Please try again"
done
echo
echo -n "What is your domain name? "; read domain
echo -n "What is your email address? "; read email
echo -n "What is the path to docker container config files? (do not include trailing /) "; read config
echo -n "What is the path to media files? (do not include trailing /) "; read media
echo -n "What is the path to downloads? (do not include trailing /) "; read downloads

# Variables

uid=$(id -u $user)
gid=$(id -g $user)
timezone=$(cat /etc/timezone)

# Install docker

apt-get update
apt-get upgrade -y
apt-get install -y apt-transport-https ca-certificates
apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
echo "deb https://apt.dockerproject.org/repo ubuntu-xenial main" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get purge -y lxc-docker
apt-cache policy docker-engine
apt-get update
apt-get install -y linux-image-extra-$(uname -r) linux-image-extra-virtual
apt-get update
apt-get install -y docker-engine
service docker start
groupadd docker
usermod -aG docker $user
systemctl enable docker

# Create and start containers

# Nginx
docker run -d \
--privileged \
--name=nginx \
-p 80:80 \
-p 443:443 \
-e EMAIL=$email \
-e URL=$domain \
-e SUBDOMAINS=www  \
-e TZ=$timezone \
-v $config/nginx/:/config:rw \
aptalca/nginx-letsencrypt

# Plex
docker run -d \
--name=plex \
--net=host \
-e VERSION=latest \
-e PUID=$uid -e PGID=$gid \
-e TZ=$timezone \
-v $config/plex:/config \
-v $media:/media \
linuxserver/plex

# CouchPotato
docker run -d \
--name=couchpotato \
-v $config/couchpotato:/config \
-v $downloads:/downloads \
-v $media:/media \
-e PGID=$gid -e PUID=$uid  \
-e TZ=$timezone \
-p 5050:5050 \
linuxserver/couchpotato

# Sonarr
docker run -d \
--name sonarr \
-p 8989:8989 \
-e PUID=$uid -e PGID=$gid \
-v /dev/rtc:/dev/rtc:ro \
-v $config/sonarr:/config \
-v $media:/media \
-v $downloads:/downloads \
linuxserver/sonarr

# PlexPy
docker run -d \
--name=plexpy \
-v $config/plexpy:/config \
-v $config/plex/Library/Application\ Support/Plex\ Media\ Server/Logs:/logs:ro \
-e PGID=$gid -e PUID=$uid  \
-e TZ=$timezone \
-p 8181:8181 \
linuxserver/plexpy

# SABnzbd
docker run -d \
--name=sabnzbd \
-v $config/sabnzbd:/config \
-v $downloads:/downloads \
-e PGID=$gid -e PUID=$uid \
-e TZ=$timezone \
-p 8080:8080 -p 9090:9090 \
linuxserver/sabnzbd

# Deluge
docker run -d \
--name deluge \
-p 8112:8112 \
-p 58846:58846 \
-p 58946:58946 \
-e PUID=$uid -e PGID=$gid \
-e TZ=$timezone \
-v $downloads:/downloads \
-v $config/deluge:/config \
linuxserver/deluge

# Jackett
docker run -d \
--name=jackett \
-v $config/jackett:/config \
-v $downloads:/downloads \
-e PGID=$gid -e PUID=$uid \
-e TZ=$timezone \
-p 9117:9117 \
linuxserver/jackett

# PlexRequests
docker run -d \
--name=plexrequests \
-v /etc/localtime:/etc/localtime:ro \
-v $config/plexrequests:/config \
-e PGID=$gid -e PUID=$uid  \
-e URL_BASE=/request \
-p 3000:3000 \
linuxserver/plexrequests

# Set URL base for reverse proxying

docker stop couchpotato jackett plexpy sonarr
sed -i 's#url_base =#url_base = /couchpotato#' $config/couchpotato/config.ini
sed -i 's#"BasePathOverride": null#"BasePathOverride": "/jackett"#' $config/jackett/Jackett/ServerConfig.json
sed -i 's#http_root = ""#http_root = /plexpy#' $config/plexpy/config.ini
sed -i 's#<UrlBase></UrlBase>#<UrlBase>/sonarr</UrlBase>#' $config/sonarr/config.xml
docker start couchpotato jackett plexpy sonarr

# Setup systemd service for each container

for d in $config/* ; do
dir=$(basename $d)
cat > /etc/systemd/system/$dir.service << EOF
[Unit]
Description=$dir container
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/docker start -a $dir
ExecStop=/usr/bin/docker stop -t 2 $dir

[Install]
WantedBy=default.target
EOF
systemctl daemon-reload
systemctl enable $dir
done

# Install htpasswd and setup basic authentication

apt-get install -y apache2-utils
htpasswd -b -c $config/nginx/.htpasswd $user $password

# Setup Nginx reverse proxying

systemctl stop nginx
rm $config/nginx/nginx/site-confs/default
ip=$(ifconfig ens18 2>/dev/null|awk '/inet addr:/ {print $2}'|sed 's/addr://')
cat > $config/nginx/nginx/site-confs/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $domain www.$domain;
    return 301 https://\$server_name\$request_uri;
    }
 
server {
    listen 443 ssl http2 default_server;
    listen [::]:443 ssl http2 default_server;
    ssl_certificate /config/keys/fullchain.pem;
    ssl_certificate_key /config/keys/privkey.pem;
    ssl_dhparam /config/nginx/dhparams.pem;
    ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA';
    ssl_prefer_server_ciphers on;
    auth_basic "Restricted";
    auth_basic_user_file /config/.htpasswd;

    # Sonarr
    location /sonarr {
        proxy_pass http://$ip:8989;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
    
    # Deluge
    location /deluge {
        proxy_pass http://$ip:8112/;
        proxy_set_header X-Deluge-Base "/deluge/";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }

    # PlexRequests
    location /request {
        auth_basic off;
        proxy_pass http://$ip:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }

    # SABnzbd
    location /sabnzbd {
        proxy_pass http://$ip:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }

    # CouchPotato
    location /couchpotato {
        proxy_pass http://$ip:5050;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }

    # PlexPy
    location /plexpy {
        proxy_pass http://$ip:8181;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }

    # Jackett
    location /jackett/ {
        proxy_pass http://$ip:9117/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
 
}
EOF
systemctl start nginx

# Set permissions

chown -R $user:$user $config $media $downloads

echo "Done!"
