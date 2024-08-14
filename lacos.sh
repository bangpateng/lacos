#!/bin/bash

# Mengambil logo dari URL
source <(curl -s https://raw.githubusercontent.com/bangpateng/symphony/main/logo.sh)

# Meminta input dari pengguna
read -p "Enter Moniker (nama Validator): " MONIKER
read -p "Enter Wallet (isi tulisan wallet): " KEY
read -p "Enter Mnemonic Phrase (frasa mnemonic 12 kata): " MNEMONIC_PHRASE

# Default port yang akan digunakan
laconicd_PORT=335

# Menyimpan variabel ke dalam .bash_profile
echo "export KEY=$KEY" >> $HOME/.bash_profile
echo "export MONIKER=$MONIKER" >> $HOME/.bash_profile
echo "export laconicd_CHAIN_ID=laconic_9000-1" >> $HOME/.bash_profile
echo "export laconicd_PORT=$laconicd_PORT" >> $HOME/.bash_profile
source $HOME/.bash_profile

# Menampilkan konfigurasi yang telah dimasukkan
echo "------------------------------------------------------------------------------------"
echo -e "Moniker: \e[1m\e[32m$MONIKER\e[0m"
echo -e "Wallet: \e[1m\e[32m$KEY\e[0m"
echo -e "Chain ID: \e[1m\e[32mlaconic_9000-1\e[0m"
echo -e "Node Port: \e[1m\e[32m$laconicd_PORT\e[0m"
echo "------------------------------------------------------------------------------------"
sleep 1

# Pembaruan paket
echo "1. Updating packages..." && sleep 1
sudo apt update

# Instalasi dependensi
echo "2. Installing dependencies..." && sleep 1
sudo apt install curl git wget htop tmux build-essential jq make lz4 gcc unzip -y

# Instalasi Go
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

# Instalasi binary
echo "4. Installing binary..." && sleep 1
cd $HOME
rm -rf laconicd
git clone https://git.vdb.to/cerc-io/laconicd.git
cd laconicd
make install

# Fungsi untuk memeriksa dan memperbarui port jika diperlukan
check_and_update_port() {
    local default_port=$1
    local config_file=$2
    local new_port="${laconicd_PORT}${default_port: -2}" # Mengubah dua digit terakhir default_port

    if ss -tulpen | awk '{print $5}' | grep -q ":$default_port$" ; then
        echo -e "\e[31mPort $default_port already in use.\e[39m"
        sleep 2
        sed -i -e "s|:$default_port\"|:${new_port}\"|" $config_file
        echo -e "\n\e[42mPort $default_port changed to ${new_port}.\e[0m\n"
        sleep 2
    fi
}

# Memeriksa dan memperbarui port
echo "5. Checking and updating ports..." && sleep 1
check_and_update_port 26656 $HOME/config/config.toml
check_and_update_port 26657 $HOME/config/config.toml
check_and_update_port 26658 $HOME/config/config.toml
check_and_update_port 6060 $HOME/config/config.toml
check_and_update_port 1317 $HOME/config/app.toml
check_and_update_port 9090 $HOME/config/app.toml
check_and_update_port 9091 $HOME/config/app.toml
check_and_update_port 8545 $HOME/config/app.toml
check_and_update_port 8546 $HOME/config/app.toml

# Variabel default
CHAINID=${laconicd_CHAIN_ID:-"laconic_9000-1"}
KEYRING=${KEYRING:-"test"}
DENOM=${DENOM:-"alnt"}
STAKING_AMOUNT=${STAKING_AMOUNT:-"1000000000000000"}
LOGLEVEL=${LOGLEVEL:-"info"}

input_genesis_file=${GENESIS_FILE}

# Membersihkan dan mengonfigurasi jika diperlukan
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

  # Mengupdate genesis.json jika diperlukan
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

  # Menyesuaikan konfigurasi untuk MacOS atau Linux
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

  # Menambahkan akun genesis dan gentx
  laconicd genesis add-genesis-account $KEY 1000000000000000000000000000000$DENOM --keyring-backend $KEYRING
  laconicd genesis gentx $KEY $STAKING_AMOUNT$DENOM --keyring-backend $KEYRING --chain-id $CHAINID
  laconicd genesis collect-gentxs
  laconicd genesis validate
else
  echo "Using existing database at $HOME/.laconicd. To replace, run '`basename $0` clean'"
fi

# Membuat file service systemd
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

sudo systemctl daemon-reload
sudo systemctl enable laconicd
sudo systemctl start laconicd
sudo systemctl status laconicd --no-pager

echo "Setup complete. Use 'sudo journalctl -u laconicd -f -o cat' to check the status."
