#!/bin/bash
## Red Helpchain basada en el ejemplo de First-Network docker-compose-e2e con COUCHDB
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#


# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}
# Versions of fabric known not to work with this release of first-network
BLACKLISTED_VERSIONS="^1\.0\. ^1\.1\.0-preview ^1\.1\.0-alpha"

# Print the usage message
function printHelp() {
  echo "Uso: "
  echo "  helpchain.sh <mode> [-c <channel name>] [-t <timeout>] [-d <delay>] [-i <imagetag>]"
  echo "    <mode> - 'up', 'down', or 'generate'"
  echo "      - 'up' - levanta la red con docker-compose up"
  echo "      - 'down' - limpia la red con docker-compose down y elimina contenedores"
  echo "      - 'generate' - genera los certificados requeridos y bloque genesis"
  echo "    -c <channel name> - nombre de canal (default \"channelhelpchain\")"
  echo "    -t <timeout> - tiempo de espera del CLI en segundos (defaults to 10)"
  echo "    -d <delay> - duración de retraso entre comandos en segundos (defaults to 3)"
  echo "    -i <imagetag> - la etiqueta para lanzar la red (defaults to \"latest\")"
  echo "  helpchain.sh -h (imprime este mensaje)"
  echo
  echo
  echo "Procedimiento (defaults):"
  echo "	helpchain.sh generate"
  echo "	helpchain.sh up"
  echo "	helpchain.sh down"
}


function askProceed() {
  read -p "¿Continuamos? [S/n] " ans
  case "$ans" in
  s | S | "")
    echo "Empecemos ..."
    ;;
  n | N)
    echo "Saliendo..."
    exit 1
    ;;
  *)
    echo "Respuesta invalida"
    askProceed
    ;;
  esac
}


function networkUp() {

  if [ ! -d "crypto-config" ]; then
    generateCerts
    generateChannelArtifacts
  fi

  COMPOSE_FILES="-f ${COMPOSE_FILE}"
  COMPOSE_FILES="${COMPOSE_FILES} -f ${COMPOSE_FILE_COUCH}"

  IMAGE_TAG=$IMAGETAG docker-compose ${COMPOSE_FILES} up -d 2>&1
  docker ps -a
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! No se pudo iniciar la red"
    exit 1
  fi

  #Crea canal, mete peers0,1 orgs1,2,3 y actualiza los anchor.
  docker exec cli scripts/script.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! No se pudo finalizar"
    exit 1
  fi
}

function networkDown() {

  docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH down --volumes --remove-orphans

  docker run -v $PWD:/tmp/redhelpchain --rm hyperledger/fabric-tools:$IMAGETAG rm -Rf /tmp/redhelpchain/ledgers-backup
  # remove orderer block and other channel configuration transactions and certs
  rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config

  docker rm -f $(docker ps -aq)
  docker rmi -f $(docker images -q)
}

function generateCerts() {
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo "No se encontró la herramienta cryptogen. Saliendo"
    exit 1
  fi
  echo
  echo "#################################################################"
  echo "##### Generando certificados usando la herramienta cryptogen ####"
  echo "#################################################################"

  if [ -d "crypto-config" ]; then
    rm -Rf crypto-config
  fi
  set -x
  cryptogen generate --config=./crypto-config.yaml
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Error al generar los certificados..."
    exit 1
  fi
  echo
  echo "Generando archivos CCP para Org1, Org2, and Org3"
  ./ccp-generate.sh
}

