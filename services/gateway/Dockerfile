# World Monitor gateway for Railway (community template): Caddy with a
# basic-auth login in front of the dashboard. Routing is in the Caddyfile; the
# login block is written at start by entrypoint.sh from WM_UI_USERNAME /
# WM_UI_PASSWORD (bcrypt-hashed in the container).
FROM caddy:2.11.7-alpine

COPY Caddyfile /etc/caddy/Caddyfile
COPY entrypoint.sh /opt/railway/entrypoint.sh
RUN chmod 0755 /opt/railway/entrypoint.sh && sh -n /opt/railway/entrypoint.sh

ENV PORT=8080
EXPOSE 8080

CMD ["/opt/railway/entrypoint.sh"]
