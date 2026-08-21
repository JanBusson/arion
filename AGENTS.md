# AGENTS.md

## Project overview

This repository contains a self-hosted music streaming application.

The system should allow the owner to store legally obtained or explicitly shared audio files on a private Linux server and play them:

- on an Android phone through an APK
- on a PC through a browser

This is primarily a learning project for backend development, Linux, Docker, networking, storage, CI/CD, and mobile/web development. It is not intended to be a public Spotify clone.

## How to interpret this document

This file defines the current direction, constraints, and learning goals of the project. It is not a fixed implementation blueprint.

Architectural and technology choices may change during development when:

- a simpler or more suitable solution becomes apparent
- practical constraints on the home server require an adjustment
- implementation experience reveals that an earlier assumption was wrong
- a different approach provides greater learning value
- established industry practice suggests a better design

Do not treat planned components as mandatory merely because they are listed here. Preserve the overall product goal and explain meaningful deviations before introducing them.

## Current infrastructure

Server:

- Dell OptiPlex 5060 Micro
- Intel Core i5-8500T
- 16 GB RAM
- 256 GB SSD
- Ubuntu Server 26.04 LTS
- Headless operation over SSH
- Fixed local IP configured in the router
- No dedicated GPU

The server is intended to run the application through Docker Compose.

## Planned architecture

```text
Android app (Flutter APK) ─┐
                           ├── HTTP API / audio streaming ── FastAPI
Browser app (Flutter Web) ─┘                                 │
                                                            ├── PostgreSQL
                                                            ├── Audio storage
                                                            └── Background processing
```

Current technology direction:

- Frontend: Flutter for Android and web
- Backend: Python with FastAPI
- Database: PostgreSQL
- Deployment: Docker Compose
- Reverse proxy: Caddy or Nginx, to be selected later
- CI/CD: GitHub Actions
- Container registry: GitHub Container Registry (GHCR)
- Production deployment: the server pulls versioned images and restarts services

Do not introduce Kubernetes. It is unnecessary for the current project.

## Storage strategy

Start with local filesystem storage on the server.

Design storage access behind an abstraction so it can later be replaced by an S3-compatible implementation without rewriting business logic.

Possible later storage backend:

- SeaweedFS running on the same server

PostgreSQL should store metadata and object/file references, not the audio binary itself.

## Audio import and metadata

Preferred metadata pipeline:

1. Read embedded metadata and cover art with Mutagen.
2. Read technical properties such as duration, codec, bitrate, and sample rate with ffprobe.
3. Fall back to parsing the filename if tags are missing.
4. Allow manual correction.
5. Later, optionally add Chromaprint, AcoustID, MusicBrainz, and Cover Art Archive lookups.

Do not depend on online music recognition for the first version.

## First useful version

The initial version should support:

- importing an audio file
- extracting title, artist, album, duration, and cover
- listing and searching tracks
- playing audio in Android and browser clients
- seeking within a track using HTTP Range requests
- creating and editing playlists
- editing incorrect metadata

The application is single-user initially. Do not add public registration, social features, recommendations, AI features, or unrelated product ideas unless explicitly requested.

## Network access

Initial access should be private:

- inside the home network through the server IP or local hostname
- later, remote private access through Tailscale

A purchased domain and public port forwarding are not required.

Do not expose the application publicly by default.

## CI/CD target

The desired workflow is:

```text
Push or merge to main
        ↓
GitHub Actions runs tests
        ↓
Build Docker images
        ↓
Push versioned images to GHCR
        ↓
Deploy on the Dell server
        ↓
docker compose pull
docker compose up -d
```

A self-hosted GitHub Actions runner may be used for the deployment step. Do not run untrusted pull-request code on that runner.

## Security and repository rules

- Never commit passwords, tokens, private keys, music files, or `.env` files.
- Provide `.env.example` files with placeholder values.
- Keep secrets on the server or in GitHub Actions secrets.
- Use SSH keys for server access when configured.
- Use only legally obtained or explicitly licensed audio in demos and tests.
- Keep sample audio files small and freely licensed.

## Primary learning objective

The main objective is not only to make the application work, but to learn practices that are relevant in professional Data and AI environments.

Prefer approaches that provide realistic experience with:

- reproducible data ingestion and processing
- clear separation of raw files, metadata, and derived data
- data quality checks and validation
- observable pipelines and services
- structured logging and useful metrics
- versioned schemas, APIs, and container images
- automated testing, CI/CD, and repeatable deployments
- secure handling of credentials and configuration
- storage abstractions and open interfaces
- maintainable Python, SQL, Docker, and Linux workflows
- documentation of architectural decisions and operational procedures

Do not add complexity only to imitate an enterprise system. Use industry-standard patterns where they solve a real problem or create meaningful learning value for Data Engineering, Analytics, MLOps, or applied AI.

## Engineering preferences

- Keep implementations simple and suitable for one small home server.
- Avoid premature microservices.
- Prefer a modular monolith unless there is a concrete reason to split services.
- Make small, reviewable changes.
- Explain significant architectural decisions briefly.
- Ask before introducing a major framework, service, or architecture change.
- Do not generate unrelated feature ideas.
- Do not over-engineer the first version.
- Add tests for important backend behavior, especially metadata parsing and HTTP Range streaming.
- Document commands needed to run, test, build, and deploy the project.

## Current project state

- Linux server is installed and reachable over SSH.
- A fixed local IP has been configured.
- The repository structure and application code have not yet been finalized.
- GitHub Actions is desired from the beginning, even if it is more advanced than strictly necessary.
