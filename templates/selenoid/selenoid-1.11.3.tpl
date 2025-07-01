<@requirement.CONSTRAINT 'selenoid' 'true' />

<@requirement.PARAM name='TEST_PORT' required='false' value='4444' type='port' />
<@requirement.PARAM name='UI_PORT' required='false' value='4480' type='port' />
<@requirement.PARAM name='CHROME_VERSION' value='106.0' />

<@img.TASK 'selenoid-${namespace}' 'imagenarium/selenoid:1.11.3'>
  <@img.PORT PARAMS.TEST_PORT '4444' />
  <@img.BIND '/dev/shm' '/dev/shm' />
  <@img.BIND '/var/opt' '/opt/selenoid/video' />
  <@img.VOLUME '/opt/selenoid/logs' />
  <@img.ENV 'OVERRIDE_VIDEO_OUTPUT_DIR' '/var/opt' />
  <@img.ENV 'CHROME_VERSION' PARAMS.CHROME_VERSION />
  <@img.CONSTRAINT 'selenoid' 'true' />
  <@img.CHECK_PORT '4444' />
</@img.TASK>

<@img.TASK 'selenoid-ui-${namespace}' 'imagenarium/selenoid-ui:1.10.11' "--selenoid-uri http://selenoid-${namespace}:4444">
  <@img.PORT PARAMS.UI_PORT '8080' />
  <@img.CONSTRAINT 'selenoid' 'true' />
  <@img.CHECK_PORT '8080' />
</@img.TASK>