After a fresh Ubuntu Server 16.04 install, run the following command:

```
sudo apt-get -y update && sudo apt-get -y upgrade && sudo apt-get -y install git && git clone https://github.com/aberg83/docker-server.git && cd ~/docker-server && sudo ./docker-server.sh
```

When the script finishes running, wait a few minutes to let your DH parameters and SSL certificate generate. You can monitor this by typing 'docker-compose logs -f nginx' within the 'docker-server' folder. Once Nginx has fully started, you will be able to access the apps at www.yourdomain.com/appname. Your browser will prompt you for the login credentials you set within the script.

Installed docker containers:
- aptalca/nginx-letsencrypt
- linuxserver/plex
- linuxserver/couchpotato
- linuxserver/sonarr
- linuxserver/plexpy
- linuxserver/jackett
- linuxserver/sabnzbd
- linuxserver/deluge
- linuxserver/plexrequests
