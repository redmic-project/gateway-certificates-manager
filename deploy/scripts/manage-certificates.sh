#!/bin/sh

if [ -z "${CERT_NAME}" ] || [ -z "${DOMAIN_LIST}" ] || [ -z "${EMAIL_LIST}" ]
then
	echo "CERT_NAME, DOMAIN_LIST and EMAIL_LIST variables should be defined!"
	exit 1
fi

dhparamFile="/dhparams/dhparam.pem"
if [ ! -e "${dhparamFile}" ]
then
	echo "DHParam not found, generating.."
	docker run --rm --name openssl \
		-v /dhparams:/dhparams \
		frapsoft/openssl dhparam \
			-out "${dhparamFile}" \
			4096
fi

fileToTestUpdate="/certs/live/${CERT_NAME}/chain.pem"
if [ -e "${fileToTestUpdate}" ]
then
	lastUpdateInSecondsBefore="$(stat -c %Y ${fileToTestUpdate})"
else
	lastUpdateInSecondsBefore=0
fi

mkdir -p /work

if ! docker run --rm --name certbot \
	-v /certs:/etc/letsencrypt \
	-v /work:/var/lib/letsencrypt \
	-v ${CERTBOT_LOGS_VOL_NAME}:/var/log/letsencrypt \
	-v /acme:/var/www/html \
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

lastUpdateInSecondsAfter="$(stat -c %Y ${fileToTestUpdate})"

metricsJob="cert-update"
dateInSeconds="$(date +%s)"

if [ "${lastUpdateInSecondsBefore}" != "${lastUpdateInSecondsAfter}" ]
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

		serverStack=$(echo "${SERVER_SERVICE}" | cut -f 1 -d '_')

		cat /certs/live/${CERT_NAME}/${secretFile}.pem | docker secret create \
			-l com.docker.stack.namespace=${serverStack} \
			${secretName} -
	done

	docker service update ${secretAddParams} ${SERVER_SERVICE}

	lastUpdateInSeconds=${lastUpdateInSecondsAfter}

	echo "Certificates successfully updated!"
else
	lastUpdateInSeconds=${lastUpdateInSecondsBefore}

	echo "Certificates are still valid!"
fi

sendMetricCmd="docker run -i --rm --name alpine-curl --network metric-net byrnedo/alpine-curl \
	--silent --data-binary @- ${PUSHGATEWAY_HOST}/metrics/job/${metricsJob}"

cat <<EOF | ${sendMetricCmd}
	# HELP certificates_updated_date_seconds Certificates renewal date in seconds.
	# TYPE certificates_updated_date_seconds gauge
	certificates_updated_date_seconds{label="${CERT_NAME}"} ${lastUpdateInSeconds}
EOF

cat <<EOF | ${sendMetricCmd}
	# HELP certificates_valid_date_seconds Certificates verification date in seconds.
	# TYPE certificates_valid_date_seconds gauge
	certificates_valid_date_seconds{label="${CERT_NAME}"} ${dateInSeconds}
EOF
