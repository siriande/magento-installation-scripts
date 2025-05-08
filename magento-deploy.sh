#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Set non-interactive mode to suppress debconf warnings
export DEBIAN_FRONTEND=noninteractive

# Log file
LOG_FILE="magento-deployment.log"

# Redirect stdout and stderr to log file
exec > >(tee -a $LOG_FILE) 2>&1

# Validate required arguments
if [ "$#" -lt 31 ]; then
  echo "Error: Missing required arguments."
  echo "Usage: $0 <AZURE_SUBSCRIPTION_ID> <RESOURCE_GROUP> <APP_SERVICE_NAME> <VM_NAME> <COMPOSER_USERNAME> <COMPOSER_PASSWORD> <ADMIN_USER> <ADMIN_PASSWORD> <ADMIN_EMAIL> <ADMIN_FIRSTNAME> <ADMIN_LASTNAME> <DB_HOST> <DB_NAME> <DB_USER> <DB_PASSWORD> <REDIS_HOST> <REDIS_PORT> <REDIS_PASSWORD> <ELASTICSEARCH_HOST> <ELASTICSEARCH_PORT> <ENABLE_ELASTICSEARCH_AUTH> <ELASTICSEARCH_USER> <ELASTICSEARCH_PASSWORD> <BASE_URL> <BASE_URL_SECURE> <USE_SECURE> <USE_SECURE_ADMIN> <BACKEND_FRONTNAME> <MAGENTO_LANGUAGE_CODE> <MAGENTO_TIMEZONE> <MAGENTO_CURRENCY> <USE_REWRITES>"
  exit 1
fi

# Variables

AZURE_SUBSCRIPTION_ID=$1
RESOURCE_GROUP=$2
APP_SERVICE_NAME=$3
VM_NAME=$4
COMPOSER_USERNAME=$5
COMPOSER_PASSWORD=$6
ADMIN_USER=$7
ADMIN_PASSWORD=$8
ADMIN_EMAIL=$9
ADMIN_FIRSTNAME=${10}
ADMIN_LASTNAME=${11}
DB_HOST=${12}
DB_NAME=${13}
DB_USER=${14}
DB_PASSWORD=${15}
REDIS_HOST=${16}
REDIS_PORT=${17}
REDIS_PASSWORD=${18}
ELASTICSEARCH_HOST=${19}
ELASTICSEARCH_PORT=${20}
ENABLE_ELASTICSEARCH_AUTH=${21}
ELASTICSEARCH_USER=${22}
ELASTICSEARCH_PASSWORD=${23}
BASE_URL=${24}
BASE_URL_SECURE=${25}
USE_SECURE=${26}
USE_SECURE_ADMIN=${27}
BACKEND_FRONTNAME=${28}
MAGENTO_LANGUAGE_CODE=${29}
MAGENTO_TIMEZONE=${30}
MAGENTO_CURRENCY=${31}
USE_REWRITES=${32}
ENABLE_DEBUG_LOGGING=true
ENABLE_SYSLOG_LOGGING=true
ZIP_FILE="magento-demo-package.zip"

# Update and install dependencies
echo "Updating and installing dependencies..."
sudo apt update && sudo apt upgrade -y 
sudo apt install -y build-essential libpcre3 libpcre3-dev zlib1g libssl-dev zlib1g-dev zip unzip curl


#Install PHP
echo "Installing PHP..."
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update
sudo apt install -y php8.4 php8.4-cli php8.4-mysql php8.4-curl php8.4-xml php8.4-mbstring php8.4-zip php8.4-bcmath php8.4-soap php8.4-intl php8.4-readline php8.4-gd

# Install Composer
if ! command -v composer &> /dev/null; then
    curl -sS https://getcomposer.org/installer | php
    sudo mv composer.phar /usr/local/bin/composer
fi

# Set Composer authentication
echo "Configuring Composer authentication..."
composer global config http-basic.repo.magento.com "$COMPOSER_USERNAME" "$COMPOSER_PASSWORD"

# Create Magento project
echo "Creating Magento project..."
sudo mkdir -p /var/www/magento
sudo chown -R $USER:www-data /var/www/magento
cd /var/www/magento
composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition .

