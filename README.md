# lima-dev
Templates used with lima to create dev environments

## Usage
### Create an env
#### Basic
```shell
bash <(curl -Ls https://raw.githubusercontent.com/nicolascochin/lima-dev/refs/heads/main/create_env.sh) NAME_OF_VM OPTIONNAL_PARAM
```
#### Ruby
```shell
bash <(curl -Ls https://raw.githubusercontent.com/nicolascochin/lima-dev/refs/heads/main/create_env.sh) NAME_OF_VM ruby
```
#### Ruby and JS
```shell
bash <(curl -Ls https://raw.githubusercontent.com/nicolascochin/lima-dev/refs/heads/main/create_env.sh) NAME_OF_VM ruby,js
```
#### With a custom image
```shell
LIMA_TEMPLATE=docker-rootful bash <(curl -Ls https://raw.githubusercontent.com/nicolascochin/lima-dev/refs/heads/main/create_env.sh) NAME_OF_VM ruby,js
```



### Enter into the vm (and start it if needed)
```shell
bash <(curl -Ls https://raw.githubusercontent.com/nicolascochin/lima-dev/refs/heads/main/enter_env.sh) NAME_OF_VM 
```
