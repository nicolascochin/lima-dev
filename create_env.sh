#!/bin/bash

NAME=$1
GUEST_HOME=/home/$NAME
ME=$(whoami)
LIMA_TEMPLATE=${LIMA_TEMPLATE:-docker}
TEMPLATE_DOCKER=https://raw.githubusercontent.com/lima-vm/lima/refs/heads/master/templates/${LIMA_TEMPLATE}.yaml
COMPONENTS=()
PORTS=()

PACKAGES=(
  command-not-found
  direnv
  zsh
  bat
#  fzf
  jq
  git
  curl
  neovim
  tmux
  tmate
  figlet
  ripgrep # lazyvim dep
  fd-find # lazyvim dep
# DEV
  build-essential
)

# Convert package list to a space-separated string
PACKAGES_STRING=$(printf "%s " "${PACKAGES[@]}")

# Check if the parameter is present
if [ -z "$NAME" ]; then
    echo "Usage: $0 name_of_the_vm"
    exit 1
fi

# Check is the name contains a space
if [[ "$NAME" =~ \  ]]; then
    echo "Error: The name should not contain a space"
    exit 1
fi

# Check if limactl is installed
if ! command -v limactl &> /dev/null; then
    echo "Error : limactl is not installed. Run brew install lima"
    exit 1
fi

# Parcourir les arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c)
      if [[ -n "$2" && "$2" != -* ]]; then
        COMPONENTS+=("$2")
        shift 2
      else
        echo "Erreur : l'option -c nécessite un argument." >&2
        exit 1
      fi
      ;;
    -p)
      if [[ -n "$2" && "$2" != -* ]]; then
        PORTS+=("$2")
        shift 2
      else
        echo "Erreur : l'option -p nécessite un argument." >&2
        exit 1
      fi
      ;;
    *)
      shift
      ;;
  esac
done


while [[ -z "${GITHUB_USER}" ]]; do
  read -p "Entrez votre nom d'utilisateur GitHub : " GITHUB_USER
done
while [[ -z "${GITHUB_EMAIL}" ]]; do
  read -p "Entrez votre email GitHub : " GITHUB_EMAIL
done

# Temporary directory to store the intermediate templates
TEMP_DIR=$(mktemp -d)
TEMPLATE_FILE=$TEMP_DIR/template.yaml

curl -so $TEMPLATE_FILE $TEMPLATE_DOCKER

# Add custom
yq eval -i ".user = {\"name\": \"$ME\", \"home\": \"$GUEST_HOME\"}" "$TEMPLATE_FILE"
yq eval -i ".mounts += [{\"location\": \"~/.ssh\", \"mountPoint\": \"${GUEST_HOME}/.ssh_host\"}]" "$TEMPLATE_FILE"
yq eval -i ".mounts += [{\"location\": \"~/Workspaces\", \"writable\": true, \"mountPoint\": \"${GUEST_HOME}/Workspaces\"}]" "$TEMPLATE_FILE"

# Add a provision step to install packages
yq eval -i ".provision += [{\"mode\": \"system\", \"script\": \"apt update && apt install -y $PACKAGES_STRING\"}]" "$TEMPLATE_FILE"
yq eval -i ".provision += [{\"mode\": \"system\", \"script\": \"ln -s /usr/bin/batcat /usr/bin/bat\"}]" "$TEMPLATE_FILE"
for port in "${PORTS[@]}"; do
  host_port=$(echo "$port" | cut -d':' -f1)
  guest_port=$(echo "$port" | cut -d':' -f2)
  yq eval -i ".portForwards += [{\"guestPort\": $guest_port, \"hostPort\": $host_port}]" "$TEMPLATE_FILE"
done

# setup hostname
yq eval -i ".provision += [{\"mode\": \"system\", \"script\": \"hostnamectl set-hostname $NAME\"}]" "$TEMPLATE_FILE"

# Finish installation
script=$(cat <<EOF
#!/bin/bash
set -eux -o pipefail
# Setup SSH
ln -s ~/.ssh_host/config ~/.ssh/config
ln -s ~/.ssh_host/id* ~/.ssh/
# Change the shell
sudo chsh -s $(which zsh) $(whoami)
# Fetch config
git clone -c core.sshCommand="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" git@github.com:nicolascochin/shell_config.git ~/.config/shell_config
GITHUB_EMAIL="$GITHUB_EMAIL" GITHUB_USER="$GITHUB_USER" ~/.config/shell_config/install.sh
EOF
)
yq eval -i ".provision += [{\"mode\": \"user\", \"script\": \"$(echo "$script" | sed 's/"/\\"/g' | awk '{print $0 "\\n"}' | tr -d '\n')\"}]" "$TEMPLATE_FILE"

# Apply optional customization
for component in "${COMPONENTS[@]}"; do
  if [ "$component" == "ruby" ]; then
    RUBY_PACKAGES=(
      libz-dev # rbenv
      libpq-dev # ruby
      libffi-dev # ruby 3
      libyaml-dev # ruby 3
    )

    RUBY_PACKAGES_STRING=$(printf "%s " "${RUBY_PACKAGES[@]}")

    echo "Install Ruby packages"
    yq eval -i ".provision += [{\"mode\": \"system\", \"script\": \"apt update && apt install -y $RUBY_PACKAGES_STRING\"}]" "$TEMPLATE_FILE"

    script=$(cat <<-EOF
    #!/bin/bash
    set -eux -o pipefail
    # Install rbenv
    curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-installer | bash
    echo "OMZ_PLUGINS+=(rbenv)" >> ~/.omz_plugins.zsh
    # Add OMZ plugins
    echo "OMZ_PLUGINS+=(bundler)" >> ~/.omz_plugins.zsh
    echo "OMZ_PLUGINS+=(ruby)" >> ~/.omz_plugins.zsh
    echo "OMZ_PLUGINS+=(rails)" >> ~/.omz_plugins.zsh
    EOF
    )
    yq eval -i ".provision += [{\"mode\": \"user\", \"script\": \"$(echo "$script" | sed 's/"/\\"/g' | awk '{print $0 "\\n"}' | tr -d '\n')\"}]" "$TEMPLATE_FILE"
  fi

  if [ "$component" == "js" ]; then  
    script=$(cat <<-EOF
    #!/bin/bash
    set -eux -o pipefail
    # Install nodenv
    curl -fsSL https://github.com/nodenv/nodenv-installer/raw/HEAD/bin/nodenv-installer | bash
    echo "OMZ_PLUGINS+=(nodenv)" >> ~/.omz_plugins.zsh
    EOF
    )
    yq eval -i ".provision += [{\"mode\": \"user\", \"script\": \"$(echo "$script" | sed 's/"/\\"/g' | awk '{print $0 "\\n"}' | tr -d '\n')\"}]" "$TEMPLATE_FILE"
  fi
done

cat $TEMPLATE_FILE
exit

echo "File used to setup the VM is here: $TEMPLATE_FILE"
# Install the VM
limactl create --tty=false --name="$NAME" $TEMPLATE_FILE
