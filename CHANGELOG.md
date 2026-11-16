# Changelog

## 2026-11-16: Deploy on Railway button

- README: add the Deploy on Railway button for the published template (`revolt`). No change to the services.

## 2026-11-16: first release

- Revolt (Stoat) backend v0.16.4 and web client v0.17.0, official images pinned by digest.
- One app service (API, events, file server, proxy, crond, pushd, web client, Caddy), RabbitMQ 4.4.0, Railway MongoDB, Railway Redis and a Railway Bucket for files.
- Voice and video calls are not included (LiveKit needs UDP ports).
