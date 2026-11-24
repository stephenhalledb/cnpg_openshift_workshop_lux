source ./config.sh
source ./replica.sh


#Doc
echo "30" > ./docs/docid

# Without a parameter, ask in the terminal: a) fence or b) unfence
#   ./32_fencing.sh        : asks
#   ./32_fencing.sh on|off : does not ask (on = fence, off = unfence)
i=$1
while [ -z "$i" ]; do
  printf "Instance ${replica} of cluster ${cluster_name}:\n"
  printf "  a) fence\n"
  printf "  b) unfence\n"
  printf "Choose a or b [q to quit]: "
  read -r answer || exit 1
  case "${answer}" in
    a|A|on|ON)    i="on" ;;
    b|B|off|OFF)  i="off" ;;
    q|Q)          echo "Nothing changed."; exit 0 ;;
    *)            print_warning "Please answer a, b or q.\n" ;;
  esac
done

case $i in
  "on")
    print_command "${kubectl_cnp} fencing on ${cluster_name} ${replica}\n"
    ${kubectl_cnp} fencing on ${cluster_name} ${replica}
    ;;
  "off")
    print_command "${kubectl_cnp} fencing off ${cluster_name} ${replica}\n"
    ${kubectl_cnp} fencing off ${cluster_name} ${replica}
    ;;
  *)
    echo "usage: $0 [on|off]"
    exit 1
esac
