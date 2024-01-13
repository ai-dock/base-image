if [[ ! -f ~/.gitconfig ]]; then
    git config --global --add safe.directory "*"
fi

if [[ -f ~/.bashrc ]]; then
    source ~/.bashrc
fi

