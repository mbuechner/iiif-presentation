import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


BUILD_INPUTS_LABEL = "de.ddb.labs.iiif.build-inputs"
REPOSITORY = r"[a-z0-9][a-z0-9./_-]*(?::[0-9]+/[a-z0-9][a-z0-9./_-]*)?"
TAG = r"[A-Za-z0-9_][A-Za-z0-9._-]{0,127}"
DIGEST = re.compile(r"sha256:[0-9a-f]{64}")
FROM = re.compile(rf"FROM\s+({REPOSITORY}:{TAG})(?:\s+AS\s+[a-z0-9][a-z0-9_.-]*)?", re.IGNORECASE)


def inspect(image, *options, allow_missing=False):
    try:
        result = subprocess.run(
            ["docker", "buildx", "imagetools", "inspect", *options, image],
            capture_output=True,
            timeout=90,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f"Could not inspect {image}: {error}") from error

    if result.returncode:
        error = result.stderr.decode(errors="replace").strip()
        missing_image = re.search(rf"(?:^|[ :]){re.escape(image)}: not found\s*$", error, re.IGNORECASE)
        manifest_unknown = re.search(r"(?:^|:\s+)manifest[ _]unknown(?:\s|:|$)", error, re.IGNORECASE)
        registry_failure = re.search(r"failed to authorize|unexpected status.*\b(?:401|403|429|5\d{2})\b", error,
                                     re.IGNORECASE)
        if allow_missing and not registry_failure and (missing_image or manifest_unknown):
            return None
        raise SystemExit(f"Could not inspect {image}: {error or f'exit code {result.returncode}'}")
    return result.stdout


def base_images(dockerfile):
    names = []
    for line_number, line in enumerate(dockerfile.read_text(encoding="utf-8").splitlines(), start=1):
        fields = line.split(maxsplit=1)
        if not fields or fields[0].upper() != "FROM":
            continue
        base = FROM.fullmatch(line.strip())
        if base is None:
            raise SystemExit(f"{dockerfile}:{line_number}: expected a literal tagged FROM image.")
        names.append(base[1])
    if len(names) != 2:
        raise SystemExit(f"{dockerfile}: expected two FROM instructions for build and runtime.")
    return names


def json_object(raw, image):
    try:
        value = json.loads(raw)
    except ValueError as error:
        raise SystemExit(f"Invalid registry metadata for {image}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"Invalid registry metadata for {image}: expected a JSON object.")
    return value


def raw_digest(manifest):
    # Buildx --raw writes the original manifest bytes, which the registry hashes as-is.
    return "sha256:" + hashlib.sha256(manifest).hexdigest()


def is_linux_amd64(platform):
    return (
        platform.get("os") == "linux"
        and platform.get("architecture") == "amd64"
        and platform.get("variant") in (None, "", "v1")
    )


def linux_amd64_digest(raw, image):
    manifest = json_object(raw, image)
    if "manifests" not in manifest:
        if isinstance(manifest.get("config"), dict):
            return raw_digest(raw)
        raise SystemExit(f"Invalid registry metadata for {image}: expected an image manifest or index.")

    entries = manifest["manifests"]
    if not isinstance(entries, list):
        raise SystemExit(f"Invalid registry metadata for {image}: expected an array of manifests.")
    matches = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise SystemExit(f"Invalid manifest descriptor for {image}.")
        platform = entry.get("platform") or {}
        if not isinstance(platform, dict):
            raise SystemExit(f"Invalid manifest platform for {image}.")
        if is_linux_amd64(platform):
            digest = entry.get("digest")
            if not isinstance(digest, str) or DIGEST.fullmatch(digest) is None:
                raise SystemExit(f"Invalid linux/amd64 digest for {image}.")
            matches.add(digest)
    if len(matches) > 1:
        raise SystemExit(f"Found multiple linux/amd64 digests for {image}.")
    return next(iter(matches), None)


def image_config(image, digest):
    # Inspect the selected immutable manifest so a concurrent tag update cannot change its labels.
    pinned = f"{image}@{digest}"
    return json_object(inspect(pinned, "--format", "{{json .Image}}"), pinned)


def reusable_digest(release_image, fingerprint):
    raw = inspect(release_image, "--raw", allow_missing=True)
    if raw is None:
        return ""
    platform_digest = linux_amd64_digest(raw, release_image)
    if platform_digest is None:
        return ""
    image = image_config(release_image, platform_digest)
    if not is_linux_amd64(image):
        return ""
    config = image.get("config") or {}
    labels = config.get("Labels") or {}
    if not isinstance(labels, dict):
        raise SystemExit(f"Invalid image labels for {release_image}.")
    if labels.get(BUILD_INPUTS_LABEL) == fingerprint:
        return raw_digest(raw)
    return ""


def main():
    image = os.environ["IMAGE"]
    release_tag = os.environ["RELEASE_TAG"]
    revision = os.environ["RELEASE_REVISION"]
    if not re.fullmatch(REPOSITORY, image) or not re.fullmatch(TAG, release_tag):
        raise SystemExit("Expected an image repository without a tag and a separate valid image tag.")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise SystemExit("Expected the full Git release revision.")

    dockerfile = Path(os.environ.get("RELEASE_DOCKERFILE", "release-source/Dockerfile"))
    build, runtime = base_images(dockerfile)
    bases = {}
    for name in dict.fromkeys((build, runtime)):
        raw = inspect(name, "--raw")
        digest = linux_amd64_digest(raw, name)
        if digest is None or (digest == raw_digest(raw) and not is_linux_amd64(image_config(name, digest))):
            raise SystemExit(f"No linux/amd64 image found for {name}.")
        bases[name] = digest

    inputs = json.dumps([revision, [(name, bases[name]) for name in (build, runtime)]])
    fingerprint = hashlib.sha256(inputs.encode("utf-8")).hexdigest()
    release_image = f"{image}:{release_tag}"
    existing_digest = reusable_digest(release_image, fingerprint)

    with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as output:
        print(f"build_required={'false' if existing_digest else 'true'}", file=output)
        print(f"existing_digest={existing_digest}", file=output)
        print(f"build_base_image={build}@{bases[build]}", file=output)
        print(f"runtime_base_image={runtime}@{bases[runtime]}", file=output)
        print(f"base_name={runtime}", file=output)
        print(f"base_digest={bases[runtime]}", file=output)
        print(f"fingerprint={fingerprint}", file=output)
        print("contexts<<BASE_IMAGES", file=output)
        for name, digest in bases.items():
            print(f"{name}=docker-image://{name}@{digest}", file=output)
        print("BASE_IMAGES", file=output)

    if existing_digest:
        print(f"Reusing {release_image} with unchanged build inputs.")
    else:
        print(f"Building {release_image} because the tag or matching build inputs are missing.")


if __name__ == "__main__":
    main()
