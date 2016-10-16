After a fresh Ubuntu Server 16.04 install, run the following command:

```
git clone https://github.com/aberg83/docker-server.git && cd ~/docker-server && sudo ./docker-server.sh
```

When the script finishes running, you will be able to access the apps at www.yourdomain.com/appname Your browser will prompt you for the login credentials you set within the script.

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
