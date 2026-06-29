#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

alpine_version="${ALPINE_VERSION:-3.21}"
arch="${ARCH:-amd64}"
extra_mb="${EXTRA_MB:-8}"
out_dir="${OUT_DIR:-${repo_root}/dist}"
profile="nginx"
name="alpine-${profile}-${alpine_version}-${arch}"

case "${arch}" in
  amd64) platform="linux/amd64"; target_arch="amd64" ;;
  arm64) platform="linux/arm64"; target_arch="arm64" ;;
  *) echo "unsupported ARCH=${arch}; expected amd64 or arm64" >&2; exit 1 ;;
esac

# Building an ext4 rootfs should run as root so extracted files keep their
# numeric Linux ownership and mke2fs can faithfully populate the image. This is
# especially important in GitHub Actions, where the default runner user would
# otherwise turn root-owned Alpine files into uid 1001-owned files.
if [[ "${EUID}" -ne 0 ]]; then
  command -v sudo >/dev/null || { echo "sudo is required when not running as root" >&2; exit 1; }
  exec sudo --preserve-env=ARCH,ALPINE_VERSION,EXTRA_MB,OUT_DIR "$0" "$@"
fi

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }
command -v mke2fs >/dev/null || { echo "mke2fs is required; install e2fsprogs" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "sha256sum is required" >&2; exit 1; }

work_dir="$(mktemp -d)"
container_id=""
cleanup() {
  if [[ -n "${container_id}" ]]; then docker rm -f "${container_id}" >/dev/null 2>&1 || true; fi
  rm -rf "${work_dir}"
}
trap cleanup EXIT

docker_image="latticeve/fc-rootfs-${profile}:${alpine_version}-${arch}"
rootfs_dir="${work_dir}/rootfs"
mkdir -p "${rootfs_dir}" "${out_dir}"

DOCKER_BUILDKIT=1 docker build \
  --platform "${platform}" \
  --build-arg "ALPINE_VERSION=${alpine_version}" \
  --build-arg "TARGETARCH=${target_arch}" \
  -t "${docker_image}" \
  "${repo_root}"

container_id="$(docker create "${docker_image}")"
docker export "${container_id}" | tar --numeric-owner --exclude='./dev/*' -C "${rootfs_dir}" -xf -
mkdir -p "${rootfs_dir}/dev" "${rootfs_dir}/proc" "${rootfs_dir}/sys" "${rootfs_dir}/run" "${rootfs_dir}/tmp"
chmod 1777 "${rootfs_dir}/tmp"

used_kib="$(du -sk "${rootfs_dir}" | awk '{print $1}')"
size_mib="$(( (used_kib + (extra_mb * 1024) + 1023) / 1024 ))"

rootfs_path="${out_dir}/${name}.ext4"
metadata_path="${rootfs_path}.json"
sha_path="${rootfs_path}.sha256"

rm -f "${rootfs_path}" "${metadata_path}" "${sha_path}"
truncate -s "${size_mib}M" "${rootfs_path}"
mke2fs -q -F -t ext4 -L latticeve-rootfs -d "${rootfs_dir}" "${rootfs_path}"

(
  cd "${out_dir}"
  sha256sum "$(basename "${rootfs_path}")" > "$(basename "${sha_path}")"
)

cat > "${metadata_path}" <<EOF
{
  "kind": "latticeve.firecracker.rootfs",
  "schema_version": "1",
  "name": "alpine-nginx",
  "distro": "alpine",
  "distro_version": "${alpine_version}",
  "arch": "${arch}",
  "profile": "${profile}",
  "format": "raw",
  "filesystem": "ext4",
  "size_mb": ${size_mib}
}
EOF

echo "Built ${rootfs_path}"
echo "SHA256 $(cut -d' ' -f1 "${sha_path}")"

if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
  chown "${SUDO_UID}:${SUDO_GID}" "${rootfs_path}" "${metadata_path}" "${sha_path}"
fi
