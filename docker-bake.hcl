variable "DOCKER_REGISTRY" {
  default = "ghcr.io"
}
variable "DOCKER_ORG" {
  default = "darpa-askem"
}
variable "VERSION" {
  default = "local"
}

# ----------------------------------------------------------------------------------------------------------------------

function "tag" {
  params = [image_name, prefix, suffix]
  result = [ "${DOCKER_REGISTRY}/${DOCKER_ORG}/${image_name}:${check_prefix(prefix)}${VERSION}${check_suffix(suffix)}" ]
}

function "check_prefix" {
  params = [tag]
  result = notequal("",tag) ? "${tag}-": ""
}

function "check_suffix" {
  params = [tag]
  result = notequal("",tag) ? "-${tag}": ""
}

# ----------------------------------------------------------------------------------------------------------------------

group "prod" {
  targets = ["model-service"]
}

group "default" {
  targets = ["model-service-base"]
}

# ----------------------------------------------------------------------------------------------------------------------

# Used by the metafile GH action
# DO NOT ADD ANYTHING HERE THIS WILL BE POPULATED DYNAMICALLY
# MAKE SURE THIS IS INHERITED NEAR THE END SO THAT IT DOES NOT GET OVERRIDEN
target "docker-metadata-action" {}

target "_platforms" {
  platforms = ["linux/amd64", "linux/arm64"]
}

target "model-service-base" {
	context = "."
	tags = tag("model-service", "", "")
	dockerfile = "Dockerfile"
}

# NOTE: target name will be used as the name of the image
target "model-service" {
  inherits = ["model-service-base", "docker-metadata-action", "_platforms"]
}
