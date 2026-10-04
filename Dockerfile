# The relay, the pages and the bot league, on stock Fedora. Everything is built and
# staged first, by deploy.sh, into out/deploy, laid out as it lands here; the
# image only carries it, and nothing is compiled inside.
FROM fedora:44
# setpriv, for the start script to drop root: the base image leaves it out
RUN dnf -y install util-linux && dnf clean all
COPY out/deploy/ /
RUN chmod 755 /usr/local/bin/relay /usr/local/bin/hedge /usr/local/bin/arena /usr/local/bin/start
# start runs as root to prepare the league's disk, then drops to nobody
ENV RELAY_BIND_HOST=fly-global-services RELAY_UDP_PORT=5029 RELAY_MAX_ROOMS=32 ARENA_DUTY=5 RELAY_WATCH_FILE=/data/league/watch.bin RELAY_LEAGUE_FILE=/data/league/league.bin RELAY_FILL_SECONDS=120 RELAY_SHY_ONE_IN=10
EXPOSE 5029/udp 8080/tcp
CMD ["/usr/local/bin/start"]
