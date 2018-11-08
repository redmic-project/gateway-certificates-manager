#!/bin/sh

if [ -z "${CERT_NAME}" ] || [ -z "${DOMAIN_LIST}" ] || [ -z "${EMAIL_LIST}" ]
then
	echo "CERT_NAME, DOMAIN_LIST and EMAIL_LIST variables should be defined!"
	exit 1
fi

docker run --rm \
	-v ${CERTBOT_CONFIG_VOL_NAME}:/etc/letsencrypt \
	-v ${CERTBOT_WORK_VOL_NAME}:/var/lib/letsencrypt \
	-v ${CERTBOT_LOGS_VOL_NAME}:/var/log/letsencrypt \
	-v ${ACME_VOL_NAME}:/var/www/html \
	certbot/certbot certonly \
		--expand \
		--renew-with-new-domains \
		--keep-until-expiring \
		--webroot -w /var/www/html/ \
		--cert-name ${CERT_NAME} \
		-m ${EMAIL_LIST} --agree-tos --no-eff-email \
		-d ${DOMAIN_LIST} \
		--pre-hook "rm -f /etc/letsencrypt/UPDATED" \
		--deploy-hook "touch /etc/letsencrypt/UPDATED"

if [ -e /certs/UPDATED ]
then
	echo "Certificates created for domains: ${DOMAIN_LIST}"

	secretFiles="chain fullchain privkey"

	if [ ! -e /certs/dhparam.pem ]
	then
		echo "DHParam not found, generating.."
		openssl dhparam -out /certs/dhparam.pem 4096
		dhparamUpdated="1"
	fi

	echo "Updating certificates in web server service: ${SERVER_SERVICE}"

	for secretFile in ${secretFiles}
	do
		secretName="cert-${secretFile}"
		echo "Updating service secret: ${secretName}"

		docker service update \
			--secret-rm ${secretName} \
			${SERVER_SERVICE}

		docker secret rm ${secretName}

		docker secret create \
			-l com.docker.stack.namespace ${SERVER_STACK}
			${secretName}
			/certs/live/${CERT_NAME}/${secretFile}.pem

		docker service update \
			--secret-add ${secretName} \
			${SERVER_SERVICE}
	done

	if [ ${dhparamUpdated} -eq "1" ]
	then
		configName="cert-dhparam"
		echo "Updating service config: ${configName}"

		docker service update \
			--config-rm ${configName} \
			${SERVER_SERVICE}

		docker config rm ${configName}

		docker config create \
			-l com.docker.stack.namespace ${SERVER_STACK}
			${configName}
			/certs/dhparam.pem

		docker service update \
			--config-add ${configName} \
			${SERVER_SERVICE}
	fi

	echo "Certificates successfully updated"
else
	echo "Certificates creation failed!"
	exit 1
fi
