[![Java CI with Maven](https://github.com/mbuechner/iiif/actions/workflows/maven.yml/badge.svg)](https://github.com/mbuechner/iiif/actions/workflows/maven.yml) [![Docker](https://github.com/mbuechner/iiif/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/mbuechner/iiif/actions/workflows/docker-publish.yml)

# IIIF

This service generates IIIF Presentation API 3.0 manifests from Deutsche Digitale Bibliothek (DDB) records.

## Local build and run

Install JDK 25 LTS and use the Maven wrapper to build and run the tests.

```sh
./mvnw verify
```

On Windows, run `.\mvnw.cmd verify`. Supply `IIIF_DDB_API_KEY_PROD`, `IIIF_DDB_API_KEY_Q1`, and `IIIF_DDB_API_KEY_Q2` as environment variables or put them in a `.env` file in the project root. The file [`.env.example`](src/main/resources/.env.example) lists the available settings. If your local `.env` is already under `src/main/resources`, set `SPRINGDOTENV_DIRECTORY=src/main/resources` in the environment. To start the service, run `java -jar target/iiif.jar` from the project root.

The service listens on port 8080 by default. Set `IIIF_PORT` to change the port or `IIIF_PATH_PREFIX` to serve it under a path such as `/iiif`. When serving the application through a reverse proxy, set `IIIF_BASEURL` to the public origin used in generated manifests.

`IIIF_MAX_METADATA_BYTES` and `IIIF_MAX_MANIFEST_BYTES` set the maximum decoded source and generated manifest sizes in bytes. Each defaults to 64 MiB.

## Docker

```sh
docker build --pull --tag iiif .
docker run --rm --env-file .env --publish 8080:8080 iiif
```

GitHub Actions publishes the image to `ghcr.io/mbuechner/iiif/iiif`. The `latest` tag tracks `main`, and release images have a version tag and the `tagged` alias.
