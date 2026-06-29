# LatticeVE Firecracker Image Builder

Template framework for building Firecracker rootfs images for LatticeVE.

This starter builds an Alpine nginx rootfs that boots under Firecracker, gets
DHCP on `eth0`, starts nginx, and serves a default page on port 80.

Docker is used only as the build frontend to assemble a Linux root filesystem.
The output is a raw ext4 rootfs for LatticeVE, not an OCI image.

## Build locally on Linux

Requirements:

- Docker
- `e2fsprogs` for `mke2fs`
- `sha256sum`
- QEMU/binfmt support if building `ARCH=arm64` on an amd64 host

```bash
ARCH=amd64 ALPINE_VERSION=3.21 ./build.sh
```

Artifacts are written to:

```text
dist/alpine-nginx-3.21-amd64.ext4
dist/alpine-nginx-3.21-amd64.ext4.sha256
dist/alpine-nginx-3.21-amd64.ext4.json
```

Upload the `.ext4` file in LatticeVE:

```text
Images → Firecracker → RootFS → Upload RootFS
```

## GitHub Actions

Use the `Build RootFS` workflow manually from the Actions tab. It uploads the
`.ext4`, `.sha256`, and `.json` files as build artifacts.

## Design notes

- No SSH is included. Firecracker rootfs images should be treated more like
  VM-shaped application containers: bake the workload into the image and
  observe it through serial logs, app endpoints, and LatticeVE lifecycle
  operations.
- OpenRC `hwdrivers` and `modules` services are disabled because LatticeVE
  supplies the Firecracker kernel separately and this rootfs does not ship
  `/lib/modules`.
- The ext4 artifact is sized to the exported rootfs plus `EXTRA_MB`, default
  `8`. At boot, `/etc/local.d/latticeve-resize.start` grows the filesystem to
  the disk size assigned by LatticeVE.
- The expected Firecracker kernel command line is the LatticeVE default:
  `console=ttyS0 reboot=k panic=1 pci=off nomodules root=/dev/vda rw`.
