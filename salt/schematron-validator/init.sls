schematron-validator-repository:
    builder.git_latest:
      - name: git@github.com:elifesciences/schematron-validator.git
      - identity: {{ pillar.elife.projects_builder.key or '' }}
      - rev: {{ salt['elife.rev']() }}
      - branch: {{ salt['elife.branch']() }}
      - target: /srv/schematron-validator/
      - force_fetch: True
      - force_checkout: True
      - force_reset: True
      - submodules: True
      - require:
          - install-composer
          - oracle-java8-installer

    file.directory:
      - name: /srv/schematron-validator
      - user: {{ pillar.elife.deploy_user.username }}
      - group: {{ pillar.elife.deploy_user.username }}
      - recurse:
          - user
          - group
      - require:
          - builder: schematron-validator-repository

schematron-validator-composer-install:
    cmd.run:
      {% if pillar.elife.env in ['prod', 'end2end'] %}
      - name: composer --no-interaction install --classmap-authoritative --no-dev
      {% elif pillar.elife.env in ['ci'] %}
      - name: composer --no-interaction install --classmap-authoritative
      {% else %}
      - name: composer --no-interaction install
      {% endif %}
      - cwd: /srv/schematron-validator/
      - user: {{ pillar.elife.deploy_user.username }}

schematron-validator-gradle-assemble:
    cmd.run:
      - name: ./gradlew assemble
      - cwd: /srv/schematron-validator/backend
      - user: {{ pillar.elife.deploy_user.username }}

schematron-validator-systemd-unit:
    file.managed:
        - name: /lib/systemd/system/schematron-validator-backend.service
        - source: salt://schematron-validator/config/lib-systemd-system-schematron-validator-backend.service
        - template: jinja
        - require:
            - schematron-validator-gradle-assemble
        - require_in:
            - cmd: schematron-validator-backend-sd-reload

schematron-validator-backend-sd-reload:
    cmd.run:
      - name: |
          systemctl daemon-reload
          systemctl enable schematron-validator-backend

schematron-validator-cache:
    file.directory:
        - name: /srv/schematron-validator/var
        - user: {{ pillar.elife.webserver.username }}
        - group: {{ pillar.elife.webserver.username }}
        - dir_mode: 775
        - file_mode: 664
        - recurse:
            - user
            - group
            - mode
        - require:
            - schematron-validator-repository

    cmd.run:
        - name: chmod -R g+s /srv/schematron-validator/var
        - require:
            - file: schematron-validator-cache

schematron-validator-logs:
    file.directory:
        - name: /srv/schematron-validator/var/logs
        - user: {{ pillar.elife.webserver.username }}
        - group: {{ pillar.elife.webserver.username }}
        - dir_mode: 775
        - file_mode: 664
        - recurse:
            - user
            - group
            - mode
        - require:
            - schematron-validator-cache
    cmd.run:
        - name: chmod -R g+s /srv/schematron-validator/var/logs

schematron-validator-backend-service:
    service.running:
        - name: schematron-validator-backend
        - require:
            - schematron-validator-gradle-assemble
            - schematron-validator-systemd-unit
        - watch:
            - schematron-validator-repository

schematron-validator-nginx-vhost:
    file.managed:
      - name: /etc/nginx/sites-enabled/schematron-validator.conf
      - source: salt://schematron-validator/config/etc-nginx-sites-enabled-schematron-validator.conf
      - template: jinja
      - require:
          - nginx-config
          - schematron-validator-composer-install
      - listen_in:
          - service: nginx-server-service
          - service: php-fpm

syslog-ng-schematron-validator-logs:
    file.managed:
        - name: /etc/syslog-ng/conf.d/schematron-validator.conf
        - source: salt://schematron-validator/config/etc-syslog-ng-conf.d-schematron-validator.conf
        - template: jinja
        - require:
            - pkg: syslog-ng
            - schematron-validator-logs
            - schematron-validator-composer-install
            - schematron-validator-gradle-assemble
        - listen_in:
            - service: syslog-ng

schematron-validator-backend-ready:
    cmd.run:
        - name: wait_for_port 8080
        - user: {{ pillar.elife.deploy_user.username }}
        - require:
            - schematron-validator-backend-service
