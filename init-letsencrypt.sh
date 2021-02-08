#!/bin/bash

echo "### Check for .env file"
if ! [ -f .env ]; then
  echo "Cannot find .env file. Creating it from .env.example."
  cp .env.example .env
  read -p "Do you want to edit this new .env file ? (y/N) " decision
  if [ "$decision" == "Y" ] || [ "$decision" == "y" ]; then
    exit
  fi
fi

#Read the env file line by line
while IFS='=' read -r var value
  do
    if [[ "$var" == 'EMAIL' ]]; then
      EMAIL=$value
    elif [[ "$var" == 'ENV' ]]; then
      ENV=$value
    elif [[ "$var" == 'VIRTUAL_HOST' ]]; then
      VIRTUAL_HOST=$value
    elif [[ "$var" == 'CERTBOT_DIR' ]]; then
      CERTBOT_DIR=$value
    elif [[ "$var" == 'NGINX_VOLUME' ]]; then
      NGINX_VOLUME=$value
    fi
  done < .env

#If the required vars are not defined exit with error
if [[ -z $VIRTUAL_HOST ]]; then
  echo "No virtual host defined"
  exit 1
fi
if [[ -z $CERTBOT_DIR ]]; then
  echo "No certbot defined"
  exit 1
fi

if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

domains=($VIRTUAL_HOST www.$VIRTUAL_HOST)
rsa_key_size=4096
data_path=$CERTBOT_DIR
email=$EMAIL # Adding a valid address is strongly recommended
# Set to 1 if you're testing your setup to avoid hitting request limits
if [ $ENV == "prod" ]; then 
  staging=0
elif [ $ENV == "preprod" ]; then
  staging=1
fi
echo

echo "### Check for existing data..."
if [ -d "$data_path" ]; then
  read -p "Existing data found for $domains. Continue and replace existing certificate? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit
  fi
fi
echo


if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

echo "### Creating dummy certificate for $domains ..."
path="/etc/letsencrypt/live/$domains"
mkdir -p "$data_path/conf/live/$domains"
echo "Dossier $data_path/conf/live/$domains créé"
docker-compose run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo

echo "### Starting nginx ..."
docker-compose up --force-recreate -d proxy
echo

echo "### Creating app.conf from app.conf template"
echo "You may be prompt for your password."
sudo cp ./conf/app.conf ./data/nginx/
sudo sed -i "s/myapp.com/$VIRTUAL_HOST/g" ./data/nginx/app.conf
echo

if [ $ENV == 'prod' ] || [ $ENV == 'preprod' ]; then
  echo "### Deleting dummy certificate for $domains ..."
  docker-compose run --rm --entrypoint "\
    rm -Rf /etc/letsencrypt/live/$domains && \
    rm -Rf /etc/letsencrypt/archive/$domains && \
    rm -Rf /etc/letsencrypt/renewal/$domains.conf" certbot
  echo


  echo "### Requesting Let's Encrypt certificate for $domains ..."
  #Join $domains to -d args
  domain_args=""
  for domain in "${domains[@]}"; do
    domain_args="$domain_args -d $domain"
  done

  # Select appropriate email arg
  case "$email" in
    "") email_arg="--register-unsafely-without-email" ;;
    *) email_arg="--email $email" ;;
  esac

  # Enable staging mode if needed
  if [ $staging != "0" ]; then staging_arg="--staging"; fi

  docker-compose run --rm --entrypoint "\
    certbot certonly --webroot -w /var/www/certbot \
      $staging_arg \
      $email_arg \
      $domain_args \
      --rsa-key-size $rsa_key_size \
      --agree-tos \
      --force-renewal" certbot
  echo
fi

echo "### Reloading nginx ..."
docker-compose exec proxy nginx -s reload