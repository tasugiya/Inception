FROM alpine:3.23

RUN apk add --no-cache mariadb mariadb-client

COPY conf/zz-inception.cnf /etc/my.cnf.d/zz-inception.cnf
COPY tools/entrypoint.sh /usr/local/bin/mariadb-entrypoint.sh

RUN chmod 755 /usr/local/bin/mariadb-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/mariadb-entrypoint.sh"]
