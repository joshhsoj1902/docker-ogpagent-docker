#!/bin/bash

/usr/local/bin/gomplate -f /opt/OGP/templates/Config.pm.tmpl -o /opt/OGP/Cfg/Config.pm
/usr/local/bin/gomplate -f /opt/OGP/templates/Preferences.pm.tmpl -o /opt/OGP/Cfg/Preferences.pm

chmod +x /opt/OGP/ogp_agent_run
echo "Starting DockerOGP"
su ogp_agent -c "cd /opt/OGP/; ./ogp_agent_run"
