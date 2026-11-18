#!/usr/bin/env bash
set -e

# Keep per-arch tags single-platform so docker manifest create accepts them.
export BUILDX_NO_DEFAULT_ATTESTATIONS=1

if [[ -z "${RELEASE}" ]]; then
  RELEASE="release"
fi

REPO="$(git remote get-url --push origin | sed -e 's#^https://github.com/##' | sed -e 's#^git@github.com:##')"
TAG="$(git describe --tags)"

declare -A manifests=()

for FILE in $(ls "${RELEASE}" | grep _linux_ | grep -v '.sha256' | xargs); do
  arch="${FILE##*_linux_}"
  name="${FILE%%_linux_*}"
  dockerfile="Dockerfile.${arch}"
  cat <<EOF >${dockerfile}
FROM --platform=linux/${arch} alpine
COPY ${RELEASE}/${FILE} /usr/local/bin/${name}
ENTRYPOINT ["/usr/local/bin/${name}"]
EOF

  image="ghcr.io/${REPO,,}/${name}:${TAG}"
  imagearch="${image}__linux_${arch}"
  docker build -t "${imagearch}" -f "${dockerfile}" . && docker push "${imagearch}"
  manifests["${image}"]+="${imagearch} "
done

for name in ${!manifests[@]}; do
  docker manifest create --amend "${name}" ${manifests["${name}"]}
  for imagearch in ${manifests["${name}"]}; do
    arch="${imagearch##*_}"
    docker manifest annotate "${name}" "${imagearch}" --arch "${arch}" --os linux
  done
  docker manifest push --purge "${name}"
done
