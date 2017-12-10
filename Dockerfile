FROM alpine

ENV OGP_LISTEN_PORT=12679
ENV OGP_GAME_DIR=/opt/games/

RUN apk --no-cache add perl docker bash gomplate netcat-openbsd sudo apkbuild-cpan

RUN apkbuild-cpan Frontier::Daemon::Forking Crypt::XXTEA

RUN adduser ogp_agent -D \
    && echo 'ogp_agent ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# RUN apt-get update \
#  && apt-get install -y software-properties-common \
#                        python-software-properties \
#                        apt-transport-https \
#                        ca-certificates \
#                        curl \
#                        software-properties-common \
#                        netcat

# RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
#  && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable" \
#  && apt-get update \
#  && apt-cache policy docker-ce \
#  && apt-get install -y  docker-ce

ADD ogpmanager.sh /usr/local/bin/
RUN mv /usr/local/bin/ogpmanager.sh /usr/local/bin/ogpmanager \
    && chmod +x /usr/local/bin/ogpmanager

# RUN curl -sSLf -z /usr/local/bin/gomplate -o /usr/local/bin/gomplate https://github.com/hairyhenderson/gomplate/releases/download/v2.0.0/gomplate_linux-amd64-slim \
#   && chmod 755 /usr/local/bin/gomplate

COPY templates /opt/OGP/templates

COPY OGP-Agent-Linux /opt/agent

ADD docker-health.sh /docker-health.sh

RUN chmod +x /docker-health.sh

RUN cd /opt/agent && cp -avf helpers systemd Crypt EHCP FastDownload File Frontier IspConfig KKrcon php-query Schedule Time ogp_agent.pl ogp_screenrc ogp_agent_run docker-compose.gmod.yml agent_conf.sh extPatterns.txt /opt/OGP/

RUN chown -R ogp_agent /opt/OGP/

HEALTHCHECK CMD ./docker-health.sh

CMD ["ogpmanager"]
