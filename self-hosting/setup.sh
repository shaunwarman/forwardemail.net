#!/bin/bash

# How to install
# curl -sSL https://raw.githubusercontent.com/forwardemail.net/forwardemail.net/master/self-hosting/setup.sh | bash
# curl -sSL https://raw.githubusercontent.com/shaunwarman/forwardemail.net/feat/self-hosted-mvp/self-hosting/setup.sh | bash

set -e          # Exit immediately if a command exits with a non-zero status
set -o pipefail # Exit if any command in a pipeline fails

REPO_FOLDER_NAME="forwardemail.net"
REPO_URL="https://github.com/shaunwarman/forwardemail.net.git"

MONGODB_DB_BACKUPS_DIR="mongo-backups"
REDIS_DB_BACKUPS_DIR="redis-backups"
SQLITE_DB_DIR="sqlite-data"

ENV_FILE_DEFAULTS=".env.defaults"
ENV_FILE_SCHEMA=".env.schema"
ENV_FILE=".env"

ROOT_DIR="/$(whoami)/$REPO_FOLDER_NAME"

# Prompt user to confirm setup
prompt_command() {
  echo "Please select an option:"
  echo "1. Initial setup"
  echo "2. Backup"
  echo "3. Upgrade"
  echo "4. Renew certificates"
  echo "5. Restore (from backup)"
  echo "6. Help"
  echo "7. Exit"
  echo -n "Enter your choice [1-7]: " >/dev/tty
  read choice </dev/tty

  case $choice in
  1)
    echo "Running Initial setup..."
    initial_setup
    ;;
  2)
    echo "Running Backups one time backup of mongodb, redis and sqlite..."
    BACKUP_DIR="/backups"
    TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
    MONGO_DUMP_PATH="$BACKUP_DIR/mongo_backup_$TIMESTAMP"
    REDIS_DUMP_PATH="$BACKUP_DIR/redis_backup_$TIMESTAMP"

    # mongo backup
    docker exec mongodb mkdir -p "$MONGO_DUMP_PATH"
    docker exec mongodb mongodump --out="$MONGO_DUMP_PATH"
    echo "Mongo backup available at: $MONGODB_DB_BACKUPS_DIR"

    # redis backup
    docker exec redis mkdir -p "$REDIS_DUMP_PATH"
    docker exec redis redis-cli CONFIG SET dir "$REDIS_DUMP_PATH" && redis-cli BGSAVE
    echo "Redis backup available at: $REDIS_DB_BACKUPS_DIR"

    # sqlite backup
    tar cvf $ROOT_DIR/$SQLITE_DB_DIR sqlite_backup_$TIMESTAMP.tgz
    echo "SQLite backup available at: $ROOT_DIR/$SQLITE_DB_DIR"
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
    echo "Restore from backup..."
    latest_backup=$(ls -td $ROOT_DIR/$MONGODB_DB_BACKUPS_DIR/mongo_backup_* 2>/dev/null | head -n 1)
    # TODO: if none exist, log warning and skip
    docker exec mongodb mongorestore --dir="$BACKUP_DIR"
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

install_dependencies() {
  echo "Installing dependencies..."
  # Update package list and install dependencies
  # NOTE: should we pipe all this to > /dev/null 2>&1
  # curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get update -y -q > /dev/null 2>&1
  sudo apt-get install -y -q \
    ca-certificates \
    curl \
    gnupg \
    git \
    openssl \
    certbot \
    docker-compose > /dev/null 2>&1
    # nodejs


  # Add Docker’s official GPG key
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Add Docker repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  # Update package index and install Docker
  sudo apt-get update -y -q > /dev/null 2>&1
  sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1

  # Verify installation
  docker --version
}

# Function to check if Docker is running
check_docker_running() {
  if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Attempting to start it."
    systemctl unmask docker
    systemctl enable docker
    if ! docker info >/dev/null 2>&1; then
      echo "Docker issues with systemctl, using dockerd directly..."
      nohup dockerd > /dev/null 2>/dev/null &
    fi
  else
    echo "✅ Docker is running."
  fi
}

update_dns_resolvers() {
  DNS1="1.1.1.1"
  DNS2="1.0.0.1"

  echo "Updating system to use Cloudflare DNS ($DNS1, $DNS2)..."

  # lots of issues with local resolvers for some cloud providers, so use cloudflare by default
  # this directly affects certbot setup and acme-challenge txt record checks
  if systemctl is-active --quiet systemd-resolved; then
      sudo sed -i "s/^#DNS=/DNS=1.1.1.1 1.0.0.1/" /etc/systemd/resolved.conf
      sudo sed -i "s/^#FallbackDNS=/FallbackDNS=8.8.8.8 8.8.4.4/" /etc/systemd/resolved.conf
      ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
      sudo systemctl restart systemd-resolved
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
    echo "Updating $key to $value in $ENV_FILE"
    sed $sed_flag -E "s|^${key}=.*|${key}=${value}|" "$ROOT_DIR/$ENV_FILE"
  else
    echo "Adding $key=$value to $ROOT_DIR/$ENV_FILE"
    echo "${key}=${value}" >>"$ROOT_DIR/$ENV_FILE"
  fi
}

