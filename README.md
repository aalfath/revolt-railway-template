# Revolt on Railway

A Railway template for [Revolt](https://github.com/revoltchat/self-hosted) (now developed as **Stoat**, [stoatchat](https://github.com/stoatchat)), the open-source chat platform with servers, text channels, direct messages, groups, roles, file sharing and bots, in a web app much like Discord.

**Version:** backend v0.16.4 (`ghcr.io/stoatchat/api`, `events`, `file-server`, `proxy`, `crond`, `pushd`) and web client v0.17.0 (`ghcr.io/stoatchat/for-web:9fd140a`), all pinned by digest in [`revolt/Dockerfile`](revolt/Dockerfile).

## What it deploys

| Service | Source | Purpose |
|---|---|---|
| **Revolt** | this repo, folder [`revolt/`](revolt) | One container with the official Revolt binaries: API (`/api`), events WebSocket (`/ws`), file server (`/autumn`), link-preview proxy (`/january`), the scheduled-task daemon and the push-notification daemon, plus the official web client, behind Caddy on `PORT`. Health check: `/api/`. |
| **RabbitMQ** | this repo, folder [`rabbitmq/`](rabbitmq) | Internal message broker (official `rabbitmq:4.4.0-alpine`). No volume: it only holds transient queues. |
| **MongoDB** | Railway MongoDB | Database (accounts, servers, channels, messages). |
| **Redis** | Railway Redis | Events and presence. |
| **Bucket** | Railway Bucket | Uploaded files (attachments, avatars, icons, emojis), encrypted by Revolt before upload. |

Why one container: the upstream file server and proxy listen on IPv4 only, and Railway's private network is IPv6. Running every Revolt process in one container keeps all internal traffic on `localhost`, exactly as the official [Caddyfile](https://github.com/revoltchat/self-hosted/blob/main/Caddyfile) routes it.

The wrapper ([`revolt/start.sh`](revolt/start.sh), [`revolt/Caddyfile`](revolt/Caddyfile)) writes `Revolt.toml` from the variables below, derives the file-encryption key and the Web Push (VAPID) key pair from `REVOLT_SECRET`, injects the public URL into the web client, and runs the processes. If any process exits, the container exits and Railway restarts it.

**Not included:** voice and video calls. They need LiveKit with a UDP port range, which Railway doesn't offer. Text chat, files, embeds and Web Push notifications work.

## Variables

Revolt service:

| Variable | Default | Notes |
|---|---|---|
| `REVOLT_SECRET` | `${{secret(48)}}` | Instance secret. The file-encryption key and the VAPID keys are derived from it. **Never change it after the first upload**, or existing files can't be decrypted. |
| `MONGODB_URL` | `${{MongoDB.MONGO_URL}}` | MongoDB connection. |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | Redis connection. |
| `RABBITMQ_HOST` | `${{RabbitMQ.RAILWAY_PRIVATE_DOMAIN}}` | RabbitMQ host on the private network. |
| `RABBITMQ_USER` / `RABBITMQ_PASSWORD` | `${{RabbitMQ.RABBITMQ_DEFAULT_USER}}` / `${{RabbitMQ.RABBITMQ_DEFAULT_PASS}}` | RabbitMQ login. |
| `S3_ENDPOINT`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | `${{Bucket.ENDPOINT}}` … | The Railway bucket. |
| `PORT` | `8080` | Port Caddy listens on. |

RabbitMQ service: `RABBITMQ_DEFAULT_USER` (`revolt`) and `RABBITMQ_DEFAULT_PASS` (`${{secret(32)}}`).

Optional, not set by the template:

- `REVOLT_PUBLIC_URL`: the URL users open, for example `https://chat.YOUR-DOMAIN`. Defaults to `https://` plus the Railway domain. Set it when you add a custom domain.
- `REVOLT_INVITE_ONLY=true`: require an invite code to sign up. Codes are documents in the `invites` collection of the `revolt` database (see [the upstream guide](https://github.com/revoltchat/self-hosted#making-your-instance-invite-only)).
- Any upstream setting as `REVOLT__<SECTION>__<KEY>`, for example email verification through SMTP: `REVOLT__API__SMTP__HOST`, `REVOLT__API__SMTP__USERNAME`, `REVOLT__API__SMTP__PASSWORD`, `REVOLT__API__SMTP__FROM_ADDRESS`. See the defaults in [`Revolt.toml`](https://github.com/stoatchat/stoatchat/blob/main/crates/core/config/Revolt.toml).

Registration is open by default and there is no admin account: the first person to sign up is an ordinary user. Use `REVOLT_INVITE_ONLY` if the instance shouldn't be public.

## Updates

The template builds from this repo's `main` branch. When a new Revolt release is pinned here, Railway shows deployers an "update available" notice. Applying it rebuilds the services, and the API runs any database migrations on start. Read [`CHANGELOG.md`](CHANGELOG.md) before applying an update.

## Local test

`docker compose up --build`, create the bucket (command at the end of [`compose.yml`](compose.yml)), then open http://localhost:42297 and create an account.
