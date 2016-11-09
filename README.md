After a fresh Ubuntu Server 16.04 install, run the following command:

```
sudo apt-get -y update; sudo apt-get -y upgrade; sudo apt-get -y install git; \
git clone https://github.com/aberg83/docker-server.git && sudo bash ~/docker-server/docker-server.sh
```

When the script finishes running, log out and back in and wait a few minutes to let your DH parameters and SSL certificate generate. You can monitor this by typing 'docker logs -f nginx'. Once Nginx has fully started, you will be able to access the apps at www.yourdomain.com/appname. Your browser will prompt you for the login credentials you set within the script.

Installed docker containers:
- linuxserver/letsencrypt
- linuxserver/plex
- linuxserver/couchpotato [ URL: www.yourdomain.com/couchpotato ]
- linuxserver/sonarr [ URL: www.yourdomain.com/sonarr ]
- linuxserver/plexpy [ URL: www.yourdomain.com/plexpy ]
- linuxserver/jackett [ URL: www.yourdomain.com/jackett ]
- linuxserver/sabnzbd [ URL: www.yourdomain.com/sabnzbd ]
- linuxserver/deluge [ URL: www.yourdomain.com/deluge ]
- linuxserver/plexrequests [ URL: www.yourdomain.com/request ]

Notes:
- This has only been tested with a top-level domain name. Results may vary if using a subdomain.
- Plex configuration will need to be completed with an SSH tunnel if the server is on a remote network. See https://support.plex.tv/hc/en-us/articles/200288586-Installation.
