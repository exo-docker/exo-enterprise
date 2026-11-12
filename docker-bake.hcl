# Local buildx bake definition (nothing is pushed unless you ask for it).
#
#   docker buildx bake                 # build for the host arch, load into docker
#   docker buildx bake multiarch       # amd64 + arm64, kept in the build cache only
#   docker buildx bake --print         # show the resolved configuration
#   EXO_VERSION=7.3.0-M18 docker buildx bake
#   docker buildx bake multiarch --push   # explicit opt-in to publish

variable "EXO_VERSION" { default = null } # unset: the Dockerfile default applies
variable "IMAGE"       { default = "exoplatform/exo-enterprise" }
variable "VCS_REF"     { default = "" }
variable "BUILD_DATE"  { default = "" }

group "default" { targets = ["image"] }

target "image" {
  context    = "."
  dockerfile = "Dockerfile"
  tags       = ["${IMAGE}:local"]
  args = {
    EXO_VERSION = EXO_VERSION
    VCS_REF     = VCS_REF
    BUILD_DATE  = BUILD_DATE
  }
  output = ["type=docker"]
}

target "multiarch" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
  output    = ["type=cacheonly"]
  # SBOM and SLSA provenance attestations (only attached when pushing)
  attest = ["type=sbom", "type=provenance,mode=max"]
}
