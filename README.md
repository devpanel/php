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
if [ "$CODESERVER_VERSION" = "$CODESERVER_PINNED_HASH_VERSION" ]; then \
	case "$DEB_ARCH" in \
		amd64) DEB_SHA256="$CODESERVER_DEB_SHA256_AMD64" ;; \
		arm64) DEB_SHA256="$CODESERVER_DEB_SHA256_ARM64" ;; \
	esac; \
	echo "$DEB_SHA256  /tmp/code-server.deb" | sha256sum -c -; \
fi; \
dpkg -i /tmp/code-server.deb
```

## GitHub Copilot Chat extension pinning

GitHub Copilot Chat is not available in the Open VSX marketplace used by
code-server, so `base/Dockerfile` downloads it directly from the Visual Studio
Marketplace at image-build time.

The pinned version (`COPILOT_CHAT_PINNED_VERSION`, currently `0.26.2025040204`)
was chosen because it requires VS Code `^1.99.0`, making it compatible with
code-server `4.99.4` (which bundles VS Code `1.99.4`).

When upgrading to a new code-server version, find a compatible Copilot Chat
release by checking the `engines.vscode` field in the extension's
[`package.json`](https://github.com/microsoft/vscode-copilot-chat) (available
for versions v0.29.0 and later; for earlier versions use the
[VsixHub version history](https://www.vsixhub.com/history/143611/)).
Pick the newest version whose `engines.vscode` minimum is &le; the VS Code version
bundled with the target code-server release.

To enable integrity checking, compute the SHA256 of the VSIX for the chosen
version and set `COPILOT_CHAT_VSIX_SHA256` in `base/Dockerfile`:

```bash
VERSION=0.26.2025040204
TMPDIR=$(mktemp -d)
curl -fsSL --retry 5 --retry-all-errors --connect-timeout 10 \
	"https://marketplace.visualstudio.com/_apis/public/gallery/publishers/GitHub/vsextensions/copilot-chat/${VERSION}/vspackage" \
	-o "${TMPDIR}/copilot-chat-${VERSION}.vsix"
shasum -a 256 "${TMPDIR}/copilot-chat-${VERSION}.vsix"
rm -rf "${TMPDIR}"
```

Then update `COPILOT_CHAT_PINNED_VERSION` and `COPILOT_CHAT_VSIX_SHA256` in
`base/Dockerfile`.

The VSIX is architecture-independent, so only one hash value is needed (unlike
code-server which ships separate `amd64`/`arm64` packages).
