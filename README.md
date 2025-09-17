# vLEI sandbox

This repository can be used to create vLEI credentials for testing purposes.

## Prerequisite

- Python 3.13
- Docker

## Getting Started

Clone this repository.

```
git clone git@github.com:Global-vLEI/vlei-sandbox.git
cd vlei-sandbox
```

Start the demo infrastructure

```
docker compose up -d
```

Run Engagement Context Role credential script

```
./scripts/ecr-credential.sh
```
