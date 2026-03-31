# Dynamic Docker Runners — Setup Guide

## Overview

This setup turns your Ubuntu host (`ubunturunner`) into a **Docker host** that spins up
ephemeral GitHub Actions runners as containers. Each runner picks up **one job**,
executes it, and **auto-destroys** — just like GitHub-hosted runners but on your own infra.

```
┌─────────────────────────────────────────────┐
│  Ubuntu Host (ubunturunner)                 │
│                                             │
│   ┌──────────┐ ┌──────────┐ ┌──────────┐   │
│   │ Runner 1 │ │ Runner 2 │ │ Runner 3 │   │
│   │ (docker) │ │ (docker) │ │ (docker) │   │
│   │ 1 job    │ │ 1 job    │ │ 1 job    │   │
│   │ then die │ │ then die │ │ then die │   │
│   └──────────┘ └──────────┘ └──────────┘   │
│                                             │
│   Each container has: JDK 17, Maven, Git    │
└─────────────────────────────────────────────┘
```

---

## Step 1 — Prepare the Ubuntu Host

SSH into your `ubunturunner` machine and install Docker:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
sudo apt install -y docker.io docker-compose-v2

# Start Docker and enable on boot
sudo systemctl start docker
sudo systemctl enable docker

# Add your user to the docker group (so you don't need sudo)
sudo usermod -aG docker $USER

# IMPORTANT: Log out and log back in for group change to take effect
exit
# SSH back in
```

Verify Docker is working:

```bash
docker run hello-world
docker compose version
```

---

## Step 2 — Create a GitHub PAT

You need a Personal Access Token to register runners via the API.

1. Go to: https://github.com/settings/tokens
2. Click **"Generate new token (classic)"**
3. Set scopes: **`repo`** (full control)
4. Copy the token — you'll use it in the next step

> For an org-level runner, you'd also need `admin:org` scope.

---

## Step 3 — Copy Files to the Host

Copy these files to your Ubuntu host:

```
/home/<user>/docker-runner/
├── Dockerfile
├── entrypoint.sh
├── docker-compose.yml
├── manage.sh
├── .env.example
└── .env              ← you create this
```

```bash
# On the Ubuntu host
mkdir -p ~/docker-runner
cd ~/docker-runner

# Copy the files (scp, git clone, or paste them)
# Then create your .env
cp .env.example .env
nano .env
```

Edit `.env` with your values:

```bash
GITHUB_TOKEN=ghp_your_actual_token_here
GITHUB_REPO=sathishbabudevops/javaapp
```

Make the management script executable:

```bash
chmod +x manage.sh
```

---

## Step 4 — Build the Runner Image

```bash
cd ~/docker-runner
./manage.sh build
```

This builds a Docker image containing: Ubuntu 22.04, JDK 17, Maven, Git,
Python3, and the GitHub Actions runner binary. Takes about 2-3 minutes first time.

---

## Step 5 — Start Runners

```bash
# Start 1 runner
./manage.sh start

# Start 3 runners for parallel jobs
./manage.sh start 3

# Check status
./manage.sh status

# View logs
./manage.sh logs
```

You should see output like:

```
============================================
  GitHub Actions Dynamic Runner
============================================
  Repo:   sathishbabudevops/javaapp
  Runner: gh-runner-1717012345-1
  Labels: self-hosted,linux,docker,dynamic
  Mode:   Ephemeral (single job, auto-cleanup)
============================================
Registration token acquired.
Runner is ready. Waiting for a job...
```

---

## Step 6 — Verify in GitHub

Go to your repo → **Settings** → **Actions** → **Runners**

You should see runners appear with labels: `self-hosted, linux, docker, dynamic`
and status **Idle**.

---

## Step 7 — Add the Workflow

Copy `docker-runner-coverage.yml` to your repo:

```
.github/workflows/docker-runner-coverage.yml
```

The key line is:

```yaml
runs-on: [self-hosted, linux, docker, dynamic]
```

This matches the labels from the Docker runners.

Push to main or trigger manually — the runner picks up the job,
runs it, and the container exits.

---

## Step 8 — Auto-Replenish Runners (Optional)

Since ephemeral runners exit after one job, you need to replenish them.

### Option A — Cron job (simplest)

```bash
# Edit crontab
crontab -e

# Add this line — starts 2 fresh runners every 5 minutes
*/5 * * * * cd /home/<user>/docker-runner && ./manage.sh cleanup && ./manage.sh start 2 >> /tmp/runner-cron.log 2>&1
```

### Option B — Systemd service with restart loop

```bash
sudo nano /etc/systemd/system/github-runner-pool.service
```

```ini
[Unit]
Description=GitHub Actions Dynamic Runner Pool
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=<your-user>
WorkingDirectory=/home/<user>/docker-runner
ExecStart=/bin/bash -c 'while true; do ./manage.sh cleanup; ./manage.sh start 2; sleep 300; done'
Restart=always
RestartSec=10
EnvironmentFile=/home/<user>/docker-runner/.env

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable github-runner-pool
sudo systemctl start github-runner-pool

# Check status
sudo systemctl status github-runner-pool
```

---

## Useful Commands

| Command                   | What it does                              |
|---------------------------|-------------------------------------------|
| `./manage.sh build`      | Build/rebuild the runner Docker image     |
| `./manage.sh start`      | Start 1 ephemeral runner                  |
| `./manage.sh start 5`    | Start 5 runners in parallel               |
| `./manage.sh status`     | Show running + stopped containers         |
| `./manage.sh logs`       | Tail logs of first running container      |
| `./manage.sh stop`       | Stop and remove all runner containers     |
| `./manage.sh cleanup`    | Remove only stopped (completed) containers|

---

## How Ephemeral Mode Works

```
1. Container starts → registers with GitHub as ephemeral runner
2. GitHub queues a job → runner picks it up
3. Job completes → runner process exits
4. Container exits → cleanup trap deregisters from GitHub
5. manage.sh or cron starts a fresh container → cycle repeats
```

Key point: every job runs on a **clean container** — no leftover files,
no stale caches, no cross-job contamination. Exactly like GitHub-hosted runners.

---

## Troubleshooting

| Problem                            | Fix                                              |
|------------------------------------|--------------------------------------------------|
| "Failed to get registration token" | Check PAT has `repo` scope and hasn't expired    |
| Runner shows but never picks jobs  | Labels in workflow must match runner labels       |
| Docker permission denied           | Run `sudo usermod -aG docker $USER` then re-login|
| Container exits immediately        | Run `./manage.sh logs` to see the error          |
| Runner image too large             | Normal — ~1.2GB with JDK + Maven                 |
