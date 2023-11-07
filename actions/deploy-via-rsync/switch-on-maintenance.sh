#!/bin/bash

CONF_DIR=$1
DESTINATION_PATH=$2

if ssh server "test -e ${DESTINATION_PATH}/${CONF_DIR}/.env"; then
    ssh server "mv ${DESTINATION_PATH}/${CONF_DIR}/.env ${DESTINATION_PATH}/${CONF_DIR}/old.env"
    ssh server "sed -e 's|A7_MAINTENANCE=\"off\"|A7_MAINTENANCE=\"on\"|' ${DESTINATION_PATH}/${CONF_DIR}/old.env > ${DESTINATION_PATH}/${CONF_DIR}/.env"
fi