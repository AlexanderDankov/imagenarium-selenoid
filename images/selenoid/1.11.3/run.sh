#!/bin/bash

docker pull selenoid/chrome:${CHROME_VERSION}
docker pull selenoid/video-recorder:latest-release

sed -i -e "s|CHROME_VERSION|${CHROME_VERSION}|g" /etc/selenoid/browsers.json

exec /usr/bin/selenoid \
-listen :4444 \
-conf /etc/selenoid/browsers.json \
-enable-file-upload \
-log-output-dir /opt/selenoid/logs \
-video-output-dir /opt/selenoid/video \
-save-all-logs \
#-container-network net-$NAMESPACE $@
