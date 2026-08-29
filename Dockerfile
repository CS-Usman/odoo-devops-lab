FROM odoo:17.0

USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io \
    && rm -rf /var/lib/apt/lists/* \
    && (groupadd -g 999 docker 2>/dev/null || true) \
    && usermod -aG docker odoo
COPY ./addons /mnt/extra-addons
RUN chown -R odoo:odoo /mnt/extra-addons
USER odoo
