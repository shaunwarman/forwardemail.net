#!/bin/bash

# How to install
# curl -sSL https://raw.githubusercontent.com/forwardemail.net/forwardemail.net/master/self-hosting/setup.sh | bash
# curl -sSL https://raw.githubusercontent.com/shaunwarman/forwardemail.net/feat/self-hosted-mvp/self-hosting/setup.sh | bash
# bash <(curl -fsSL setup.myselfhosted.email)

# check for spam on the IP first
# https://www.abuseipdb.com/check/<ip>
# https://www.spamrats.com/lookup.php?ip=<ip>
# https://check.spamhaus.org/results/?query=<ip>

# TODO: one click marketplaces
# https://docs.vultr.com/vultr-marketplace#6.-create-the-application-instructions
# https://marketplace.digitalocean.com/vendors/guidelines-resources
# https://github.com/digitalocean/marketplace-partners

# TODO: cloud config works for most cloud providers, creates a simple way to inject context, set variables for the user
# ... this will be even easier for vendor marketplace apps as the user can defined variables that are injected here as well
#cloud-config
# write_files:
#  - path: /root/cloudflare.ini
#    content: |
#      dns_cloudflare_email = "your-email@example.com"
#      dns_cloudflare_api_key = "your-cloudflare-global-api-key"
#    owner: root:root
#    permissions: '0600'
#  - path: /etc/profile.d/marketplace.sh
#    content: |
#      export MARKETPLACE_DEPLOYMENT="true"
#      export PROVIDER="digitalocean"

# runcmd:
#   - chmod +x /etc/profile.d/marketplace.sh

set -e          # Exit immediately if a command exits with a non-zero status
set -o pipefail # Exit if any command in a pipeline fails

DEBUG=${DEBUG:-false}

REPO_FOLDER_NAME="forwardemail.net"
REPO_URL="https://github.com/shaunwarman/forwardemail.net.git"

MONGODB_DB_BACKUPS_DIR="mongo-backups"
REDIS_DB_BACKUPS_DIR="redis-backups"
SQLITE_DB_DIR="sqlite-data"

ENV_FILE_DEFAULTS=".env.defaults"
ENV_FILE_SCHEMA=".env.schema"
ENV_FILE=".env"

ROOT_DIR="/$(pwd)/$REPO_FOLDER_NAME"

