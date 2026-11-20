[![Java CI with Maven](https://github.com/mbuechner/iiif-presentation/actions/workflows/maven.yml/badge.svg)](https://github.com/mbuechner/iiif-presentation/actions/workflows/maven.yml) [![Docker](https://github.com/mbuechner/iiif-presentation/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/mbuechner/iiif-presentation/actions/workflows/docker-publish.yml)

# IIIF

This service generates IIIF Presentation API 3.0 manifests from Deutsche Digitale Bibliothek (DDB) records.

## Local build and run

Install Amazon Corretto 25 LTS and use the Maven wrapper to build and run the tests.

```sh
./mvnw verify
```

On Windows, run `.\mvnw.cmd verify`. Start the service by running `java -jar target/iiif.jar` from the project root. The service uses the public DDB API v2 for production, Q1, and Q2.

The service listens on port 8080 by default. Set `IIIF_PORT` to change the port or `IIIF_PATH_PREFIX` to serve it under a path such as `/iiif`. When serving the application through a reverse proxy, set `IIIF_BASEURL` to the public origin used in generated manifests.

`IIIF_MAX_METADATA_BYTES` and `IIIF_MAX_MANIFEST_BYTES` set the maximum decoded source and generated manifest sizes in bytes. Each defaults to 64 MiB.

Set these options through environment variables or a local `.env` file. The file [`.env.example`](src/main/resources/.env.example) lists the settings. To load an existing `.env` under `src/main/resources`, set `SPRINGDOTENV_DIRECTORY=src/main/resources` in the environment.

## Docker

```sh
docker build --platform linux/amd64 --pull --tag iiif .
docker run --rm --publish 8080:8080 iiif
```

Use `--env-file .env` to pass optional settings to the container from a local file.

The container runs as UID and GID `10001` and listens on port `8080` by default.
Maven builds it in `maven:3-amazoncorretto-25`, and it runs on `amazoncorretto:25`.
An online Maven `verify` writes the CycloneDX SBOM to `target/bom.json`.

## Container releases

- Publishing a stable release queues the workflow on `main` if the tagged commit contains the trigger. For manual runs, use **Actions → Docker** on `main` with optional `release_tag`. Builds use the tagged source, Dockerfile, and commit timestamp.
- Daily at **06:17 UTC**, rebuild if the release commit or either `linux/amd64` base digest changed, or the version tag is missing. Otherwise rescan the existing digest.
- HTTP probe → Trivy (image + optional SBOM) → Cosign → `ghcr.io/mbuechner/iiif/iiif:<release_tag>`. Fixable High/Critical CVEs block promotion. The maintained release also gets `latest` and `tagged`.

Grant the repository write access under GHCR **Manage Actions access**. Set `CONTAINER_RELEASE_TAG` to override the latest stable release and `CONTAINER_HTTP_PATH` to override `/`.
