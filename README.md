# Certificates Manager

Este servicio de encarga de crear y mantener actualizados los certificados SSL empleados por el entorno de REDMIC.

## Descripción

Técnicamente, se trata de un envoltorio que hace uso de la imagen oficial de certbot para obtener y renovar certificados.
Además, implementa una lógica de gestión, fija configuración concreta y añade persistencia.

Es capaz de renovar los certificados solo cuando sea necesario, y se comunica con el servidor web para actualizarle los certificados en uso si se produce la renovación.
Cuando obtiene por primera vez o actualiza certificados, los expone como configuraciones secretas de Docker, para usarse en el servicio del servidor web. Para ello, elimina los valores anteriores (si los hubiese) y actualiza el servicio del servidor web con ellos.
Las siguientes ejecuciones en las que no sea necesario renovar todavía, simplemente se informará de ello, ya que gracias a la persistencia de la configuración se puede comprobar localmente la validez de los certificados.

La programación de renovación se realiza en GitLab, con una tarea de CI/CD que se ejecuta semanalmente. Es importante haber desplegado antes el servicio, para luego poder relanzarlo todas las semanas.

## Uso

Requiere la definición de las siguientes variables de entorno:

| Variable | Descripción | Ejemplo |
|:-:|:-:|:-:|
| **CERT_NAME** | Nombre identificativo del certificado. Es importante elegir un valor fijo para poder renovarlo posteriormente. | redmic.es |
| **DOMAIN_LIST** | Dominios para los que se obtiene el certificado. Se define como una lista separada por comas. | redmic.es,www.redmic.es |
| **EMAIL_LIST** | Direcciones de email utilizadas para obtener el certificado (y recibir notificaciones). Se define como una lista separada por comas. | user1@example.org,user2@example.org |


También se pueden definir opcionalmente las siguientes variables de entorno:

| Variable | Descripción | Valor por defecto |
|:-:|:-:|:-:|
| SERVER_SERVICE | Nombre del servicio (*Docker Swarm*, `<stack>_<service-name>`) del servidor web. | `nginx-proxy_nginx-proxy` |
| CERTBOT_CONFIG_VOL_NAME | Nombre del volumen Docker donde se almacena la configuración de certbot y los certificados (se montará sobre `/etc/letsencrypt`). | `certbot-config-vol` |
| CERTBOT_WORK_VOL_NAME | Nombre del volumen Docker donde se almacenan ficheros internos de certbot (se montará sobre `/var/lib/letsencrypt`). | `certbot-work-vol` |
| CERTBOT_LOGS_VOL_NAME | Nombre del volumen donde se guardan los logs de certbot, por si hace falta consultarlos (se montará sobre `/var/log/letsencrypt`). | `certbot-logs-vol` |
| ACME_VOL_NAME | Nombre del volumen donde almacenar los ficheros usados para verificar (responder a los *challenges*) el dominio a certificar. También debe ser montado por el servidor web, para que exponga los ficheros en la ruta `/.well-known/acme-challenge/`. No será necesario si la validación se realiza mediante registros DNS (aún no disponible). | `acme-vol` |
| PUSHGATEWAY_HOST | Dirección del servicio Pushgateway al que se enviarán las métricas Prometheus de monitorización. | `pushgateway:9091` |

## Métricas

Siempre que se ejecuta con éxito el servicio, se exponen métricas *Prometheus* para conocer el estado de los certificados y poder generar alertas si algo no ha ido bien.

Existen 2 métricas, etiquetadas con el nombre del certificado:
* **certificates_updated_date_seconds**: Fecha en segundos de la última actualización del certificado.
* **certificates_valid_date_seconds**: Fecha en segundos del último intento de actualización (necesario o no) del certificado.