run_cmd() {
  if [[ "$DEBUG" == "true" ]]; then
    echo "+ $*" # Print the command (optional for debugging)
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

run_silent() {
  if [[ "$DEBUG" == "true" ]]; then
    "$@" # Run the command with output shown
  else
    "$@" >/dev/null 2>&1 || echo "Command failed: $*"
  fi
}

# Prompt user to confirm setup
prompt_command() {
  echo "Please select an option:"
  echo "1. Initial setup"
  echo "2. Backup"
  echo "3. Upgrade"
  echo "4. Renew certificates"
  echo "5. Restore from backup"
  echo "6. Help"
  echo "7. Exit"
  echo -n "Enter your choice [1-7]: " >/dev/tty
  read -r choice </dev/tty

  case $choice in
  1)
    echo "Running Initial setup..."
    initial_setup
    ;;
  2)
    read -rp "Backup support currently requires an S3-compatible storage provider. Do you want to continue? (yes/no): " choice

    # Convert input to lowercase to handle YES, Yes, yEs, etc.
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    if [[ "$choice" == "yes" || "$choice" == "y" ]]; then
      read -rp "What is the S3 ACCESS KEY ID?: " AWS_ACCESS_KEY_ID
      export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
      update_env_file AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"

      read -rp "What is the S3 SECRET ACCESS KEY?: " AWS_SECRET_ACCESS_KEY
      export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
      update_env_file AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"

      read -rp "Will you be using AWS S3 directly? (yes/no): " isAwsS3
      isAwsS3=$(echo "$isAwsS3" | tr '[:upper:]' '[:lower:]')
      if [[ "$isAwsS3" == "no" || "$isAwsS3" == "n" ]]; then
        read -rp "What is the S3 endpoint URL?: " AWS_ENDPOINT_URL
        export AWS_ENDPOINT_URL="$AWS_ENDPOINT_URL"
        update_env_file AWS_ENDPOINT_URL "$AWS_ENDPOINT_URL"
      fi

      set_aws_credentials

      chmod +x "$HOME"/forwardemail.net/self-hosting/scripts/backup-mongo.sh
      chmod +x "$HOME"/forwardemail.net/self-hosting/scripts/backup-redis.sh

      MONGO_BACKUP_CRON="0 0 * * * $HOME/forwardemail.net/self-hosting/scripts/backup-mongo.sh >> /var/log/mongo-backup.log 2>&1"
      (crontab -l 2>/dev/null | grep -Fq "$MONGO_BACKUP_CRON") || (
        crontab -l 2>/dev/null
        echo "$CRON_JOB"
      ) | crontab -
      REDIS_BACKUP_CRON="0 0 * * * $HOME/forwardemail.net/self-hosting/scripts/backup-redis.sh >> /var/log/redis-backup.log 2>&1"
      (crontab -l 2>/dev/null | grep -Fq "$REDIS_BACKUP_CRON") || (
        crontab -l 2>/dev/null
        echo "$CRON_JOB"
      ) | crontab -

    else
      echo "You choose not to continue. Skipping backup setup."
    fi

    echo "Backup setup complete. Please be sure to save your .env file in a safe place in the event of a restore from backup."

    ;;
  3)
    echo "Upgrading to latest code..."
    clone_repo

    echo "Taking down infrastructure..."
    docker-compose -f docker-compose-self-hosted.yml down

    echo "Building re-usable docker image..."
    docker builder build -t self-hosted/forwardemail.net:latest .

    echo "Spinning up infrastructure..."
    docker-compose -f docker-compose-self-hosted.yml up -d
    echo "✅ Upgrade complete..."
    ;;
  4)
    echo "Renewing certificates..."
    renew_certificates
    ;;
  5)
    # TODO: add larger message about whats about to happen and prompt to continue y/n
    echo "Restore from backup..."

    ENV_FILE="/$(pwd)/.env"

    if [ ! -e "$ENV_FILE" ]; then
      echo "$ENV_FILE does not exist. Add .env and retry."
      exit 1
    fi

    export_from_env_file AWS_ACCESS_KEY_ID
    export_from_env_file AWS_SECRET_ACCESS_KEY
    export_from_env_file AWS_ENDPOINT_URL
    export_from_env_file DOMAIN

    set_aws_credentials

    update_dns_resolvers
    install_dependencies
    setup_firewall
    clone_repo

    cp "$ENV_FILE" "$ROOT_DIR"/.env

    docker-compose -f docker-compose-self-hosted.yml down

    remove_from_schema
    generate_certificates
    update_ssl_paths

    # this is a workaround for the build, will set after
    update_env_file "DKIM_PRIVATE_KEY_PATH" ""

    echo "Building re-usable docker image, this may take a while..."
    docker builder build -t self-hosted/forwardemail.net:latest .

    openssl genrsa -f4 -out "$ROOT_DIR/ssl/dkim.key" 2048
    update_env_file "DKIM_PRIVATE_KEY_PATH" "/app/ssl/dkim.key"

    # TODO this could be cleaner
    cp "$ENV_FILE" "$ROOT_DIR"/.env

    # restore redis
    LATEST_REDIS_BACKUP=$(aws s3api list-objects-v2 --bucket forwardemail-selfhosted --prefix redis-backups/ \
      --query 'Contents | sort_by(@, &LastModified) | [-1].Key' --output text)
    aws s3 cp s3://forwardemail-selfhosted/"$LATEST_REDIS_BACKUP" /tmp/dump.rdb
    mv /tmp/dump.rdb "$ROOT_DIR"/redis-data/dump.rdb

    # restore mongo
    LATEST_MONGO_BACKUP=$(aws s3api list-objects-v2 --bucket forwardemail-selfhosted --prefix mongo-backups/ \
      --query 'Contents | sort_by(@, &LastModified) | [-1].Key' --output text)
    aws s3 cp s3://forwardemail-selfhosted/"$LATEST_MONGO_BACKUP" /tmp/mongo-backup.tgz
    tar -xzf /tmp/mongo-backup.tgz -C "$ROOT_DIR"/mongo-backups/
    LATEST_MONGO_BACKUP_PATH=$(basename "$LATEST_MONGO_BACKUP" .tgz)

    # restore sqlite
    LATEST_SQLITE_BACKUP=$(aws s3api list-objects-v2 --bucket production-sqlite-storage \
      --query 'Contents | sort_by(@, &LastModified) | [-1].Key' --output text)
    aws s3 cp s3://production-sqlite-storage/"$LATEST_SQLITE_BACKUP" /tmp/
    mv /tmp/*sqlite* "$HOME"/forwardemail.net/sqlite-data/

    docker-compose -f "$ROOT_DIR"/docker-compose-self-hosted.yml up -d
    docker exec -i mongodb mongorestore --drop --dir /backups/"$LATEST_MONGO_BACKUP_PATH"

    echo "✅ Restore from backup complete..."
    ;;
  6)
    echo "Help:"
    echo "1. Initial setup: Sets up the application for the first time."
    echo "2. Backup: Creates a backup of your data."
    echo "3. Upgrade: Stay up to date with the latest code and security fixes"
    echo "4. Renew certificates: Renews SSL certificates for your domain."
    echo "5. Restore: Backup from a previous point in time"
    echo "6. Help: All commands and related information"
    echo "7. Exit: Exits the script."
    ;;
  7)
    echo "Exiting..."
    ;;
  *)
    echo "Invalid choice. Please select a valid option."
    ;;
  esac
}

export_from_env_file() {
  if ! grep -q "^$1=" "$ENV_FILE"; then
    echo "Error: The following key is missing in $ENV_FILE: $1"
    return 1
  fi

  export "$1"="$(grep "^$1=" "$ENV_FILE" | cut -d'=' -f2-)"
}

install_dependencies() {
  echo "Installing dependencies..."
  # Update package list and install dependencies
  # NOTE: should we pipe all this to > /dev/null 2>&1
  # curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  apt-get update -y -q
  apt-get install -y -q \
    ca-certificates \
    curl \
    gnupg \
    git \
    openssl \
    certbot \
    docker-compose

  # ubuntu 24 doesn't have awscli
  # https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
  snap install aws-cli --classic

  # Add Docker’s official GPG key
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # Add Docker repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list

  # Update package index and install Docker
  apt-get update -y -q
  apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Verify installation
  docker --version
}

# Function to check if Docker is running
check_docker_running() {
  if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Attempting to start it."
    systemctl unmask docker
    systemctl enable docker
    systemctl start docker
    if ! docker info >/dev/null 2>&1; then
      echo "Docker issues with systemctl, using dockerd directly..."
      nohup dockerd >/dev/null 2>/dev/null &
    fi
  else
    echo "✅ Docker is running."
  fi
}

set_aws_credentials() {
  mkdir -p ~/.aws

  cat >~/.aws/credentials <<EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF

  cat >~/.aws/config <<EOF
[default]
region = auto
output = json
EOF

  if [[ -n $AWS_ENDPOINT_URL ]]; then
    echo "endpoint_url = $AWS_ENDPOINT_URL" >>~/.aws/config
  fi
}

update_dns_resolvers() {
  echo "Updating system to use Cloudflare DNS"

  # lots of issues with local resolvers for some cloud providers, so use cloudflare by default
  # this directly affects certbot setup and acme-challenge txt record checks
  echo "nameserver 1.1.1.1" | tee /etc/resolv.conf
  if systemctl is-active --quiet systemd-resolved; then
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
    systemctl mask systemd-resolved
  fi

  echo "DNS update complete!"
}

update_env_file() {
  local key="$1"
  local value="$2"

  local sed_flag="-i"
  # if [[ "$(uname)" == "Darwin" ]]; then
  #   sed_flag="-i ''"
  # else
  #   sed_flag="-i"
  # fi

  # Check if the key exists in the file
  if grep -qE "^${key}=" "$ROOT_DIR/$ENV_FILE"; then
    sed $sed_flag -E "s|^${key}=.*|${key}=${value}|" "$ROOT_DIR/$ENV_FILE"
  else
    echo "${key}=${value}" >>"$ROOT_DIR/$ENV_FILE"
  fi
}

update_default_env() {
  update_env_file NODE_ENV production
  update_env_file HTTP_PROTOCOL https
  update_env_file SQLITE_HOST sqlite.{{DOMAIN}}
  update_env_file WEB_HOST {{DOMAIN}}
  update_env_file WEB_PORT 443
  update_env_file CALDAV_HOST caldav.{{DOMAIN}}
  update_env_file API_HOST api.{{DOMAIN}}
  update_env_file APP_NAME {{DOMAIN}}
  update_env_file TRANSPORT_DEBUG true
  update_env_file SEND_EMAIL true
  update_env_file PREVIEW_EMAIL false
  update_env_file MONGO_HOST 127.0.0.1
  update_env_file LOGS_MONGO_HOST 127.0.0.1
  update_env_file JOURNALS_MONGO_HOST 127.0.0.1
  update_env_file EMAILS_MONGO_HOST 127.0.0.1
  update_env_file REDIS_HOST 127.0.0.1
  update_env_file TURNSTILE_ENABLED false
  update_env_file MX_PORT 25
  update_env_file SQLITE_STORAGE_PATH sqlite_storage
  update_env_file SMTP_TRANSPORT_PASS "Thisisapassword123"
  update_env_file SMTP_HOST smtp.{{DOMAIN}}
  update_env_file SMTP_PORT 465
  update_env_file IMAP_HOST imap.{{DOMAIN}}
  update_env_file IMAP_PORT 993
  update_env_file POP3_HOST pop3.{{DOMAIN}}
  update_env_file POP3_PORT 995
  update_env_file MX_HOST mx.{{DOMAIN}}
  update_env_file SMTP_EXCHANGE_DOMAINS mx.{{DOMAIN}}
  update_env_file SELF_HOSTED true
  update_env_file ENABLE_MONITOR_SERVER false
  update_env_file DOMAIN "$DOMAIN"
  update_env_file WEBSITE_URL "$DOMAIN"
  update_env_file CACHE_RESPONSES true
}

update_ssl_paths() {
  # Update SSL paths
  sed -i -E \
    -e 's|^(.*_)?SSL_KEY_PATH=.*|\1SSL_KEY_PATH=/app/ssl/privkey.pem|' \
    -e 's|^(.*_)?SSL_CERT_PATH=.*|\1SSL_CERT_PATH=/app/ssl/fullchain.pem|' \
    -e 's|^(.*_)?SSL_CA_PATH=.*|\1SSL_CA_PATH=/app/ssl/chain.pem|' \
    "$ENV_FILE"
}

remove_from_schema() {
  sed -i -E \
    -e '/^APPLE/d' \
    -e '/^MICROSOFT/d' \
    -e '/^TWILIO/d' \
    -e '/^PAYPAL/d' \
    -e '/^STRIPE/d' \
    "$ENV_FILE_SCHEMA"
}

# Validate a domain name
validate_domain() {
  [[ "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

# Generate SSL certificates and DKIM key
generate_certificates() {
  echo "Generating SSL certificates for *.$DOMAIN"

  rm -rf /etc/letsencrypt/live/"$DOMAIN"*/*
  mkdir -p "$ROOT_DIR/ssl"

  # https://toolbox.googleapps.com/apps/dig/#TXT/_acme-challenge.$DOMAIN

  # let's encrypt doesn't need an email because htey don't send renewal notices anymore
  # https://letsencrypt.org/2025/01/22/ending-expiration-emails/
  if [[ "$MARKETPLACE_DEPLOYMENT" == "true" ]]; then
    certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.cloudflare.ini \ -d "$DOMAIN" -d "*.$DOMAIN" --non-interactive --agree-tos --email "$EMAIL"  
  else
    certbot certonly --manual --agree-tos --preferred-challenges dns -d "*.$DOMAIN" -d "$DOMAIN" </dev/tty >/dev/tty 2>&1
  fi

  # https://certbot-dns-cloudflare.readthedocs.io/en/stable/
  # /root/cloudflare.ini
  # dns_cloudflare_email = "your-email@example.com"
  # dns_cloudflare_api_key = "your-cloudflare-global-api-key"
  # certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.cloudflare.ini \ -d "$DOMAIN" -d "*.$DOMAIN" --non-interactive --agree-tos --email admin@example.com

  cp /etc/letsencrypt/live/"$DOMAIN"*/* "$ROOT_DIR/ssl"
}

renew_certificates() {
  input_custom_domain

  # TODO: should we check expiration of current certs?
  # /etc/letsencrypt/live/$domain*/*

  certbot certonly --manual --agree-tos --preferred-challenges dns -d "*.$DOMAIN" -d "$DOMAIN" </dev/tty >/dev/tty 2>&1

  cp /etc/letsencrypt/live/"$DOMAIN"*/* "$ROOT_DIR/ssl"
}

# Generate various encryption keys
generate_encryption_keys() {
  echo "Generating encryption keys and secrets"

  helper_encryption_key=$(openssl rand -base64 32 | tr -d /=+ | cut -c -32)
  update_env_file "HELPER_ENCRYPTION_KEY" "$helper_encryption_key"

  srs_secret=$(openssl rand -base64 32 | tr -d /=+ | cut -c -32)
  update_env_file "SRS_SECRET" "$srs_secret"

  txt_encryption_key=$(openssl rand -hex 16)
  update_env_file "TXT_ENCRYPTION_KEY" "$txt_encryption_key"

  echo "Helper and SRS encryption keys generated"
}

clone_repo() {
  echo "Cloning forward email codebase..."
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Already inside the repository. Pulling latest changes..."
    git pull origin master
  elif [ -d "$ROOT_DIR" ]; then
    echo "Repository already cloned. Pulling latest changes..."
    cd "$ROOT_DIR" && git pull origin master
  else
    echo "Cloning repository from $REPO_URL..."
    git clone "$REPO_URL"
    cd "$ROOT_DIR"
    git checkout -b feat/self-hosted-mvp origin/feat/self-hosted-mvp
  fi
}

setup_firewall() {
  ufw default deny incoming >/dev/null 2>&1

  PORTS=(22 25 80 443 465 587 993 995 2993 2995 3456 4000 5000)

  for port in "${PORTS[@]}"; do
    ufw allow "${port}/tcp" >/dev/null 2>&1
  done

  ufw allow from 127.0.0.1 to any port 27017 >/dev/null 2>&1
  ufw allow from 127.0.0.1 to any port 6379 >/dev/null 2>&1

  echo "y" | ufw enable >/dev/null 2>&1
  ufw status
}

create_db_directories() {
  mkdir -p "$ROOT_DIR/$SQLITE_DB_DIR"
  mkdir -p "$ROOT_DIR/$MONGODB_DB_BACKUPS_DIR"
  mkdir -p "$ROOT_DIR/$REDIS_DB_BACKUPS_DIR"
}

input_custom_domain() {
  while true; do
    read -rp "Enter the domain name you are setting up (e.g. example.com): " DOMAIN </dev/tty
    if validate_domain "$DOMAIN"; then
      echo "✅ Domain name is valid."
      break
    else
      echo "❌ Invalid domain name. Please enter a valid one."
    fi
  done
}

input_user_pass() {
  echo "Let's create a username and password for the initial user."
  while true; do
    read -rp "Enter a username for the initial login " username </dev/tty
    if [[ -n "$username" ]]; then
      echo "✅ Username is valid."
      break
    else
      echo "❌ Invalid Username. Please enter a valid one."
    fi
  done
  while true; do
    read -rp "Enter a password for the initial login " password </dev/tty
    if [[ -n "$password" ]]; then
      echo "✅ Password is valid."
      break
    else
      echo "❌ Invalid Password. Please enter a valid one."
    fi
  done
}

initial_setup() {
  update_dns_resolvers
  run_silent install_dependencies
  setup_firewall
  clone_repo

  if [[ -f "$ENV_FILE" ]]; then
    mv "$ENV_FILE" ".env.bak"
    echo "Moving existing env file '$ENV_FILE' to .env.bak."
  fi

  cp "$ENV_FILE_DEFAULTS" "$ENV_FILE"

  check_docker_running

  input_custom_domain
  remove_from_schema
  update_default_env
  input_user_pass
  update_env_file "AUTH_BASIC_USERNAME" "$username"
  update_env_file "AUTH_BASIC_PASSWORD" "$password"

  generate_certificates
  generate_encryption_keys
  update_ssl_paths

  # export env vars needed for docker compose file template strings
  export SQLITE_STORAGE_PATH="sqlite_storage" # TODO: needs to be dynamic or come from env?

  create_db_directories

  # take down any previous setup
  docker-compose -f docker-compose-self-hosted.yml down

  echo "Building re-usable docker image..."
  docker builder build -t self-hosted/forwardemail.net:latest .

  openssl genrsa -f4 -out "$ROOT_DIR/ssl/dkim.key" 2048
  update_env_file "DKIM_PRIVATE_KEY_PATH" "/app/ssl/dkim.key"

  echo "Spinning up necessary infrastructure..."
  docker-compose -f docker-compose-self-hosted.yml up -d

  echo "✅ Setup completed successfully!"

  echo "Follow the rest of the guide for DNS configuration..."
}

prompt_command
