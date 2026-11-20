[![Java CI with Maven](https://github.com/mbuechner/iiif/actions/workflows/maven.yml/badge.svg)](https://github.com/mbuechner/iiif/actions/workflows/maven.yml) [![Docker](https://github.com/mbuechner/iiif/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/mbuechner/iiif/actions/workflows/docker-publish.yml)

# IIIF

This service generates IIIF Presentation API 3.0 manifests from Deutsche Digitale Bibliothek (DDB) records.

## Local build and run

Install JDK 25 LTS and use the Maven wrapper to build and run the tests.

```sh
./mvnw verify
```

On Windows, run `.\mvnw.cmd verify`. Start the service by running `java -jar target/iiif.jar` from the project root. The service uses the public DDB API v2 for production, Q1, and Q2.

The service listens on port 8080 by default. Set `IIIF_PORT` to change the port or `IIIF_PATH_PREFIX` to serve it under a path such as `/iiif`. When serving the application through a reverse proxy, set `IIIF_BASEURL` to the public origin used in generated manifests.

`IIIF_MAX_METADATA_BYTES` and `IIIF_MAX_MANIFEST_BYTES` set the maximum decoded source and generated manifest sizes in bytes. Each defaults to 64 MiB.

Set these options through environment variables or a local `.env` file. The file [`.env.example`](src/main/resources/.env.example) lists the settings. To load an existing `.env` under `src/main/resources`, set `SPRINGDOTENV_DIRECTORY=src/main/resources` in the environment.

## Docker

```sh
docker build --pull --tag iiif .
docker run --rm --publish 8080:8080 iiif
```

Use `--env-file .env` to pass optional settings to the container from a local file.

GitHub Actions publishes the image to `ghcr.io/mbuechner/iiif/iiif`. The `latest` tag tracks `main`, and release images have a version tag and the `tagged` alias.
