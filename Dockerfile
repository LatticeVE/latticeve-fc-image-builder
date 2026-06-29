# syntax=docker/dockerfile:1
ARG ALPINE_VERSION=3.21
FROM alpine:${ALPINE_VERSION}

ARG ALPINE_VERSION=3.21
ARG TARGETARCH

RUN apk add --no-cache \
      e2fsprogs \
      nginx \
      openrc

# LatticeVE supplies the Firecracker kernel separately, so this rootfs does not
# ship /lib/modules. Remove OpenRC services that would try to load modules.
RUN rc-update del hwdrivers sysinit 2>/dev/null || true; \
    rc-update del modules boot 2>/dev/null || true; \
    rc-update del modules sysinit 2>/dev/null || true; \
    rc-update add devfs sysinit; \
    rc-update add sysfs sysinit; \
    rc-update add cgroups sysinit; \
    rc-update add networking boot; \
    rc-update add local default; \
    rc-update add nginx default

RUN cat > /etc/network/interfaces <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

RUN mkdir -p /run/nginx /var/lib/nginx/html; \
    cat > /etc/nginx/http.d/default.conf <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/lib/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

RUN cat > /var/lib/nginx/html/index.html <<EOF
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>LatticeVE Firecracker nginx</title>
  </head>
  <body>
    <h1>It works from LatticeVE Firecracker</h1>
    <p>Alpine ${ALPINE_VERSION} nginx rootfs (${TARGETARCH}).</p>
  </body>
</html>
EOF

COPY files/latticeve-resize.start /etc/local.d/latticeve-resize.start

RUN chmod +x /etc/local.d/latticeve-resize.start; \
    sed -i '/tty[0-9]::respawn/d' /etc/inittab || true
