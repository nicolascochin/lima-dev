#!/bin/bash

TEMPLATE=docker
GUEST_HOME=/home/$1
ME=$(whoami)
CUSTOMIZATION=$2

#TEMPLATE_DEBIAN=https://raw.githubusercontent.com/lima-vm/lima/refs/heads/master/templates/debian-12.yaml
TEMPLATE_DOCKER=https://raw.githubusercontent.com/lima-vm/lima/refs/heads/master/templates/docker.yaml

PACKAGES=(
  command-not-found
  direnv
  zsh
  bat
  fzf
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
if [ -z "$1" ]; then
    echo "Usage: $0 name_of_the_vm"
    exit 1
fi

# Check is the name contains a space
if [[ "$1" =~ \  ]]; then
    echo "Error: The name should not contain a space"
    exit 1
fi

# Check if limactl is installed
if ! command -v limactl &> /dev/null; then
    echo "Error : limactl is not installed. Run brew install lima"
    exit 1
fi

# Temporary directory to store the templates
TEMP_DIR=$(mktemp -d)

TEMPLATE_FILE=$TEMP_DIR/template.yaml
curl -so $TEMPLATE_FILE $TEMPLATE_DOCKER

# The Following comment are here to merge the debian template with the docker's template
# Since debian is a but late on the package's version (neovim). I'll stick to ubuntu for now
#
## Fetch the templates into the temporary directory
#curl -so "$TEMP_DIR/debian-12.yaml" $TEMPLATE_DEBIAN
#curl -so "$TEMP_DIR/docker.yaml" $TEMPLATE_DOCKER
#
## Remove 'images' and 'mounts' keys from docker.yaml
#yq eval 'del(.images, .mounts)' "$TEMP_DIR/docker.yaml" -o yaml > "$TEMP_DIR/docker_without_images_and_mounts.yaml"
#
## Merge everything from docker.yaml (except 'images' and 'mounts') into debian-12.yaml
#yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$TEMP_DIR/debian-12.yaml" "$TEMP_DIR/docker_without_images_and_mounts.yaml" -o yaml > "$TEMPLATE_FILE"

# Add custom
yq eval -i ".user = {\"name\": \"$ME\", \"home\": \"$GUEST_HOME\"}" "$TEMPLATE_FILE"
yq eval -i ".mounts += [{\"location\": \"~/.ssh\", \"mountPoint\": \"${GUEST_HOME}/.ssh_host\"}]" "$TEMPLATE_FILE"
yq eval -i ".mounts += [{\"location\": \"~/Workspaces\", \"writable\": true, \"mountPoint\": \"${GUEST_HOME}/Workspaces\"}]" "$TEMPLATE_FILE"

# Add a provision step to install packages
yq eval -i ".provision += [{\"mode\": \"system\", \"script\": \"apt update && apt install -y $PACKAGES_STRING\"}]" "$TEMPLATE_FILE"
yq eval -i ".provision += [{\"mode\": \"system\", \"script\": \"ln -s /usr/bin/batcat /usr/bin/bat\"}]" "$TEMPLATE_FILE"

# setup hostname
yq eval -i ".provision += [{\"mode\": \"system\", \"script\": \"hostnamectl set-hostname $1\"}]" "$TEMPLATE_FILE"

# Finish installation
script=$(cat <<'EOF'
#!/bin/bash
set -eux -o pipefail
echo "Setup ssh"
ln -s ~/.ssh_host/config ~/.ssh/config
ln -s ~/.ssh_host/id* ~/.ssh/
echo "Change the shell"
sudo chsh -s $(which zsh) $(whoami)
echo "Install OMZ"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
echo "Install OMZ plugins & theme"
git clone https://github.com/mattmc3/zshrc.d $HOME/.oh-my-zsh/custom/plugins/zshrc.d
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $HOME/.oh-my-zsh/custom/themes/powerlevel10k
echo "Fetch config"
git clone -c core.sshCommand="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" git@github.com:nicolascochin/shell_config.git ~/.config/shell_config
~/.config/shell_config/install.sh
EOF
)
yq eval -i ".provision += [{\"mode\": \"user\", \"script\": \"$(echo "$script" | sed 's/"/\\"/g' | awk '{print $0 "\\n"}' | tr -d '\n')\"}]" "$TEMPLATE_FILE"

# Apply optional customization
if [ "$CUSTOMIZATION" == "ruby" ]; then
  RUBY_PACKAGES=(
    libz-dev # rbenv
    libpq-dev # ruby
    libffi-dev # ruby 3
    libyaml-dev # ruby 3
  )

  RUBY_PACKAGES_STRING=$(printf "%s " "${RUBY_PACKAGES[@]}")

  echo "Install Ruby packages"
  yq eval -i ".provision += [{\"mode\": \"system\", \"script\": \"apt update && apt install -y $RUBY_PACKAGES_STRING\"}]" "$TEMPLATE_FILE"

script=$(cat <<'EOF'
#!/bin/bash
set -eux -o pipefail
echo "Install rbenv"
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/main/bin/rbenv-installer | bash
echo "OMZ_PLUGINS+=(rbenv)" >> ~/.omz_plugins.zsh
echo "Add OMZ plugins"
echo "OMZ_PLUGINS+=(bundler)" >> ~/.omz_plugins.zsh
echo "OMZ_PLUGINS+=(ruby)" >> ~/.omz_plugins.zsh
echo "OMZ_PLUGINS+=(rails)" >> ~/.omz_plugins.zsh
EOF
)
  yq eval -i ".provision += [{\"mode\": \"user\", \"script\": \"$(echo "$script" | sed 's/"/\\"/g' | awk '{print $0 "\\n"}' | tr -d '\n')\"}]" "$TEMPLATE_FILE"
fi


#cat $TEMPLATE_FILE
#exit

echo "File used to setup the VM is here: $TEMPLATE_FILE"
# Install the VM
limactl create --tty=false --name="$1" $TEMPLATE_FILE


#echo "Add ssh config"
#limactl show-ssh --format=config $1 >> ~/.ssh/config
