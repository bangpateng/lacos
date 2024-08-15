#!/bin/bash

# Mengambil logo dari URL
source <(curl -s https://raw.githubusercontent.com/bangpateng/symphony/main/logo.sh)

read -p "Enter Moniker (nama Validator): " MONIKER
read -p "Enter Wallet (isi tulisan wallet): " KEY
read -p "Enter Mnemonic Phrase (frasa mnemonic 12 kata): " MNEMONIC_PHRASE

laconicd_PORT=375

echo "export KEY=$KEY" >> $HOME/.bash_profile
echo "export MONIKER=$MONIKER" >> $HOME/.bash_profile
echo "export laconicd_CHAIN_ID=laconic_9000-1" >> $HOME/.bash_profile
echo "export laconicd_PORT=$laconicd_PORT" >> $HOME/.bash_profile
source $HOME/.bash_profile


echo "------------------------------------------------------------------------------------"
echo -e "Moniker: \e[1m\e[32m$MONIKER\e[0m"
echo -e "Wallet: \e[1m\e[32m$KEY\e[0m"
echo -e "Chain ID: \e[1m\e[32mlaconic_9000-1\e[0m"
echo -e "Node Port: \e[1m\e[32m$laconicd_PORT\e[0m"
echo "------------------------------------------------------------------------------------"
sleep 1

echo "1. Updating packages..." && sleep 1
sudo apt update


echo "2. Installing dependencies..." && sleep 1
sudo apt install curl git wget htop tmux build-essential jq make lz4 gcc unzip -y

echo "3. Installing Go..." && sleep 1
cd $HOME
VER="1.22.2"
wget "https://golang.org/dl/go$VER.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$VER.linux-amd64.tar.gz"
rm "go$VER.linux-amd64.tar.gz"
[ ! -f ~/.bash_profile ] && touch ~/.bash_profile
echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
source $HOME/.bash_profile
[ ! -d ~/go/bin ] && mkdir -p ~/go/bin

echo $(go version) && sleep 1


echo "4. Installing binary..." && sleep 1
cd $HOME
rm -rf laconicd
git clone https://git.vdb.to/cerc-io/laconicd.git
cd laconicd
make install



CHAINID=${laconicd_CHAIN_ID:-"laconic_9000-1"}
KEYRING=${KEYRING:-"test"}
DENOM=${DENOM:-"alnt"}
STAKING_AMOUNT=${STAKING_AMOUNT:-"1000000000000000"}
LOGLEVEL=${LOGLEVEL:-"info"}

input_genesis_file=${GENESIS_FILE}

if [ "$1" == "clean" ] || [ ! -d "$HOME/.laconicd/data/blockstore.db" ]; then
  command -v jq > /dev/null 2>&1 || {
    echo >&2 "jq not installed. More info: https://stedolan.github.io/jq/download/"
    exit 1
  }

  rm -rf $HOME/.laconicd/*

  if [ -n "`which make`" ]; then
    make install
  fi

  laconicd config set client chain-id $CHAINID
  laconicd config set client keyring-backend $KEYRING
  echo $MNEMONIC_PHRASE | laconicd keys add $KEY --keyring-backend $KEYRING --recover

  laconicd init $MONIKER --chain-id $CHAINID --default-denom $DENOM

  if [[ -f ${input_genesis_file} ]]; then
    cp $input_genesis_file $HOME/.laconicd/config/genesis.json
  fi

  update_genesis() {
    jq "$1" $HOME/.laconicd/config/genesis.json > $HOME/.laconicd/config/tmp_genesis.json &&
      mv $HOME/.laconicd/config/tmp_genesis.json $HOME/.laconicd/config/genesis.json
  }

  if [[ "$TEST_REGISTRY_EXPIRY" == "true" ]]; then
    update_genesis '.app_state["registry"]["params"]["record_rent_duration"]="60s"'
    update_genesis '.app_state["registry"]["params"]["authority_grace_period"]="60s"'
    update_genesis '.app_state["registry"]["params"]["authority_rent_duration"]="60s"'
  fi

  if [[ "$ONBOARDING_ENABLED" == "true" ]]; then
    update_genesis '.app_state["onboarding"]["params"]["onboarding_enabled"]=true'
  fi

  if [[ "$AUTHORITY_AUCTION_ENABLED" == "true" ]]; then
    update_genesis '.app_state["registry"]["params"]["authority_auction_enabled"]=true'
  fi

  if [[ -n $AUTHORITY_AUCTION_COMMITS_DURATION ]]; then
    update_genesis ".app_state[\"registry\"][\"params\"][\"authority_auction_commits_duration\"]=\"${AUTHORITY_AUCTION_COMMITS_DURATION}s\""
  fi

  if [[ -n $AUTHORITY_AUCTION_REVEALS_DURATION ]]; then
    update_genesis ".app_state[\"registry\"][\"params\"][\"authority_auction_reveals_duration\"]=\"${AUTHORITY_AUCTION_REVEALS_DURATION}s\""
  fi

  if [[ -n $AUTHORITY_GRACE_PERIOD ]]; then
    update_genesis ".app_state[\"registry\"][\"params\"][\"authority_grace_period\"]=\"${AUTHORITY_GRACE_PERIOD}s\""
  fi

  update_genesis '.consensus["params"]["block"]["time_iota_ms"]="1000"'
  update_genesis '.consensus["params"]["block"]["max_gas"]="10000000"'

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/create_empty_blocks = true/create_empty_blocks = false/g' $HOME/.laconicd/config/config.toml
  else
    sed -i 's/create_empty_blocks = true/create_empty_blocks = false/g' $HOME/.laconicd/config/config.toml
  fi

  sed -i 's/cors_allowed_origins.*$/cors_allowed_origins = ["*"]/' $HOME/.laconicd/config/config.toml

  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/enabled = false/enabled = true/g' $HOME/.laconicd/config/app.toml
    sed -i '' 's/prometheus-retention-time = 0/prometheus-retention-time = 60/g' $HOME/.laconicd/config/app.toml
    sed -i '' 's/prometheus = false/prometheus = true/g' $HOME/.laconicd/config/config.toml
  else
    sed -i 's/enabled = false/enabled = true/g' $HOME/.laconicd/config/app.toml
    sed -i 's/prometheus-retention-time = 0/prometheus-retention-time = 60/g' $HOME/.laconicd/config/app.toml
    sed -i 's/prometheus = false/prometheus = true/g' $HOME/.laconicd/config/config.toml
  fi

  laconicd genesis add-genesis-account $KEY 1000000000000000000000000000000$DENOM --keyring-backend $KEYRING
  laconicd genesis gentx $KEY $STAKING_AMOUNT$DENOM --keyring-backend $KEYRING --chain-id $CHAINID
  laconicd genesis collect-gentxs
  laconicd genesis validate
else
  echo "Using existing database at $HOME/.laconicd. To replace, run '`basename $0` clean'"
fi

SERVICE_FILE=/etc/systemd/system/laconicd.service

cat <<EOF | sudo tee $SERVICE_FILE
[Unit]
Description=laconicd daemon
After=network-online.target

[Service]
User=$USER
ExecStart=$(which laconicd) start
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

DAEMON_NAME="laconicd"
DAEMON_HOME="$HOME/.laconicd"
echo -e '\n\e[42mChecking a ports\e[0m\n' && sleep 1

DAEMON_HOME="$HOME/.laconicd"
PORT=335
if ss -tulpen | awk '{print $5}' | grep -q ":26656$" ; then
    echo -e "\e[31mPort 26656 already in use.\e[39m"
    sleep 2
    sed -i -e "s|:26656\"|:${PORT}56\"|g" $DAEMON_HOME/config/config.toml
    echo -e "\n\e[42mPort 26656 changed to ${PORT}56.\e[0m\n"
    sleep 2
fi
if ss -tulpen | awk '{print $5}' | grep -q ":26657$" ; then
    echo -e "\e[31mPort 26657 already in use\e[39m"
    sleep 2
    sed -i -e "s|:26657\"|:${PORT}57\"|" $DAEMON_HOME/config/config.toml
    echo -e "\n\e[42mPort 26657 changed to ${PORT}57.\e[0m\n"
    sleep 2
    $DAEMON_NAME config node tcp://localhost:${PORT}57
fi
if ss -tulpen | awk '{print $5}' | grep -q ":26658$" ; then
    echo -e "\e[31mPort 26658 already in use.\e[39m"
    sleep 2
    sed -i -e "s|:26658\"|:${PORT}58\"|" $DAEMON_HOME/config/config.toml
    echo -e "\n\e[42mPort 26658 changed to ${PORT}58.\e[0m\n"
    sleep 2
fi
if ss -tulpen | awk '{print $5}' | grep -q ":6060$" ; then
    echo -e "\e[31mPort 6060 already in use.\e[39m"
    sleep 2
    sed -i -e "s|:6060\"|:${PORT}60\"|" $DAEMON_HOME/config/config.toml
    echo -e "\n\e[42mPort 6060 changed to ${PORT}60.\e[0m\n"
    sleep 2
fi
if ss -tulpen | awk '{print $5}' | grep -q ":1317$" ; then
    echo -e "\e[31mPort 1317 already in use.\e[39m"
    sleep 2
    sed -i -e "s|:1317\"|:${PORT}17\"|" $DAEMON_HOME/config/app.toml
    echo -e "\n\e[42mPort 1317 changed to ${PORT}17.\e[0m\n"
    sleep 2
fi
if ss -tulpen | awk '{print $5}' | grep -q ":9090$" ; then
    echo -e "\e[31mPort 9090 already in use.\e[39m"
    sleep 2
    sed -i -e "s|:9090\"|:${PORT}90\"|" $DAEMON_HOME/config/app.toml
    echo -e "\n\e[42mPort 9090 changed to ${PORT}90.\e[0m\n"
    sleep 2
fi
if ss -tulpen | awk '{print $5}' | grep -q ":9091$" ; then
    echo -e "\e[31mPort 9091 already in use.\e[39m"
    sleep 2
    sed -i -e "s|:9091\"|:${PORT}91\"|" $DAEMON_HOME/config/app.toml
    echo -e "\n\e[42mPort 9091 changed to ${PORT}91.\e[0m\n"
    sleep 2
fi
if ss -tulpen | awk '{print $5}' | grep -q ":8545$" ; then
    echo -e "\e[31mPort 8545 already in use.\e[39m"
    sleep 2
    sed -i -e "s|:8545\"|:${PORT}45\"|" $DAEMON_HOME/config/app.toml
    echo -e "\n\e[42mPort 8545 changed to ${PORT}45.\e[0m\n"
    sleep 2
fi
if ss -tulpen | awk '{print $5}' | grep -q ":8546$" ; then
    echo -e "\e[31mPort 8546 already in use.\e[39m"
    sleep 2
    sed -i -e "s|:8546\"|:${PORT}46\"|" $DAEMON_HOME/config/app.toml
    echo -e "\n\e[42mPort 8546 changed to ${PORT}46.\e[0m\n"
    sleep 2
fi

echo "Port checks and updates complete."

sudo systemctl daemon-reload
sudo systemctl enable laconicd
sudo systemctl start laconicd
sudo systemctl status laconicd --no-pager

echo "Setup complete. Use 'sudo journalctl -u laconicd -f -o cat' to check the status."
