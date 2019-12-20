#!/bin/bash

echo
echo " ____    _____      _      ____    _____ "
echo "/ ___|  |_   _|    / \    |  _ \  |_   _|"
echo "\___ \    | |     / _ \   | |_) |   | |  "
echo " ___) |   | |    / ___ \  |  _ <    | |  "
echo "|____/    |_|   /_/   \_\ |_| \_\   |_|  "
echo
echo "----------------- Helpchain ---------------"
echo
CHANNEL_NAME="$1"
DELAY="$2"
LANGUAGE="$3"
TIMEOUT="$4"
: ${CHANNEL_NAME:="channelhelpchain"}
: ${DELAY:="5"}
: ${LANGUAGE:="node"}
: ${TIMEOUT:="10"}
LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`
COUNTER=1
MAX_RETRY=10

if [ "$LANGUAGE" = "node" ]; then
	CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/contract"
fi

echo "Channel name : "$CHANNEL_NAME

# import utils
. scripts/utils.sh

createChannel() {
	setGlobals 0 1

	if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
                set -x
		peer channel create -o orderer.ord.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx >&log.txt
		res=$?
                set +x
	else
				set -x
		peer channel create -o orderer.ord.com:7050 -c $CHANNEL_NAME -f ./channel-artifacts/channel.tx --tls $CORE_PEER_TLS_ENABLED --cafile $ORDERER_CA >&log.txt
		res=$?
				set +x
	fi
	cat log.txt
	verifyResult $res "La creacion del canal ha fallado"
	echo "===================== El canal '$CHANNEL_NAME' ha sido creado exitosamente ===================== "
	echo
}

joinChannel () {
	for org in 1 2 3; do
	    for peer in 0 1; do
		joinChannelWithRetry $peer $org
		echo "===================== peer${peer}.org${org} se ha unido al canal '$CHANNEL_NAME' ===================== "
		sleep $DELAY
		echo
	    done
	done
}

## Create channel
echo "Creando el canal $CHANNEL_NAME..."
createChannel

## Join all the peers to the channel
echo "Uniendo todos los peers al canal..."
joinChannel

## Set the anchor peers for each org in the channel
echo "Actualizando anchor peers para la organizacion de Reguladores..."
updateAnchorPeers 0 1
echo "Actualizando anchor peers para la organizacion de Soporte Tecnico..."
updateAnchorPeers 0 2
echo "Actualizando anchor peers para la organizacion de Usuarios..."
updateAnchorPeers 0 3


# ## Install chaincode on peer0.reg and peer0.sop
 echo "Instalando chaincode en peer0.reg..."
 installChaincode 0 1
 echo "Instalando chaincode en peer0.sop..."
 installChaincode 0 2
 echo "Instalando chaincode en peer0.usr..."
 installChaincode 0 3


# # Instantiate chaincode on peer0.sop
 echo "Instanciando chaincode en peer0.reg..."
 instantiateChaincode 0 1


# # Query chaincode on peer0.reg
# echo "Querying chaincode on peer0.reg..."
# chaincodeQuery 0 1 100
#
# # Invoke chaincode on peer0.reg and peer0.sop
# echo "Sending invoke transaction on peer0.reg peer0.sop..."
# chaincodeInvoke 0 1 0 2
#
# ## Install chaincode on peer1.sop
# echo "Installing chaincode on peer1.sop..."
# installChaincode 1 2
#
# # Query on chaincode on peer1.sop, check if the result is 90
# echo "Querying chaincode on peer1.sop..."
# chaincodeQuery 1 2 90



echo
echo "================ Helpchain configurado correctamente ================== "
echo

echo
echo " _____   _   _   ____   "
echo "| ____| | \ | | |  _ \  "
echo "|  _|   |  \| | | | | | "
echo "| |___  | |\  | | |_| | "
echo "|_____| |_| \_| |____/  "
echo

exit 0
