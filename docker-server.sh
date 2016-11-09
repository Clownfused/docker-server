#!/bin/bash

# Check if running as root

if [ "$(id -u)" != "0" ]; then
echo "This script must be run with sudo" 1>&2
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

# Install Docker & Docker Compose

curl -s https://gist.githubusercontent.com/luislobo/2dc3de67b7f2ddc623c239dff36962a0/raw/9f24ff62eb7ada78718f5a805b54c0295c248692/install_latest_docker_compose.sh | bash /dev/stdin
usermod -aG docker $user

# Create and start containers

cat > /home/$user/docker-server/docker-compose.yml << EOF
version: '2'
services:
  nginx:
    container_name: nginx
    image: linuxserver/letsencrypt
    restart: always
    privileged: true
    volumes:
      - $config/nginx:/config
    ports:
      - "80:80"
      - "443:443"
    environment:
      - EMAIL=$email
      - URL=$domain
      - SUBDOMAINS=www
      - PUID=$uid
      - PGID=$gid
      - TZ=$timezone
  plex:
    container_name: plex
    image: linuxserver/plex
    restart: always
    network_mode: "host"
    volumes:
      - $config/plex:/config
      - $media:/media
    environment:
      - VERSION=latest
      - PUID=$uid
      - PGID=$gid
      - TZ=$timezone
  couchpotato:
    container_name: couchpotato
    image: linuxserver/couchpotato
    restart: always
    volumes:
      - $config/couchpotato:/config
      - $media:/media
      - $downloads:/downloads
    ports:
      - "5050:5050"
    environment:
      - PUID=$uid  
      - PGID=$gid
      - TZ=$timezone
  sonarr:
    container_name: sonarr
    image: linuxserver/sonarr
    restart: always
    volumes:
      - $config/sonarr:/config
      - $media:/media
      - $downloads:/downloads
      - /dev/rtc:/dev/rtc:ro
    ports:
      - "8989:8989"
    environment:
      - PUID=$uid  
      - PGID=$gid
      - TZ=$timezone
  plexpy:
    container_name: plexpy
    image: linuxserver/plexpy
    restart: always
    volumes:
      - $config/plexpy:/config
      - $config/plex/Library/Application\ Support/Plex\ Media\ Server/Logs:/logs:ro
    ports:
      - "8181:8181"
    environment:
      - PUID=$uid  
      - PGID=$gid
      - TZ=$timezone
  sabnzbd:
    container_name: sabnzbd
    image: linuxserver/sabnzbd
    restart: always
    volumes:
      - $config/sabnzbd:/config
      - $downloads:/downloads
    ports:
      - "8080:8080"
      - "9090:9090"
    environment:
      - PUID=$uid
      - PGID=$gid
      - TZ=$timezone
  deluge:
    container_name: deluge
    image: linuxserver/deluge
    restart: always
    volumes:
      - $config/deluge:/config
      - $downloads:/downloads
    ports:
      - "8112:8112"
      - "58846:58846"
      - "58946:58946"
    environment:
      - PUID=$uid
      - PGID=$gid
      - TZ=$timezone
  jackett:
    container_name: jackett
    image: linuxserver/jackett
    restart: always
    volumes:
      - $config/jackett:/config
      - $downloads:/downloads
    ports:
      - "9117:9117"
    environment:
      - PUID=$uid
      - PGID=$gid
      - TZ=$timezone
  plexrequests:
    container_name: plexrequests
    image: linuxserver/plexrequests
    restart: always
    volumes:
      - $config/plexrequests:/config
      - $downloads:/downloads
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "3000:3000"
    environment:
      - PUID=$uid
      - PGID=$gid
      - URL_BASE=/request
EOF
chown $user:$user /home/$user/docker-server/docker-compose.yml
cd /home/$user/docker-server/
docker-compose up -d
echo "Pausing for 30s to allow config files to be created..."
sleep 30

# Set URL base for reverse proxying

docker-compose stop couchpotato jackett plexpy sonarr
sed -i 's#url_base =#url_base = /couchpotato#' $config/couchpotato/config.ini
sed -i 's#"BasePathOverride": null#"BasePathOverride": "/jackett"#' $config/jackett/Jackett/ServerConfig.json
sed -i 's#http_root = ""#http_root = /plexpy#' $config/plexpy/config.ini
sed -i 's#<UrlBase></UrlBase>#<UrlBase>/sonarr</UrlBase>#' $config/sonarr/config.xml
docker-compose start couchpotato jackett plexpy sonarr

# Install htpasswd and setup basic authentication

apt-get install -y apache2-utils
htpasswd -b -c $config/nginx/.htpasswd $user $password

# Setup Nginx reverse proxying

docker-compose stop nginx
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
    ssl_certificate /config/etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /config/etc/letsencrypt/live/$domain/privkey.pem;
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
docker-compose start nginx

# Set permissions

chown -R $user:$user $config

echo "Done!"
