#!/bin/sh

if [ -z "${CERT_NAME}" ] || [ -z "${DOMAIN_LIST}" ] || [ -z "${EMAIL_LIST}" ]
then
	echo "CERT_NAME, DOMAIN_LIST and EMAIL_LIST variables should be defined!"
	exit 1
fi

fileToTestUpdate="/certs/live/${CERT_NAME}/chain.pem"
if [ -e "${fileToTestUpdate}" ]
then
	md5Before=$(md5sum "${fileToTestUpdate}")
else
	md5Before=0
fi

if ! docker run --rm \
	-v ${CERTBOT_CONFIG_VOL_NAME}:/etc/letsencrypt \
	-v ${CERTBOT_WORK_VOL_NAME}:/var/lib/letsencrypt \
	-v ${CERTBOT_LOGS_VOL_NAME}:/var/log/letsencrypt \
	-v ${ACME_VOL_NAME}:/var/www/html \
	certbot/certbot certonly \
		--expand \
		--keep-until-expiring \
		--webroot -w /var/www/html/ \
		--cert-name ${CERT_NAME} \
		-m ${EMAIL_LIST} --agree-tos --no-eff-email \
		-d ${DOMAIN_LIST} \
		--no-self-upgrade
then
	echo "Certificates creation failed!"
	exit 1
fi

md5After=$(md5sum "${fileToTestUpdate}")

if [ "${md5Before}" != "${md5After}" ]
then
	echo "Certificates created for domains: ${DOMAIN_LIST}"
	echo "Updating certificates in web server service: ${SERVER_SERVICE}"

	secretFiles="chain fullchain privkey"
	secretRmParams=""
	secretAddParams=""

	for secretFile in ${secretFiles}
	do
		secretName="cert-${secretFile}"
		secretRmParams="${secretRmParams} --secret-rm ${secretName}"
		secretAddParams="${secretAddParams} --secret-add ${secretName}"
	done

	docker service update ${secretRmParams} ${SERVER_SERVICE}

	for secretFile in ${secretFiles}
	do
		secretName="cert-${secretFile}"
		echo "Updating service secret: ${secretName}"

		docker secret rm ${secretName}

		cat /certs/live/${CERT_NAME}/${secretFile}.pem | docker secret create \
			-l com.docker.stack.namespace=${SERVER_STACK} \
			${secretName} -
	done

	docker service update ${secretAddParams} ${SERVER_SERVICE}

	echo "Certificates successfully updated!"
else
	echo "Certificates are still valid!"
fi
