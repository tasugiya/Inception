FROM alpine:3.23

ARG DOMAIN_NAME

RUN apk add --no-cache nginx openssl

RUN test -n "$DOMAIN_NAME" \
	&& mkdir -p /etc/nginx/ssl \
	&& openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 365 \
		-subj "/CN=${DOMAIN_NAME}" \
		-addext "subjectAltName=DNS:${DOMAIN_NAME}" \
		-keyout /etc/nginx/ssl/inception.key \
		-out /etc/nginx/ssl/inception.crt \
	&& chmod 600 /etc/nginx/ssl/inception.key

COPY conf/default.conf /etc/nginx/http.d/default.conf

RUN sed -i "s|__DOMAIN_NAME__|${DOMAIN_NAME}|g" /etc/nginx/http.d/default.conf

CMD ["nginx", "-g", "daemon off;"]
