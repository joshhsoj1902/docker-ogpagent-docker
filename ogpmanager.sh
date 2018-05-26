#!/bin/bash

/usr/local/bin/gomplate -f /opt/OGP/templates/Config.pm.tmpl -o /opt/OGP/Cfg/Config.pm
/usr/local/bin/gomplate -f /opt/OGP/templates/Config.tmpl.yml -o /opt/OGP/Cfg/Config.yml
/usr/local/bin/gomplate -f /opt/OGP/templates/Preferences.pm.tmpl -o /opt/OGP/Cfg/Preferences.pm

chmod +x /opt/OGP/ogp_agent_run
echo "Starting DockerOGP"

tail -F /opt/OGP/ogp_agent.log &

su ogp_agent -c "cd /opt/OGP/; ./ogp_agent_run"