function generateChannelArtifacts() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "No se encontró la herramienta configtxgen. Saliendo"
    exit 1
  fi

  echo "##########################################################"
  echo "#########  Generando Bloque Genesis Ordenador ############"
  echo "##########################################################"
  echo "CONSENSUS_TYPE="$CONSENSUS_TYPE
  set -x
  if [ "$CONSENSUS_TYPE" == "solo" ]; then
    configtxgen -profile ThreeOrgsOrdererGenesis -channelID $SYS_CHANNEL -outputBlock ./channel-artifacts/genesis.block
  else
    set +x
    echo "unrecognized CONSESUS_TYPE='$CONSENSUS_TYPE'. exiting"
    exit 1
  fi
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Error al generar bloque genesis ordenador..."
    exit 1
  fi
  echo
  echo "#################################################################"
  echo "### Generando: channel configuration transaction 'channel.tx' ###"
  echo "#################################################################"
  set -x
  configtxgen -profile ThreeOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Error: Failed to generate channel configuration transaction..."
    exit 1
  fi

  echo
  echo "#################################################################"
  echo "#######    Generando: anchor peer update for Org1MSP   ##########"
  echo "#################################################################"
  set -x
  configtxgen -profile ThreeOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/Org1MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org1MSP
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Error: Failed to generate anchor peer update for Org1MSP..."
    exit 1
  fi

  echo
  echo "#################################################################"
  echo "#######    Generando: anchor peer update for Org2MSP   ##########"
  echo "#################################################################"
  set -x
  configtxgen -profile ThreeOrgsChannel -outputAnchorPeersUpdate \
    ./channel-artifacts/Org2MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org2MSP
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Error: Failed to generate anchor peer update for Org2MSP..."
    exit 1
  fi

  echo
  echo "#################################################################"
  echo "#######    Generando: anchor peer update for Org3MSP   ##########"
  echo "#################################################################"
  set -x
  configtxgen -profile ThreeOrgsChannel -outputAnchorPeersUpdate \
    ./channel-artifacts/Org3MSPanchors.tx -channelID $CHANNEL_NAME -asOrg Org3MSP
  res=$?
  set +x
  if [ $res -ne 0 ]; then
    echo "Error: Failed to generate anchor peer update for Org3MSP..."
    exit 1
  fi
  echo
}


########################################################AQUI COMIENZA LA EJECUCION DEL SCRIPT#########################################



# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform, e.g., darwin-amd64 or linux-amd64
OS_ARCH=$(echo "$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')

# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
CLI_TIMEOUT=10

# default for delay between commands
CLI_DELAY=3

# system channel name defaults to "helpchain-sys-channel"
SYS_CHANNEL="helpchain-sys-channel"

# channel name defaults to "channelhelpchain"
CHANNEL_NAME="channelhelpchain"

# use this as the default docker-compose yaml and couch yaml
COMPOSE_FILE=docker-compose-redhelpchain.yaml
COMPOSE_FILE_COUCH=docker-compose-couch.yaml

LANGUAGE=node
IMAGETAG="latest"
CONSENSUS_TYPE="solo"

# Parse commandline args
if [ "$1" = "-m" ]; then # supports old usage, muscle memory is powerful!
  shift
fi
MODE=$1
shift
if [ "$MODE" == "up" ]; then
  EXPMODE="Iniciando "
elif [ "$MODE" == "down" ]; then
  EXPMODE="Deteniendo "
elif [ "$MODE" == "generate" ]; then
  EXPMODE="Generando certificados y bloque Genesis"
else
  printHelp
  exit 1
fi

while getopts "h?c:t:d:i" opt; do
  case "$opt" in
  h | \?)
    printHelp
    exit 0
    ;;
  c)
    CHANNEL_NAME=$OPTARG
    ;;
  t)
    CLI_TIMEOUT=$OPTARG
    ;;
  d)
    CLI_DELAY=$OPTARG
    ;;
  i)
    IMAGETAG=$(go env GOARCH)"-"$OPTARG
    ;;
  esac
done


# Announce what was requested
  echo "${EXPMODE} el canal '${CHANNEL_NAME}' con tiempo de respuesta de '${CLI_TIMEOUT}' segundos y retraso de CLI en '${CLI_DELAY}' segundos. Utilizando COUCHDB como base de datos."
askProceed

#Create the network using docker compose
if [ "${MODE}" == "up" ]; then
  networkUp
elif [ "${MODE}" == "down" ]; then ## Clear the network
  networkDown
elif [ "${MODE}" == "generate" ]; then ## Generate Artifacts
  generateCerts
  #replacePrivateKey
  generateChannelArtifacts
else
  printHelp
  exit 1
fi
