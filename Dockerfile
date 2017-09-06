FROM joshhsoj1902/docker-ogpagent

MAINTAINER joshhsoj1902

ADD ogpmanager.sh /usr/local/bin/
RUN mv /usr/local/bin/ogpmanager.sh /usr/local/bin/ogpmanager \
    && chmod +x /usr/local/bin/ogpmanager

COPY templates /opt/OGP/templates

RUN curl -sSLf -z /usr/local/bin/gomplate -o /usr/local/bin/gomplate https://github.com/hairyhenderson/gomplate/releases/download/v2.0.0/gomplate_linux-amd64-slim \
  && chmod 755 /usr/local/bin/gomplate

RUN apt-get update \
 && apt-get install -y software-properties-common \
                       python-software-properties \
                       apt-transport-https \
                       ca-certificates \
                       curl \
                       software-properties-common

RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \
 && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu xenial stable" \
 && apt-get update \
 && apt-cache policy docker-ce \
 && apt-get install -y  docker-ce


COPY OGP-Agent-Linux /opt/agent

RUN cd /opt/agent && cp -avf systemd Crypt EHCP FastDownload File Frontier IspConfig KKrcon php-query Schedule Time ogp_agent.pl ogp_screenrc ogp_agent_run docker-compose.gmod.yml agent_conf.sh extPatterns.txt /opt/OGP/

RUN chown --preserve-root -R ogp_agent /opt/OGP/
