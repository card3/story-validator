#!/usr/bin/env bash

# the moniker (the human-readable identifier for your node)
moniker_name=""
archive=false

# GOLANG
GO_VERSION=1.23.2
GO_DOWNLOAD_URL=https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz
GO_PACKAGE=go.tar.gz

# check disk  available space
available_space=$(df --output=avail -BG / | tail -n 1 | tr -d 'G')

# At least 500 GB if use archive snapshot
threshold=500
# COSMOVISOR https://docs.cosmos.network/main/build/tooling/cosmovisor#installation
COSMOVISOR_VERSION=v1.6.0


# Story-Geth - https://github.com/piplabs/story-geth
GETH_VERSION=v0.9.4
GETH_BINARY_URL=https://github.com/piplabs/story-geth/releases/download/${GETH_VERSION}/geth-linux-amd64

# Story -https://github.com/piplabs/story
STORY_VERSION=v0.11.0
STORY_BINARY_URL=https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.11.0-aac4bfe.tar.gz


# DIR for binary to store
INSTALL_DIR="/opt/story-validator"
GETH_BINARY_DIR="${INSTALL_DIR}/geth"
STORY_BINARY_DIR="${INSTALL_DIR}/story"


# Install basic dependencies
function install_deps(){
    sudo apt-get update \
     && sudo apt-get install curl \
        git make jq build-essential gcc unzip wget lz4 aria2 pv -y
}

# Install Golang 
function install_go(){
    # Check if golang exists
    if ! sudo -u root command -v go &> /dev/null
    then
        echo "Start to install Golang environment"
        wget  ${GO_DOWNLOAD_URL} -O ${GO_PACKAGE} && \
        sudo rm -rf /usr/local/go && \
        sudo tar -C /usr/local -xzf ${GO_PACKAGE} && \
        rm ${GO_PACKAGE}  && \
        [ ! -f /root/.bash_profile ] && sudo touch /root/.bash_profile && \
        echo 'export PATH=$PATH:/usr/local/go/bin:/root/go/bin' | sudo tee -a /root/.bash_profile && \
sudo tee -a /root/.bashrc << EOF

# Source .bash_profile if it exists
if [ -f ~/.bash_profile ]; then
    source ~/.bash_profile
fi
EOF
sudo bash -c "source /root/.bash_profile && go version"
    else
        echo "Go is installed for the root user"
    fi

}

# Install Cosmovisor
function install_cosmovisor(){
    install_go
    sudo bash -c "source /root/.bash_profile && go version && \
    go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@${COSMOVISOR_VERSION} "
 

}

# https://github.com/piplabs/story-geth
function install_geth(){
    sudo mkdir -p "$GETH_BINARY_DIR" 
    sudo wget  ${GETH_BINARY_URL} -O ${GETH_BINARY_DIR}/geth && \
    sudo chmod +x ${GETH_BINARY_DIR}/geth
}

function create_geth_service(){
if [ -f /etc/systemd/system/geth.service ]; then
    echo "File /etc/systemd/system/geth.service exists."
else
    echo "File /etc/systemd/system/geth.service does not exist."
sudo tee /etc/systemd/system/geth.service > /dev/null <<EOF
[Unit]
Description=Geth
After=network.target

[Service]
User=root
ExecStart=${GETH_BINARY_DIR}/geth --iliad --syncmode full
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
fi
}

function init_geth(){
create_geth_service
}

function install_story(){
    sudo mkdir -p "$STORY_BINARY_DIR" 
    sudo wget  ${STORY_BINARY_URL} -O  story.tar.gz && \
    sudo tar --strip-components=1 -xzf story.tar.gz -C "$STORY_BINARY_DIR" && \
    sudo rm -f story.tar.gz 
}


function init_story(){
    echo "$moniker_name"
    sudo $STORY_BINARY_DIR/story init --network iliad --moniker "$moniker_name" 
}

function create_story_service(){
    if [ -f /etc/systemd/system/story.service ]; then
    echo "File /etc/systemd/system/story.service  exists."
else
    echo "File /etc/systemd/system/story.service does not exist."
sudo tee /etc/systemd/system/story.service > /dev/null <<EOF
[Service]
Type=simple
User=root
ExecStart=/root/go/bin/cosmovisor run run
Restart==always
RestartSec=3
StartLimitInterval=0
StandardOutput=journal
StandardError=journal
LimitNOFILE=65536
LimitNPROC=65536

Environment="DAEMON_HOME=/root/.story/story"
Environment="DAEMON_NAME=story"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="COSMOVISOR_SKIP_BACKUP=true"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="DAEMON_DATA_BACKUP_DIR=/root/.story/story/cosmovisor/backup"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"

[Install]
WantedBy=multi-user.target
EOF
fi
}


