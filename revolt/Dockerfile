# Revolt (Stoat) all-in-one app service for Railway.
# Bundles the official Revolt backend binaries (API, events, file server,
# proxy, crond, pushd), the official web client and Caddy into one container,
# so every internal hop stays on localhost.
FROM ghcr.io/stoatchat/api:v0.16.4@sha256:0a495b947d2b33398364f0caec3937860fc2d2ceb9be17e2c46705026adcc73c AS api
FROM ghcr.io/stoatchat/events:v0.16.4@sha256:7ab7b3f071b1665df2e4dc272ba6a037defd2b0fa350f222f87050f5e5ac8a16 AS events
FROM ghcr.io/stoatchat/file-server:v0.16.4@sha256:1c98cd336d766efad3f9d8719cd145dadb1cd891ea1c8d3f4f0424196b7525e3 AS autumn
FROM ghcr.io/stoatchat/proxy:v0.16.4@sha256:384c8f947d6a88541c18e2868f23591d4d6a3eb243b44861d92c1c381a526245 AS january
FROM ghcr.io/stoatchat/crond:v0.16.4@sha256:bb33c9b7372f67d20e212575cc08a13df624f2946946975bb270473fc27b78b4 AS crond
FROM ghcr.io/stoatchat/pushd:v0.16.4@sha256:a57c9e2596a0ebbafce60fed7afaf49fb36d1116372fb1f6c23d38f76d2061ab AS pushd
# Web client v0.17.0 (stoat-for-web-v0.17.0, commit 9fd140a)
FROM ghcr.io/stoatchat/for-web:9fd140a@sha256:47bbb515da62e2680c8a6a9f0960c0ead22dff56ba141ff16d0966e1cb050ad8 AS web
FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0 AS caddy

FROM debian:trixie-20261104-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libssl3t64 libdav1d7 openssl xxd \
 && rm -rf /var/lib/apt/lists/*
COPY --from=api /home/nonroot/revolt-delta /opt/revolt/bin/
COPY --from=events /home/nonroot/revolt-bonfire /opt/revolt/bin/
COPY --from=autumn /home/nonroot/revolt-autumn /opt/revolt/bin/
COPY --from=autumn /usr/local/bin/ffmpeg /usr/local/bin/ffprobe /usr/local/bin/
COPY --from=january /home/nonroot/revolt-january /opt/revolt/bin/
COPY --from=crond /home/nonroot/revolt-crond /opt/revolt/bin/
COPY --from=pushd /home/nonroot/revolt-pushd /opt/revolt/bin/
COPY --from=web /app/dist /opt/revolt/web-dist
COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
COPY Caddyfile start.sh /opt/revolt/
RUN chmod +x /opt/revolt/start.sh
ENV PORT=8080
EXPOSE 8080
CMD ["/opt/revolt/start.sh"]
