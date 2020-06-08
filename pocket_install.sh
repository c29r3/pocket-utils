#!/bin/bash

PWD="pass"
INFURA_TOKEN="token"
CHAIN_ID="0022"
USERNAME="moniker"
SEEDS="610cf8a6e8cefbaded845f1c1dc3b10a670be26b@node1.testnet.pokt.network:26656,e6946760d9833f49da39aae9500537bef6f33a7a@node2.testnet.pokt.network:26656,7674a47cc977326f1df6cb92c7b5a2ad36557ea2@node3.testnet.pokt.network:26656"
EXTERNAL_IP=$(curl -s 2ip.ru)

apt install -y nginx gcc

if [[ ! -d "/root/pokt" ]]; then
    mkdir ~/pokt
fi

mkdir -p ~/.pocket/config 

cd ~/pokt

echo $GOPATH

echo "build new version"
git clone https://github.com/pokt-network/pocket-core.git > /dev/null 2>&1
cd pocket-core
git checkout tags/RC-0.4.0 > /dev/null 2>&1
go build -tags cleveldb -o $GOPATH/bin/pocket ./app/cmd/pocket_core/main.go > /dev/null 2>&1
echo $(pocket version)

cd ..

echo "Create new wallet"
VALIDATOR_ADDRESS=$(echo -e "$PWD\n\n" | $(which pocket) accounts create | egrep -o "[a-f0-9]{40}")

echo "Export raw private key to file"
PRIVATE_KEY=$(echo -e "$PWD\n\n" | $(which pocket) accounts export-raw $VALIDATOR_ADDRESS | egrep -o "[a-f0-9]{128}")

echo -e "$VALIDATOR_ADDRESS;$PRIVATE_KEY" > ~/pokt/pocket_$USERNAME.txt

echo "pocket reset"
$(which pocket) reset

echo "Init new config.json config"
$(pocket start)

echo "Setup chains.json"
echo "[
  {
    'id': '$CHAIN_ID',
    'url': 'https://ropsten.infura.io/v3/$INFURA_TOKEN',
    'basic_auth': {
      'username': '',
      'password': ''
    }
  }
]" > ~/.pocket/config/chains.json
sed -i -e "s/'/\"/g" ~/.pocket/config/chains.json

echo "Set validator address $VALIDATOR_ADDRESS"
echo -e "$PWD\n\n" | $(which pocket) accounts set-validator $VALIDATOR_ADDRESS


echo "Changing ports in config.toml"
sed -i -e "s/26658/28658/g" ~/.pocket/config/config.json

sed -i -e "s/26657/28657/g" ~/.pocket/config/config.json

sed -i -e "s/26656/28656/g" ~/.pocket/config/config.json

sed -i -e "s/26660/28650/g" ~/.pocket/config/config.json

sed -i -e "s/$HOSTNAME/$USERNAME/g" ~/.pocket/config/config.json

sed -i -e "s/http:\/\/localhost:8081/https:\/\/$EXTERNAL_IP:8082/g" ~/.pocket/config/config.json

sed -i -e "s/\"Seeds\": \"\"/\"Seeds\": \"$SEEDS\"/" ~/.pocket/config/config.json


echo -e "\n\n\n\n\n\n\n" | openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/nginx-selfsigned.key -out /etc/ssl/certs/nginx-selfsigned.crt > /dev/null 2>&1


wget https://raw.githubusercontent.com/pokt-network/pocket-network-genesis/master/testnet/genesis.json -O ~/.pocket/config/genesis.json > /dev/null 2>&1



if [[ ! -f "/etc/nginx/sites-available/pocket-proxy.conf" ]]; then
    echo "[
            server {
            listen 8082 ssl;
            listen [::]:8082 ssl;

            ssl on;
            ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
            ssl_certificate_key  /etc/ssl/private/nginx-selfsigned.key;
            access_log /var/log/nginx/reverse-access.log;
            error_log /var/log/nginx/reverse-error.log;
            location / {
                proxy_pass http://$EXTERNAL_IP:8081;
            }
        }" >> /etc/nginx/sites-available/pocket-proxy.conf
fi


if ! grep -Fxq "subjectAltName=IP:$EXTERNAL_IP" /etc/ssl/openssl.cnf; then
    sed -i -e "/\[ v3_ca \]/a subjectAltName=IP:$EXTERNAL_IP" /etc/ssl/openssl.cnf
fi


echo "Creating systemd service pocket.service"
echo "[Unit]
Description="Pocket node"
After=network-online.target

[Service]
User=root
WorkingDirectory=/root
ExecStart=/root/go/bin/pocket start
ExecStop=/bin/kill $(/bin/pidof pocket)
LimitNOFILE=10000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/pocket.service


systemctl daemon-reload
systemctl enable pocket.service
systemctl start pocket.service
systemctl status pocket.service
systemctl restart nginx

