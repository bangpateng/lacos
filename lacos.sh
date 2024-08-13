#!/bin/bash
source <(curl -s https://raw.githubusercontent.com/bangpateng/symphony/main/logo.sh)

read -p "Enter Moniker (nama Validator ): " MONIKER
read -p "Enter Wallet (isi tulisan wallet): " KEY
read -p "Enter Node Port (isi 92): " laconicd_PORT

echo "export KEY=$KEY" >> $HOME/.bash_profile
echo "export MONIKER=$MONIKER" >> $HOME/.bash_profile
echo "export laconicd_CHAIN_ID=laconic_9000-1" >> $HOME/.bash_profile
echo "export laconicd_PORT=$laconicd_PORT" >> $HOME/.bash_profile
source $HOME/.bash_profile

echo "------------------------------------------------------------------------------------"
echo -e "Moniker: \e[1m\e[32m$MONIKER\e[0m"
echo -e "Wallet: \e[1m\e[32m$KEY\e[0m"
echo -e "Chain id: \e[1m\e[32mlaconic_9000-1\e[0m"
echo -e "Node custom port: \e[1m\e[32m$laconicd_PORT\e[0m"
echo "------------------------------------------------------------------------------------"
sleep 1

"1. Installing go..." && sleep 1
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

source <(curl -s https://raw.githubusercontent.com/Winnode/winnode/main/update.sh)

"2. Installing binary..." && sleep 1
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

  laconicd keys add $KEY --keyring-backend $KEYRING

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

  if [[ "$TEST_AUCTION_ENABLED" == "true" ]]; then
    update_genesis '.app_state["registry"]["params"]["authority_auction_enabled"]=true'
    update_genesis '.app_state["registry"]["params"]["authority_rent_duration"]="60s"'
    update_genesis '.app_state["registry"]["params"]["authority_grace_period"]="300s"'
    update_genesis '.app_state["registry"]["params"]["authority_auction_commits_duration"]="60s"'
    update_genesis '.app_state["registry"]["params"]["authority_auction_reveals_duration"]="60s"'
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
  echo "Using existing database at $HOME/.laconicd.  To replace, run '`basename $0` clean'"
fi

# Create systemd service file
SERVICE_FILE=/etc/systemd/system/laconicd.service

cat <<EOF | sudo tee $SERVICE_FILE
[Unit]
Description=Laconic Daemon
After=network.target

[Service]
Type=simple
User=root
ExecStart=/root/go/bin/laconicd start \
  --pruning=nothing \
  --log_level info \
  --minimum-gas-prices=1$DENOM \
  --api.enable \
  --rpc.laddr="tcp://0.0.0.0:$laconicd_PORT" \
  --gql-server \
  --gql-playground \
  --gql-port="9473"
Restart=on-failure
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable laconicd
sudo systemctl restart laconicd && sudo journalctl -u laconicd -f
