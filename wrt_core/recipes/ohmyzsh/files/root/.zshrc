export ZSH="/root/.oh-my-zsh"
zstyle ':omz:update' mode disabled
ZSH_THEME="robbyrussell"
plugins=(git zsh-autocomplete zsh-autosuggestions zsh-syntax-highlighting)

source /etc/profile
source "$ZSH/oh-my-zsh.sh"
