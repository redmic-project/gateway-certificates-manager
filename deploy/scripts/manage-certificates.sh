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
	echo "Updating certificates in web server service: ${SERVER_SERVICE}"

	secretFiles="chain fullchain privkey"

	for secretFile in ${secretFiles}
	do
		secretName="cert-${secretFile}"
		echo "Updating service secret: ${secretName}"

		docker service update \
			--secret-rm ${secretName} \
			${SERVER_SERVICE}

		docker secret rm ${secretName}

		cat /certs/live/${CERT_NAME}/${secretFile}.pem | docker secret create \
			-l com.docker.stack.namespace ${SERVER_STACK} \
			${secretName} -

		docker service update \
			--secret-add ${secretName} \
			${SERVER_SERVICE}
	done

	echo "Certificates successfully updated"
else
	echo "Certificates creation failed!"
	exit 1
fi
