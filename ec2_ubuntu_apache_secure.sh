#!/bin/bash
# Used to configure Apache on AWS EC2 Ubuntu 22.04 LTS image
# Single web site setup
# Warning there is no error control, testing, or checking of anything
# Everything is hardcoded to get it to work. This will break as Ubuntu and Apache evolve
# Author Christopher J. Burke 2022-05-27
# If things break then the file /var/log/cloud-init-output.log can be
#  viewed to see the stdout from all the below commands.

# First update Ubuntu noninteractively
#  From https://askubuntu.com/questions/1364742/how-to-do-apt-upgrade-with-noninteractive
#  The trick is setting DEBIAN_FRONTEND in combination with sudo -E 
#  the -E flag tells sudo to forward the environment variable
#  The other things are there to force some yeses.
sudo apt update -y
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" dist-upgrade -q -y --allow-downgrades --allow-remove-essential --allow-change-held-packages

#Install apache
sudo -E apt-get -y install apache2
#Harden apache steps
# From various blog sources
# https://linuxhint.com/secure_apache_server/
# https://help.dreamhost.com/hc/en-us/articles/226327268-The-most-important-steps-to-take-to-make-an-Apache-server-more-secure
# https://hostadvice.com/how-to/how-to-harden-your-apache-web-server-on-ubuntu-18-04/
# https://geekflare.com/apache-web-server-hardening-security/
# https://www.linuxcapable.com/how-to-install-apache-with-modsecurity-on-ubuntu-22-04-lts/
# https://ipm.hutton.ac.uk/sites/ipm.hutton.ac.uk/files/Apache%20Web%20Server%20Hardening%20and%20Security%20Guide.pdf
# https://hackernoon.com/apache-web-server-hardening-how-to-protect-your-server-from-attacks-tc1t3umm
# change directory to non-root ownership
sudo chown -R www-data:www-data /etc/apache2

# Make changes to /etc/apache2/conf-available/security.conf
# Turn off extra server info returned in headers
sudo sed -i.bak0 -e "s/#ServerSignature Off/ServerSignature off/" -e "s/ServerSignature On/#ServerSignature On/" /etc/apache2/conf-available/security.conf
sudo sed -i.bak1 -e "s/^ServerTokens Full/#ServerTokens Full/" -e "s/^ServerTokens OS/#ServerTokens OS/" -e "s/^ServerTokens Minimal/#ServerTokens Minimal/" -e "s/# ServerTokens/# ServerTokens\nServerTokens Prod/"  /etc/apache2/conf-available/security.conf
# Turn off FileETag
echo "FileETag None" | sudo tee -a /etc/apache2/conf-available/security.conf
sudo a2enmod headers
echo "Header always append X-Frame-Options SAMEORIGIN" | sudo tee -a /etc/apache2/conf-available/security.conf
echo "Header always set X-XSS-Protection: \"1; mode=block\"" | sudo tee -a /etc/apache2/conf-available/security.conf
echo "Header always set X-Content-Type-Options: \"nosniff\"" | sudo tee -a /etc/apache2/conf-available/security.conf
echo "Header always set Strict-Transport-Security \"max-age=31536000; includeSubDomains\"" | sudo tee -a /etc/apache2/conf-available/security.conf
echo "Header always edit Set-Cookie ^(.*)$ $1;HttpOnly;Secure" | sudo tee -a /etc/apache2/conf-available/security.conf
# Turn on rewrite module to disable http 1.0 requests
sudo a2enmod rewrite
echo "RewriteEngine On" | sudo tee -a /etc/apache2/conf-available/security.conf
echo "RewriteCond %{THE_REQUEST} HTTP/1\.0$" | sudo tee -a /etc/apache2/conf-available/security.conf
echo "RewriteRule .? - [F]" | sudo tee -a /etc/apache2/conf-available/security.conf

# Make changes to /etc/apache2/apache2.conf
# Disallow listing of files in directories
sudo sed -i.bak0 -e "s/        Options Indexes FollowSymLinks/          Options -Indexes -Includes -ExecCGI\n           Options -FollowSymLinks/" /etc/apache2/apache2.conf
# Disallow .htaccess
sudo sed -i.bak1 -e "s/AccessFileName .htaccess/#AccessFileName .htaccess/" /etc/apache2/apache2.conf
# Decrease timeout to blunt DoS and SlowLoris attacks
sudo sed -i.bak2 -e "s/^Timeout [[:digit:]]\+/Timeout 60/" /etc/apache2/apache2.conf
# Set a limit on the client request body size in bytes to reduce DoS attacks
#  This sed is kinda tricky the comma ',' is a line address range set by the 
#   two regex between /regex/,/regex/{command} The brackets then
#  give the command to execute for each line in teh address range
#  In this case it appends LimitRequestBody to the block as it doesnt pre-exist  
sudo sed -i.bak3 '/<Directory \/var\/www\/>/,/<\/Directory>/{s/<\/Directory>/         LimitRequestBody 990000\n<\/Directory>/g;}' /etc/apache2/apache2.conf
# another request time limit and byte rate limiter using mod_reqtimeout
echo RequestReadTimeout header=10-20,MinRate=500 body=20,MinRate=500 | sudo tee -a /etc/apache2/apache2.conf
# Put in LimitExcept to only allow GET POST and OPTIONS requests deny others
# https://askubuntu.com/questions/549556/apache-and-limitexcept
sudo sed -i.bak4 '/<Directory \/var\/www\/>/,/<\/Directory>/{s/<\/Directory>/    <LimitExcept GET POST OPTIONS>\n       Require all denied\n     <\/LimitExcept>\n<\/Directory>/g;}' /etc/apache2/apache2.conf


# restart apache service
sudo systemctl restart apache2
echo 'Starting modsecurity install'
# Start the modsecurity install
sudo -E apt -y install libapache2-mod-security2
# enable module
sudo a2enmod security2
# restart
sudo systemctl restart apache2
# configure modsecurity
sudo cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf
sudo sed -i.bak0 -e "s/SecRuleEngine DetectionOnly/SecRuleEngine On/" /etc/modsecurity/modsecurity.conf
sudo sed -i.bak1 -e "s/SecAuditLogParts ABDEFHIJZ/SecAuditLogParts ABDEFHJKZ/" /etc/modsecurity/modsecurity.conf
# There appears to be a version coreruleset-3.3.2 under
# /etc/modsecurity/crs and /usr/share/modsecurity-crs/ already working
#  these get loaded via /etc/apache2/mods-available/security2.conf
#  Thus, unless one wants to do a custom rule thing it doesn't seem necessary to download from
#  the github coreruleset and install other rules as most instructions indicate to do

echo "starting mod-evasive install"
sudo -E apt -y install apache2-utils
sudo -E apt -y install libapache2-mod-evasive
# It appears to already be configured at /etc/apache2/mods-available/evasive.conf

# Final cleanup and restart
sudo chown -R www-data:www-data /etc/apache2
# all files only user and group readable
# problematic for ubuntu user to view files for debugging
#sudo chmod -R 750 /etc/apache2
sudo systemctl restart apache2
