# php

## Code-server artifact pinning

`base/Dockerfile` files define `CODESERVER_PINNED_HASH_VERSION` (currently `4.99.4`) and use it as the default `CODESERVER_VERSION`.
Checksum verification is applied when `CODESERVER_VERSION` matches `CODESERVER_PINNED_HASH_VERSION`.

For the pinned hash version, keep both hashes in sync:

- `CODESERVER_DEB_SHA256_AMD64`
- `CODESERVER_DEB_SHA256_ARM64`

If you choose to pin another version the same way, compute new hashes with:

```bash
VERSION=4.99.4
for arch in amd64 arm64; do
	TMPDIR=$(mktemp -d)
	curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 \
		"https://github.com/coder/code-server/releases/download/v${VERSION}/code-server_${VERSION}_${arch}.deb" \
		-o "${TMPDIR}/code-server_${VERSION}_${arch}.deb"
	shasum -a 256 "${TMPDIR}/code-server_${VERSION}_${arch}.deb"
	rm -rf "${TMPDIR}"
done
```

Then update each `*/base/Dockerfile` so the version condition and both SHA256 values stay in sync.

Example pattern used in `base/Dockerfile` files:

```dockerfile
CODESERVER_VERSION="${CODESERVER_VERSION-$CODESERVER_PINNED_HASH_VERSION}"; \
if [ "$CODESERVER_VERSION" = "$CODESERVER_PINNED_HASH_VERSION" ]; then \
	case "$DEB_ARCH" in \
		amd64) DEB_SHA256="$CODESERVER_DEB_SHA256_AMD64" ;; \
		arm64) DEB_SHA256="$CODESERVER_DEB_SHA256_ARM64" ;; \
	esac; \
	echo "$DEB_SHA256  /tmp/code-server.deb" | sha256sum -c -; \
fi; \
dpkg -i /tmp/code-server.deb
```

## Docker Hub namespace for secure/advance images

`secure/Dockerfile` and `advance/Dockerfile` files now support a `DOCKERHUB_USERNAME` build argument for upstream image references.

- Default (if omitted): `devpanel`
- Override example:

```bash
docker build \
	--build-arg DOCKERHUB_USERNAME=mydockerhubuser \
	-f 8.3/secure/Dockerfile \
	8.3/secure
```

```bash
docker build \
	--build-arg DOCKERHUB_USERNAME=mydockerhubuser \
	-f 8.3/advance/Dockerfile \
	8.3/advance
```