# Install Magento (use environment variables for sensitive data)
echo "Installing Magento..."
sudo php bin/magento setup:install \
  --enable-debug-logging=$ENABLE_DEBUG_LOGGING \
  --enable-syslog-logging=$ENABLE_SYSLOG_LOGGING \
  --backend-frontname=$BACKEND_FRONTNAME \
  --db-host=$DB_HOST \
  --db-name=$DB_NAME \
  --db-user=$DB_USER \
  --db-password=$DB_PASSWORD \
  --session-save=redis \
  --session-save-redis-host=$REDIS_HOST \
  --session-save-redis-port=$REDIS_PORT \
  --session-save-redis-password=$REDIS_PASSWORD \
  --cache-backend=redis \
  --cache-backend-redis-server=$REDIS_HOST \
  --cache-backend-redis-port=$REDIS_PORT \
  --cache-backend-redis-password=$REDIS_PASSWORD \
  --page-cache=redis \
  --page-cache-redis-server=$REDIS_HOST \
  --page-cache-redis-port=$REDIS_PORT \
  --page-cache-redis-password=$REDIS_PASSWORD \
  --base-url=$BASE_URL \
  --language=$MAGENTO_LANGUAGE_CODE \
  --timezone=$MAGENTO_TIMEZONE \
  --currency=$MAGENTO_CURRENCY \
  --use-rewrites=$USE_REWRITES \
  --use-secure=$USE_SECURE \
  --base-url-secure=$BASE_URL_SECURE \
  --use-secure-admin=$USE_SECURE_ADMIN \
  --admin-user=$ADMIN_USER \
  --admin-password=$ADMIN_PASSWORD \
  --admin-email=$ADMIN_EMAIL \
  --admin-firstname=$ADMIN_FIRSTNAME \
  --admin-lastname=$ADMIN_LASTNAME \
  --search-engine=elasticsearch8 \
  --elasticsearch-host=$ELASTICSEARCH_HOST \
  --elasticsearch-port=$ELASTICSEARCH_PORT \
  --elasticsearch-enable-auth=$ENABLE_ELASTICSEARCH_AUTH \
  --elasticsearch-username=$ELASTICSEARCH_USER \
  --elasticsearch-password=$ELASTICSEARCH_PASSWORD

# Install Magento cron jobs
echo "Installing Magento cron jobs..."
sudo php bin/magento cron:install
sudo php bin/magento cron:run

# Run Magento setup commands
echo "Running Magento setup commands..."
sudo php bin/magento setup:upgrade
sudo php bin/magento setup:di:compile

# Create zip
cd /var/www/magento
zip -r $ZIP_FILE .

# Validate Azure CLI installation
echo "Validating Azure CLI installation..."
if ! command -v az &> /dev/null; then
  echo "Azure CLI not found. Installing Azure CLI..."
  curl -sL https://aka.ms/InstallAzureCLIDeb | bash
fi

# Validate Redis and Elasticsearch connectivity
echo "Validating Redis and Elasticsearch connectivity..."
if ! nc -z $REDIS_HOST $REDIS_PORT; then
  echo "Error: Unable to connect to Redis at $REDIS_HOST:$REDIS_PORT"
  exit 1
fi
if ! nc -z $ELASTICSEARCH_HOST $ELASTICSEARCH_PORT; then
  echo "Error: Unable to connect to Elasticsearch at $ELASTICSEARCH_HOST:$ELASTICSEARCH_PORT"
  exit 1
fi

# Deploy the zip file to the existing App Service
echo "Logging in to Azure..."
sudo az login --identity
echo "Setting the Azure subscription..."
sudo az account set --subscription "$AZURE_SUBSCRIPTION_ID"
sudo az webapp deploy \
  --resource-group $RESOURCE_GROUP \
  --name $APP_SERVICE_NAME \
  --src $ZIP_FILE

# Clean up (optional)
rm $ZIP_FILE

echo "Magento app deployed successfully to $APP_SERVICE_NAME."

# Ensure the log file is accessible
chmod 644 $LOG_FILE
echo "Log file can be found at: $LOG_FILE"

# Ensure VM deletion does not interfere with deployment
echo "Scheduling VM deletion in 10 seconds..."
nohup bash -c "sleep 10 && sudo az vm delete --resource-group $RESOURCE_GROUP --name $VM_NAME --yes --no-wait" > /dev/null 2>&1 &
