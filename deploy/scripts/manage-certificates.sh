#!/bin/sh

if [ -z "${CERT_NAME}" ] || [ -z "${DOMAIN_LIST}" ] || [ -z "${EMAIL_LIST}" ]
then
	echo "CERT_NAME, DOMAIN_LIST and EMAIL_LIST variables should be defined!"
	exit 1
fi

mkdir -p \
	/work/certs \
	/work/lib \
	/work/log

docker run --rm \
	-v /work/certs:/etc/letsencrypt \
	-v /work/lib:/var/lib/letsencrypt \
	-v /work/log:/var/log/letsencrypt \
	-v /var/www/html:/var/www/html \
	certbot/certbot certonly \
		--expand --webroot -w /var/www/html/ \
		--cert-name ${CERT_NAME} \
		-m ${EMAIL_LIST} --agree-tos --no-eff-email \
		-d ${DOMAIN_LIST} \
		--post-hook "export UPDATED=1"

if [ ${UPDATED} -eq "1" ]
then
	echo "Certificates created for domains: ${DOMAIN_LIST}"

	serverStack=${SERVER_STACK:-nginx-proxy}
	serverService=${SERVER_SERVICE:-${serverStack}_${serverStack}}
	secretFiles="chain fullchain privkey"

	if [ ! -e /work/dhparam.pem ]
	then
		echo "DHParam not found, generating.."
		openssl dhparam -out /work/dhparam.pem 4096
		dhparamUpdated="1"
	fi

	echo "Updating certificates in web server service: ${serverService}"

	for secretFile in ${secretFiles}
	do
		secretName="cert-${secretFile}"
		echo "Updating service secret: ${secretName}"

		docker service update \
			--secret-rm ${secretName} \
			${serverService}

		docker secret rm ${secretName}

		docker secret create \
			-l com.docker.stack.namespace ${serverStack}
			${secretName}
			/work/certs/live/${CERT_NAME}/${secretFile}.pem

		docker service update \
			--secret-add ${secretName} \
			${serverService}
	done

	if [ ${dhparamUpdated} -eq "1" ]
	then
		configName="cert-dhparam"
		echo "Updating service config: ${configName}"

		docker service update \
			--config-rm ${configName} \
			${serverService}

		docker config rm ${configName}

		docker config create \
			-l com.docker.stack.namespace ${serverStack}
			${configName}
			/work/dhparam.pem

		docker service update \
			--config-add ${configName} \
			${serverService}
	fi

	echo "Certificates successfully updated"
else
	echo "Certificates creation failed!"
	exit 1
fi