update_default_env() {
  update_env_file NODE_ENV production
  update_env_file HTTP_PROTOCOL https
  update_env_file SQLITE_HOST sqlite.{{DOMAIN}}
  update_env_file WEB_HOST {{DOMAIN}}
  update_env_file CALDAV_HOST caldav.{{DOMAIN}}
  update_env_file API_HOST api.{{DOMAIN}}
  update_env_file APP_NAME {{DOMAIN}}
  update_env_file TRANSPORT_DEBUG true
  update_env_file SEND_EMAIL true
  update_env_file PREVIEW_EMAIL false
  update_env_file MONGO_HOST mongodb.{{DOMAIN}}
  update_env_file LOGS_MONGO_HOST mongodb.{{DOMAIN}}
  update_env_file JOURNALS_MONGO_HOST mongodb.{{DOMAIN}}
  update_env_file EMAILS_MONGO_HOST mongodb.{{DOMAIN}}
  update_env_file REDIS_HOST redis.{{DOMAIN}}
  update_env_file TURNSTILE_ENABLED false
  update_env_file MX_PORT 25
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
  update_env_file DOMAIN $domain
  update_env_file WEBSITE_URL $domain
  update_env_file REDIS_S3_BACKUPS_ENABLED true
  update_env_file REDIS_S3_BACKUP_BUCKET redis-database-backups
  update_env_file REDIS_S3_BACKUPS_DIR "/data"
  update_env_file MONGO_S3_BACKUPS_ENABLED true
  update_env_file MONGO_S3_BACKUP_BUCKET mongo-database-backups
  update_env_file MONGO_S3_BACKUPS_DIR "/data/db"
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
  echo "Generating SSL certificates for *.$domain"

  rm -rf /etc/letsencrypt/live/$domain*/*
  mkdir -p "$ROOT_DIR/ssl"

  # https://toolbox.googleapps.com/apps/dig/#TXT/_acme-challenge.$DOMAIN

  # let's encrypt doesn't need an email because htey don't send renewal notices anymore
  # https://letsencrypt.org/2025/01/22/ending-expiration-emails/
  certbot certonly --manual --agree-tos --preferred-challenges dns -d "*.$domain" -d "$domain" </dev/tty >/dev/tty 2>&1

  cp /etc/letsencrypt/live/$domain*/* "$ROOT_DIR/ssl"
}

renew_certificates() {
  input_custom_domain

  # TODO: should we check expiration of current certs?
  # /etc/letsencrypt/live/$domain*/*

  certbot certonly --manual --agree-tos --preferred-challenges dns -d "*.$domain" -d "$domain" </dev/tty >/dev/tty 2>&1

  cp /etc/letsencrypt/live/$domain*/* "$ROOT_DIR/ssl"
}

# Generate various encryption keys
generate_encryption_keys() {
  echo "Generating encryption keys and secrets"

  helper_encryption_key=$(openssl rand -base64 32 | tr -d /=+ | cut -c -32)
  update_env_file "HELPER_ENCRYPTION_KEY" $helper_encryption_key

  srs_secret=$(openssl rand -base64 32 | tr -d /=+ | cut -c -32)
  update_env_file "SRS_SECRET" $srs_secret

  txt_encryption_key=$(openssl rand -hex 16)
  update_env_file "TXT_ENCRYPTION_KEY" $txt_encryption_key

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
    cd $ROOT_DIR
    git checkout -b feat/self-hosted-mvp origin/feat/self-hosted-mvp
  fi
}

create_db_directories() {
  mkdir -p "$ROOT_DIR/$SQLITE_DB_DIR"
  mkdir -p "$ROOT_DIR/$MONGODB_DB_BACKUPS_DIR"
  mkdir -p "$ROOT_DIR/$REDIS_DB_BACKUPS_DIR"
}

input_custom_domain() {
  while true; do
    read -rp "Enter the domain name you are setting up (e.g. example.com): " domain </dev/tty
    if validate_domain "$domain"; then
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
  install_dependencies
  clone_repo

  if [[ -f "$ENV_FILE" ]]; then
    mv "$ENV_FILE" ".env.bak"
    echo "Moving existing env file '$ENV_FILE' to .env.bak."
  fi

  cp "$ENV_FILE_DEFAULTS" "$ENV_FILE"

  check_docker_running

  input_custom_domain
  input_user_pass
  update_env_file "AUTH_BASIC_USERNAME" "$username"
  update_env_file "AUTH_BASIC_PASSWORD" "$password"

  remove_from_schema
  update_default_env

  generate_certificates
  generate_encryption_keys
  update_ssl_paths

  # export env vars needed for docker compose file template strings
  export DOMAIN=$domain
  export SQLITE_STORAGE_PATH="sqlite_storage" # TODO: needs to be dynamic or come from env?

  create_db_directories

  echo "Building re-usable docker image..."
  docker builder build -t self-hosted/forwardemail.net:latest .

  openssl genrsa -f4 -out "$ROOT_DIR/ssl/dkim.key" 2048
  update_env_file "DKIM_PRIVATE_KEY_PATH" "/app/ssl/dkim.key"

  # take down any previous setup
  docker-compose -f docker-compose-self-hosted.yml down

  echo "Spinning up necessary infrastructure..."
  sudo docker-compose -f docker-compose-self-hosted.yml up -d

  echo "✅ Setup completed successfully!"

  echo "Follow the rest of the guide for DNS configuration..."
}

prompt_command
