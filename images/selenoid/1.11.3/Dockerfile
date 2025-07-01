FROM aerokube/selenoid:1.11.3
RUN apk add --update --no-cache bash curl jq
COPY browsers.json /etc/selenoid/
COPY *.sh /
RUN chmod +x /*.sh
ENTRYPOINT ["/imagenarium-entrypoint.sh"]
