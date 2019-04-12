#!/bin/bash

# TODO voir quels fichier d'install
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BOLD='\e[1m'
orig=$(pwd)

# TODO rajouter demande url site web
read -p "Saisir le nom de domaine du site : (sans https:// ni www.) " url

read -p "Are you sure (Y/n) ? " -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

# update repo
echo -e "${BOLD}[Bizzbee]\t${GREEN}Add source list for certbot ppa..."
sudo echo "deb http://ppa.launchpad.net/certbot/certbot/ubuntu cosmic main \
deb-src http://ppa.launchpad.net/certbot/certbot/ubuntu cosmic main" > /etc/apt/sources.list.d/certbor-ppa.list

echo -e "${BOLD}[Bizzbee]\t${GREEN}Update repos..."
sudo apt-get update
sudo apt-get dist-upgrade -y

# enbale ssh if needed
# sudo raspi-config nonint do_ssh 0

# install nodejs + pm2
echo -e "${BOLD}[Bizzbee]\t${GREEN}Install NodeJS and pm2..."
curl -sL https://deb.nodesource.com/setup_8.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install pm2@latest -g

#adduser bizzbee
echo -e "${BOLD}[Bizzbee]\t${GREEN}Install firewall ufw..." 
sudo apt-get install -y ufw
echo -e "${BOLD}[Bizzbee]\t${GREEN}Enable ufw rules (OpenSSH, Nginx Full)..."
sudo ufw allow OpenSSH
sudo ufw enable

# install nginx
echo -e "${BOLD}[Bizzbee]\t${GREEN}Install and configure Nginx..."
sudo apt install -y nginx
sudo ufw allow 'Nginx Full'

echo -e "${BOLD}[Bizzbee]\t${GREEN}Create directory for website storage..."
sudo mkdir -p /var/www/bizzbee.maximegautier.fr/html

echo -e "${BOLD}[Bizzbee]\t${GREEN}Create temporary page for HTTPS certificate generation..."
sudo echo "<html>
    <head>
        <title>Welcome to bizzbee.maximegautier.fr!</title>
    </head>
    <body>
        <h1>Success!  The bizzbee.maximegautier.fr server block is working!</h1>
    </body>
</html>" > /var/www/bizzbee.maximegautier.fr/html/index.html

sudo chown -R $USER:$USER /var/www/bizzbee.maximegautier.fr/html
sudo chmod -R 755 /var/www/bizzbee.maximegautier.fr

echo -e "${BOLD}[Bizzbee]\t${GREEN}Add temporary server configuration..."
sudo echo "server { 
        listen 80 default_server; 
        listen [::]:80 default_server; 
 
        root /var/www/bizzbee.maximegautier.fr/html; 
        index index.html index.htm index.nginx-debian.html; 
 
        server_name bizzbee.maximegautier.fr www.bizzbee.maximegautier.fr; 
 
        location / { 
                try_files \$uri \$uri/ =404; 
        } 
}" > /etc/nginx/sites-available/bizzbee.maximegautier.fr
sudo rm /etc/nginx/sites-enabled/default
sudo ln -s /etc/nginx/sites-available/bizzbee.maximegautier.fr /etc/nginx/sites-enabled/

echo -e "${BOLD}[Bizzbee]\t${GREEN}Install certbot and make HTTPS certificates..."
sudo apt install -y python-certbot-nginx
certbot --nginx -d bizzbee.maximegautier.fr -d www.bizzbee.maximegautier.fr 

# install postgresql
echo -e "${BOLD}[Bizzbee]\t${GREEN}Install PostgreSQL..."
sudo apt-get install -y postgresql libpq-dev postgresql-client
postgresql-client-common -y

# install python3 modules
#sudo pip3 install psycopg2

# clone bizzbee-repo
echo -e "${BOLD}[Bizzbee]\t${GREEN}Clone bizzbee repos in www directory..."
cd $orig
sudo git clone https://github.com/gautiemi/projet-2a-iut.git
cd /var/www/bizzbee.maximegautier.fr/ 
sudo git clone https://github.com/thomasaudo/bizbee_api.git

# database creation
echo -e "${BOLD}[Bizzbee]\t${GREEN}Initialyze bizzbee database..."
echo -e "${BOLD}[Bizzbee]\t${ORANGE}Type password for postgres user (= postgres)"
sudo -u postgres psql -a -f $orig/SQL/create_role.sql

echo -e "${BOLD}[Bizzbee]\t${ORANGE}Type password for bizzbee user (= bizzbee)"
sudo psql -h 127.0.0.1 -U bizzbee -d bizzbee -a -f $orig/SQL/script.sql

echo -e "${BOLD}[Bizzbee]\t${GREEN}Start NodeJS app.js..."
cd /var/www/bizzbee.maximegautier.fr/bizbee_api
nom install .
pm2 start app.js
pm2 startup systemd
# sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u bizzbee --hp /home/bizzbee
# pm2 unstartup systemd

echo -e "${BOLD}[Bizzbee]\t${GREEN}Add final configuration for website..."
sudo sed "$(sed -n '\|try_files $uri $uri/ =404;|=' /etc/nginx/sites-available/bizzbee.maximegautier.fr)i \ \t\tproxy_pass http://localhost:3000;\n\
\t\tproxy_http_version 1.1;\n\
\t\tproxy_set_header Upgrade \$http_upgrade;\n\
\t\tproxy_set_header Connection 'upgrade';\n\
\t\tproxy_set_header Host \$host;\n\
\t\tproxy_cache_bypass \$http_upgrade;\n" /etc/nginx/sites-available/bizzbee.maximegautier.fr

echo -e "${BOLD}[Bizzbee]\t${GREEN}Remove temporary configuration..."
sudo rm /var/www/bizzbee.maximegautier.fr/index.html
sudo rm -r $orig

echo -e "${BOLD}[Bizzbee]\t${GREEN}Restart nginx server..."
sudo systemctl restart nginx

echo "\e[1;33mDone"
