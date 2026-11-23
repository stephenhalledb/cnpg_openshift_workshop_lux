
#!/bin/bash

# Colors
reset="\e[0m" #reset color
red="\e[31m"
green="\e[32m"
yellow="\e[33m"
blue="\e[34m"
bold="\e[1m"
underline="\e[4m"

# to_rfc1123 <name>
# Normalizes a name into a valid RFC 1123 label, as Kubernetes requires for
# namespaces, cluster names, etc. (regex: [a-z0-9]([-a-z0-9]*[a-z0-9])?, max 63 chars):
#   - converts to lowercase
#   - replaces every character that is not a-z, 0-9 or "-" (space, "_", ".", "@"...) by "-"
#   - collapses repeated "-" and removes leading/trailing "-"
#   - truncates to 63 characters
# Prints the result. Returns 1 (and prints nothing) if nothing valid is left.
# POSIX sh compatible (works with the bash 3.2 of macOS).
# Example: id=$(to_rfc1123 "Stephen_Hall") -> stephen-hall
to_rfc1123() {
  local name
  name=$(printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' \
    | cut -c1-63 \
    | sed -e 's/-$//')
  [ -n "${name}" ] || return 1
  printf '%s\n' "${name}"
}

# --- Names: validation functions ---------------------------------------------
# A name used by Kubernetes (namespace, cluster name...) or in the settings
# (S3 bucket name) must be a valid RFC 1123 label: lowercase a-z, 0-9 and "-",
# start and end with a letter or digit, 63 characters at most.
# The functions below check a name, repair it if needed
# and warn the user. Each one has a single responsibility:
#   is_rfc1123_label     : checks a value (no output)
#   warn_name_changed    : prints the warning (no logic)
#   fix_name_variable    : checks a variable, repairs it in memory, warns
#   fix_name_variables   : applies fix_name_variable to several variables
# The repair itself is done by to_rfc1123 (above).
# Names that are changed are only changed in memory: config.sh is NOT edited.

K8S_LABEL_MAX_LENGTH=63

# is_rfc1123_label <value>
# Returns 0 if <value> is a valid RFC 1123 label, 1 otherwise.
# (LC_ALL=C: the a-z range must mean ASCII letters only, whatever the locale)
is_rfc1123_label() {
  local value="$1"
  [ "${#value}" -le "${K8S_LABEL_MAX_LENGTH}" ] || return 1
  case "${value}" in
    ''|-*|*-) return 1 ;;   # empty, or starts/ends with "-"
  esac
  [ -z "$(printf '%s' "${value}" | LC_ALL=C tr -d 'a-z0-9-')" ]   # only a-z 0-9 -
}

# warn_name_changed <variable> <old value> <new value> [description]
# <description> says what kind of name it is (default: Kubernetes name).
# Warns once per run (the marker is exported, so the scripts started by a
# script do not repeat it, although each one loads config.sh again).
warn_name_changed() {
  local variable="$1" old="${2//%/%%}" new="${3//%/%%}" description="${4:-Kubernetes name}"
  case ":${K8S_NAMES_WARNED}:" in
    *":${variable}:"*) return 0 ;;
  esac
  export K8S_NAMES_WARNED="${K8S_NAMES_WARNED}:${variable}"

  print_warning "WARNING: '${variable}' = '${old}' is not a valid ${description}.\n"
  print_warning "         '${new}' is used instead, this change is only in memory.\n"
  print_warning "         Change '${variable}' in config.sh to remove this warning.\n"
}

# fix_name_variable <variable name> [description]
# Valid value: nothing happens. Invalid value: it is repaired in memory and the
# user is warned. Returns 1 if the value cannot be repaired (nothing valid left).
fix_name_variable() {
  local variable="$1" description="${2:-Kubernetes name}" original fixed
  original="${!variable}"

  is_rfc1123_label "${original}" && return 0

  fixed=$(to_rfc1123 "${original}")
  if [ -z "${fixed}" ]; then
    print_error "ERROR: '${variable}' = '${original}' is not a valid ${description} and cannot be repaired.\n"
    print_error "       Set a valid '${variable}' in config.sh (lowercase letters, digits and '-').\n"
    return 1
  fi

  export "${variable}=${fixed}"
  warn_name_changed "${variable}" "${original}" "${fixed}" "${description}"
}

# fix_name_variables <variable name>...
# Returns 1 if at least one variable could not be repaired.
fix_name_variables() {
  local variable status=0
  for variable in "$@"; do
    fix_name_variable "${variable}" || status=1
  done
  return ${status}
}

print_command() {
    
    local message="$1"
    printf "\e[32m$message\e[0m"
}

print_warning() {
    local message="$1"
    printf "\e[33m$message\e[0m"
}

print_error() {
    local message="$1"
    printf "\e[31m$message\e[0m"
}

print_banner() {
    local message="$1"
    printf "\e[32m$message\e[0m"
}

print_info() {
    local message="$1"
    printf "\e[34m$message\e[0m"
}

center_text() {
    local text="$1"          # The text to center
    local width="$2"         # The desired width
    local text_length=${#text} # Length of the text
    local padding=$(( (width - text_length) / 2 )) # Calculate padding

    # Handle odd padding to ensure text is visually centered
    local extra_padding=$(( (width - text_length) % 2 ))
    printf "%*s%s%*s\n" $((padding + extra_padding)) "" "$text" $padding ""
}

repeat_text() {
    local text="$1"    # Text to repeat
    local count="$2"   # Number of repetitions

    # Validate that count is a number
    if ! [[ "$count" =~ ^[0-9]+$ ]]; then
        echo "Error: Count must be a non-negative integer."
        return 1
    fi

    # Loop to print the text n times
    for ((i = 0; i < count; i++)); do
        printf "$text"
    done
    echo  # Add a newline after the repeated text
}

function count_cpu_pods() {
  # Sum of CPUs Pods using CloudNativePG
  kubectl get pods -l 'role in (primary,replica)' -A -o=jsonpath='{range .items[*]}{.spec.containers[*].resources.limits.cpu}{"\n"}{end}' | \
  awk '{
    if ($1 ~ "m") {
      total += $1 / 1000
    } else {
      total += $1
    }
  } END {
    if (total == "") total = 0
    print total
  }'
}

function count_cpu_nodes() { 
  # Sum of CPUs Nodes in K8s
  kubectl get nodes -l node-role.kubernetes.io/worker= -o jsonpath='{range .items[*]}{.status.capacity.cpu}{"\n"}{end}' | \
  awk '{
    if ($1 ~ "m") {
      total += $1 / 1000
    } else {
      total += $1
    }
  } END {
    print total
  }'
}

function total_nodes() {
  kubectl get nodes --no-headers| wc -l | xargs
}