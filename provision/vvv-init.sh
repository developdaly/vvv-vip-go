#!/usr/bin/env bash
# Provision WordPress Stable

DOMAIN=`get_primary_host "${VVV_SITE_NAME}".test`
DOMAINS=`get_hosts "${DOMAIN}"`
SITE_TITLE=`get_config_value 'site_title' "${DOMAIN}"`
WP_VERSION=`get_config_value 'wp_version' 'latest'`
WP_TYPE=`get_config_value 'wp_type' "single"`
DB_NAME=`get_config_value 'db_name' "${VVV_SITE_NAME}"`
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*-]/}

RED='\e[0;31m'
GREEN='\e[0;32m'
NC='\e[0m' # No Color


echo -e "${GREEN}Commencing $SITE_NAME setup${NC}"


# Add GitHub and GitLab to known_hosts, so we don't get prompted
# to verify the server fingerprint.
# The fingerprints in [this repo]/ssh/known_hosts are generated as follows:
#
# As the starting point for the ssh-keyscan tool, create an ASCII file
# containing all the hosts from which you will create the known hosts
# file, e.g. sshhosts.
# Each line of this file states the name of a host (alias name or TCP/IP
# address) and must be terminated with a carriage return line feed
# (Shift + Enter), e.g.
#
# bitbucket.org
# github.com
# gitlab.com
#
# Execute ssh-keyscan with the following parameters to generate the file:
#
# ssh-keyscan -t rsa,dsa -f ssh_hosts >ssh/known_hosts
# The parameter -t rsa,dsa defines the host’s key type as either rsa
# or dsa.
# The parameter -f /home/user/ssh_hosts states the path of the source
# file ssh_hosts, from which the host names are read.
# The parameter >ssh/known_hosts states the output path of the
# known_host file to be created.
#
# From "Create Known Hosts Files" at:
# http://tmx0009603586.com/help/en/entpradmin/Howto_KHCreate.html
mkdir -p ~/.ssh
touch ~/.ssh/known_hosts
IFS=$'\n'
for KNOWN_HOST in $(cat "ssh/known_hosts"); do
	if ! grep -Fxq "$KNOWN_HOST" ~/.ssh/known_hosts; then
	    echo $KNOWN_HOST >> ~/.ssh/known_hosts
	    echo -e "${GREEN}Success:${NC} Added host to SSH known_hosts for user 'root': $(echo $KNOWN_HOST |cut -d '|' -f1)"
	fi
done


# Make a database, if we don't already have one
echo -e "\nCreating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME}"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO wp@localhost IDENTIFIED BY 'wp';"
echo -e "\n DB operations done.\n\n"

# Nginx Logs
mkdir -p ${VVV_PATH_TO_SITE}/log
touch ${VVV_PATH_TO_SITE}/log/error.log
touch ${VVV_PATH_TO_SITE}/log/access.log

# Install and configure the latest stable version of WordPress
if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-load.php" ]]; then
    echo "Downloading WordPress..."
	noroot wp core download --version="${WP_VERSION}"
fi

if [[ ! -f "${VVV_PATH_TO_SITE}/public_html/wp-config.php" ]]; then
  echo "Configuring WordPress Stable..."
  noroot wp core config --dbname="${DB_NAME}" --dbuser=wp --dbpass=wp --quiet --extra-php <<PHP
define( 'WP_DEBUG', true );
PHP
fi

if ! $(noroot wp core is-installed); then
  echo "Installing WordPress Stable..."

  if [ "${WP_TYPE}" = "subdomain" ]; then
    INSTALL_COMMAND="multisite-install --subdomains"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    INSTALL_COMMAND="multisite-install"
  else
    INSTALL_COMMAND="install"
  fi

  noroot wp core ${INSTALL_COMMAND} --url="${DOMAIN}" --quiet --title="${SITE_TITLE}" --admin_name=admin --admin_email="admin@local.test" --admin_password="password"

  # Add MU plugins in place
  if [ ! -d "${VVV_PATH_TO_SITE}/public_html/wp-content/mu-plugins" ]; then
    git clone --recursive --quiet https://github.com/Automattic/vip-go-mu-plugins.git public_html/wp-content/mu-plugins
    echo -e "${GREEN}Success:${NC} Cloned the VIP Go MU plugins repository"
  fi

  # Everyone gets VIP Scanner
  wp --allow-root plugin install vip-scanner

else
  echo "Updating WordPress Stable..."
  cd ${VVV_PATH_TO_SITE}/public_html
  noroot wp core update --version="${WP_VERSION}"

  echo "wp-config.php already exists for ${SITE_NAME}"
  # Make sure core and VIP Scanner are up to date
  wp --allow-root core update

  if [ wp --allow-root plugin is-installed vip-scanner ]
    wp --allow-root plugin update vip-scanner
  else
    wp --allow-root plugin install vip-scanner
  fi

  (
    cd ${VVV_PATH_TO_SITE}/public_html/wp-content/mu-plugins
    git pull --recurse-submodules
  )

  echo -e "${GREEN}Success:${NC} Updated WordPress, VIP Go MU plugins, and VIP Scanner"

fi


cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
sed -i "s#{{DOMAINS_HERE}}#${DOMAINS}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