function init_cosmovisor(){
    
    export DAEMON_NAME=story
    export DAEMON_HOME=/root/.story/story
    sudo mkdir -p  $DAEMON_HOME/cosmovisor/backup
    export DAEMON_DATA_BACKUP_DIR=$DAEMON_HOME/cosmovisor/backup

    echo "export DAEMON_HOME=/root/.story/story" | sudo tee -a /root/.bash_profile
    echo "export DAEMON_NAME=story" | sudo tee -a /root/.bash_profile
    
    echo "export DAEMON_DATA_BACKUP_DIR=$DAEMON_HOME/cosmovisor/backup" | sudo tee -a /root/.bash_profile
    echo "export DAEMON_ALLOW_DOWNLOAD_BINARIES=true" | sudo tee -a /root/.bash_profile
    # cosmovisor init [path for story binary]
    sudo bash -c "source /root/.bash_profile && cosmovisor init ${STORY_BINARY_DIR}/story"
}

function download_prune_snapshot(){
    # download geth snapshot
     sudo rm -f Geth_snapshot.lz4 
     sudo rm -f Story_snapshot.lz4 
     aria2c -x 16 -s 16 -k 1M https://story.josephtran.co/Geth_snapshot.lz4
     aria2c -x 16 -s 16 -k 1M https://story.josephtran.co/Story_snapshot.lz4

}

function extract_prune_snapshot(){
  sudo rm -rf /root/.story/story/data
  sudo rm -rf /root/.story/geth/iliad/geth/chaindata
  lz4 -d -c Geth_snapshot.lz4 | pv | sudo tar xv -C /root/.story/geth/iliad/geth  > /dev/null
  lz4 -d -c Story_snapshot.lz4 | pv | sudo tar xv -C /root/.story/story > /dev/null
}

function download_archive_snapshot(){
    sudo rm -f archive_Story_snapshot.lz4
    sudo rm -f archive_Geth_snapshot.lz4
    aria2c -x 16 -s 16 -k 1M https://story.josephtran.co/archive_Geth_snapshot.lz4
    aria2c -x 16 -s 16 -k 1M https://story.josephtran.co/archive_Story_snapshot.lz4
}


function extract_archive_snapshot(){
  sudo rm -rf /root/.story/story/data
  sudo rm -rf /root/.story/geth/iliad/geth/chaindata
  lz4 -d -c Geth_snapshot.lz4 | pv | sudo tar xv -C /root/.story/geth/iliad/geth  > /dev/null
  lz4 -d -c Story_snapshot.lz4 | pv | sudo tar xv -C /root/.story/story > /dev/null 
}
function backup_validator_state(){
    sudo cp /root/.story/story/data/priv_validator_state.json /root/.story/priv_validator_state.json.backup
}

function restore_validator_state(){
    sudo cp /root/.story/priv_validator_state.json.backup /root/.story/story/data/priv_validator_state.json 
}


function launch_geth_story(){
    sudo systemctl daemon-reload && \
    sudo systemctl enable geth && \
    sudo systemctl enable story && \
    sudo systemctl start geth && \
    sudo  systemctl start story
}

function stop_geth_story(){
    sudo systemctl stop geth && \
    sudo  systemctl stop story
}
function start_geth_story(){
    sudo systemctl start geth && \
    sudo  systemctl start story
}

function check_status(){
    systemctl is-active --quiet story.service || echo "Story is not running, check logs by using sudo journalctl -u story-geth.service -f "
    echo "======================Validator Info======================= "
    curl -s localhost:26657/status | jq -r '.result.validator_info'
}

while getopts "m:" opt; do
  case $opt in
    m)
      moniker_name=$OPTARG
      ;;
    \?)
      echo "Invalid option:  -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG  requires an argument " >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

# --archive
for arg in "$@"; do
  if [ "$arg" == "--archive" ]; then
    echo "Archive flag detected, Using archive snapshot"
    archive=true
    if [ "$available_space" -lt "$threshold" ]; then
        echo "Warning: The available disk space is smaller than 500GB. Current available space: ${available_space}GB"
        
        read -p "Do you want to continue? (Y/N): " choice

        choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
        if [ "$choice" == "Y" ]; then
            echo "Continuing operation..."
        else
            echo "Operation aborted."
            exit 1
        fi
    fi
   fi
done

install_deps
install_cosmovisor
install_geth
init_geth
install_story
init_story
init_cosmovisor
create_story_service
launch_geth_story
if [ "$archive" = true ]; then
    download_archive_snapshot
    stop_geth_story
    backup_validator_state
    extract_archive_snapshot
else
    download_prune_snapshot
    stop_geth_story
    backup_validator_state
    extract_prune_snapshot
fi
restore_validator_state
start_geth_story
check_status
