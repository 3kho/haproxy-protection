FROM alpine:latest
RUN apk update && apk add tor
COPY ./tor/torrc.default /etc/tor/torrc
RUN chmod -R 700 /var/lib/tor/
RUN chown -R tor /var/lib/tor/
RUN chown -R tor /etc/tor
USER tor
ENTRYPOINT [ "tor" ]
CMD [ "-f", "/etc/tor/torrc" ]
