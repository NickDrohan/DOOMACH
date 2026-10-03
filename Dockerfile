# The relay and the download page, on stock Fedora. Everything is built and
# staged first, by deploy.sh, into out/deploy, laid out as it lands here; the
# image only carries it, and nothing is compiled inside.
FROM fedora:44
COPY out/deploy/ /
RUN chmod 755 /usr/local/bin/relay /usr/local/bin/hedge /usr/local/bin/start
USER nobody
ENV RELAY_BIND_HOST=fly-global-services RELAY_UDP_PORT=5029 RELAY_MAX_ROOMS=32
EXPOSE 5029/udp 8080/tcp
CMD ["/usr/local/bin/start"]
