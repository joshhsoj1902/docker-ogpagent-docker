FROM joshhsoj1902/docker-ogpagent

MAINTAINER joshhsoj1902

ADD ogpmanager.sh /usr/local/bin/
RUN mv /usr/local/bin/ogpmanager.sh /usr/local/bin/ogpmanager \
    && chmod +x /usr/local/bin/ogpmanager

COPY templates /opt/OGP/templates

RUN curl -sSLf -z /usr/local/bin/gomplate -o /usr/local/bin/gomplate https://github.com/hairyhenderson/gomplate/releases/download/v2.0.0/gomplate_linux-amd64-slim \
  && chmod 755 /usr/local/bin/gomplate
