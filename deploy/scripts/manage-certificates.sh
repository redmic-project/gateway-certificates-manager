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

serverStack=$(echo "${SERVER_SERVICE}" | cut -f 1 -d '_')

metricsJob="cert-update"
dateInSeconds="$(date +%s)"

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
		secretAddParams="${secretAddParams} --secret-add source=${secretName},target=/etc/nginx/certs/${secretFile}.pem"
	done

	docker service update ${secretRmParams} ${SERVER_SERVICE}

	for secretFile in ${secretFiles}
	do
		secretName="cert-${secretFile}"
		echo "Updating service secret: ${secretName}"

		docker secret rm ${secretName}

		cat /certs/live/${CERT_NAME}/${secretFile}.pem | docker secret create \
			-l com.docker.stack.namespace=${serverStack} \
			${secretName} -
	done

	docker service update ${secretAddParams} ${SERVER_SERVICE}

	echo "Certificates successfully updated!"
fi

lastUpdateInSeconds="$(stat -c %Y ${fileToTestUpdate})"

cat <<EOF | docker run -i --rm --name alpine-curl --network metric-net byrnedo/alpine-curl --data-binary @- \
	${PUSHGATEWAY_HOST}/metrics/job/${metricsJob}
	# HELP certificates_updated_date_seconds Certificates update date in seconds.
	# TYPE certificates_updated_date_seconds gauge
	certificates_updated_date_seconds{label="${CERT_NAME}"} ${lastUpdateInSeconds}
EOF

cat <<EOF | docker run -i --rm --name alpine-curl --network metric-net byrnedo/alpine-curl --data-binary @- \
	${PUSHGATEWAY_HOST}/metrics/job/${metricsJob}
	# HELP certificates_valid_date_seconds Certificates verification date in seconds.
	# TYPE certificates_valid_date_seconds gauge
	certificates_valid_date_seconds{label="${CERT_NAME}"} ${dateInSeconds}
EOF

echo "Certificates are still valid!"
