#!/bin/bash

# Shows a YAML file of the yaml/ folder with the variables of config.sh filled in.
# Usage: ./show_yaml.sh            (asks which YAML to show)
#        ./show_yaml.sh <name|nr>  (name with or without .yaml, or number in the list)

cd "$(dirname "$0")" || exit 1
yaml_dir="yaml"

# List the YAML files (bash 3.2 compatible, no mapfile)
files=()
for f in "${yaml_dir}"/*.yaml; do
  [ -f "$f" ] && files+=("$(basename "$f")")
done
if [ ${#files[@]} -eq 0 ]; then
  echo "No YAML files found in ${yaml_dir}/" >&2
  exit 1
fi

choice="$1"
if [ -z "${choice}" ]; then
  echo "YAML files in ${yaml_dir}/:" >&2
  i=1
  for f in "${files[@]}"; do
    printf "  %2d) %s\n" "$i" "$f" >&2
    i=$((i + 1))
  done
  printf "Which YAML do you want to see? (number or name): " >&2
  read -r choice
fi

# Resolve the choice to a file name
selected=""
if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le ${#files[@]} ]; then
  selected="${files[$((choice - 1))]}"
else
  name=$(basename "${choice}")
  for f in "${files[@]}"; do
    if [ "$f" = "${name}" ] || [ "$f" = "${name}.yaml" ]; then
      selected="$f"
      break
    fi
  done
fi

if [ -z "${selected}" ]; then
  echo "'${choice}' is not a valid choice." >&2
  exit 1
fi

. ./config.sh
. ./commands.sh

print_banner "\n=== ${yaml_dir}/${selected} ===\n\n"
envsubst < "${yaml_dir}/${selected}"
