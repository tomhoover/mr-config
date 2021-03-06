#!/bin/bash
#
# Bootstrap a new ~adam using mr.
#
# This essentially does the following steps:
#   - configures ssh
#   - configures git
#   - checks out and installs my hacked version of mr
#   - runs mr bootstrap on a remote copy of home-mrconfig
#   - uses mr to install GNU Stow
#   - uses mr to check out and fixup all repositories

set -e

git_host=git.adamspiers.org
git_local_hostname=coral
git_user=adam
git_user_at_host=$git_user@$git_host
# On a vanilla bootstrap, we may not have an ssh key with
# access to this URL:
#mr_upstream_repo="git@github.com:aspiers/kitenet-mr.git"
mr_upstream_repo="$git_local_hostname:.GIT/3rd-party/mr"

div () {
    echo
    echo "############################################################"
    echo
}

fatal () {
    echo "$*" >&2
    exit 1
}

which curl >/dev/null 2>&1 || fatal "mr can't bootstrap without curl"
[ -d ~/.stow ] && fatal "Rogue ~/.stow - delete it first."

cd

[ -e ~/.zdotuser           ] || ${EDITOR:-vi} ~/.zdotuser
[ -e ~/.localhost-nickname ] || ${EDITOR:-vi} ~/.localhost-nickname

echo "Setting ZDOTDIR to $HOME"
export ZDOTDIR=$HOME

if [ -z "$PERL5LIB" ]; then
    export PERL5LIB=$HOME/lib/perl5
else
    export PERL5LIB=$HOME/lib/perl5:$PERL5LIB
fi
echo "exported PERL5LIB=$PERL5LIB"

[ -d ~/.ssh ] || mkdir ~/.ssh
chmod 700 ~/.ssh

if ! [ -f "$HOME/.ssh/config" ]; then
    echo "~/.ssh/config does not exist."
    cat <<EOF > ~/.ssh/config
# bootstrap.sh-magic-cookie <- indicates can be automatically removed by bootstrap.sh
Host $git_host
   ControlMaster auto

Host *
   ControlPath ~/.ssh/master-%r@%h:%p
EOF
    chmod 600 ~/.ssh/config
    echo "Wrote ~/.ssh/config:"
    echo
    cat ~/.ssh/config
fi

ssh_socket=$HOME/.ssh/master-${git_user_at_host}:22
if [ -S $ssh_socket ]; then
    echo "$ssh_socket already exists"
else
    echo "Executing ssh -NMf $git_user_at_host"
    ssh -NMf $git_user_at_host
    echo
fi

echo -n "Checking passwordless ssh works ... "
cmd="ssh -n -o PasswordAuthentication=no $git_user_at_host hostname 2>&1"
out="`$cmd`"
if [ "$out" != "$git_local_hostname" ]; then
    echo
    fatal "$cmd returned [$out] not $git_local_hostname; aborting."
else
    echo "yep - good!"
fi

div ############################################################

echo "Configuring git ..."
which git >&/dev/null || fatal "git not found on \$PATH; aborting."
git config --global url.ssh://$git_host/home/$git_user/.insteadof $git_local_hostname:

div ############################################################

echo "Setting up ~/bin ..."
# Various .cfg-post.d rely on ~/bin being there.
if ! [ -d ~/bin ]; then
    mkdir ~/bin
fi
export PATH=$HOME/bin:$PATH

div ############################################################

third_party_git=$HOME/.GIT/3rd-party

mkdir -p $third_party_git
if [ -d $third_party_git/mr ]; then
    echo "Updating existing mr git repo ..."
    ( cd $third_party_git/mr && git pull -r )
else
    echo "Retrieving upstream git repo for mr: $mr_upstream_repo ..."
    git clone $mr_upstream_repo $third_party_git/mr
    ( cd $third_party_git/mr && git checkout master )
fi
ln -sf $third_party_git/mr/mr ~/bin
echo '~/.config/mr/.mrconfig' > ~/.mrtrust

div ############################################################

echo "Setting up mr config ..."

if [ -e .mrconfig ]; then
    mr -r mr-config up
else
    mr -t -i bootstrap http://adamspiers.org/.mrconfig
fi

div ############################################################

up=$HOME/bin/up
# We need 'up' installed first, so that the download
# plugin can unpack stow.
if [ -x $up ]; then
    echo "'up' utility already exists ..."
else
    echo "Downloading 'up' utility ..."
    curl -o $up https://raw.github.com/aspiers/shell-env/master/bin/up
    chmod +x $up
fi

div ############################################################

# We need stow installed first, so that the other
# repos can stow themselves.
echo "Installing stow-release ..."
mr -r stow-release checkout

if ! which stow >&/dev/null; then
    echo "stow installation failed; aborting." >&2
    exit 1
fi

if [ -d ~/.cfg ]; then
    touch ~/.cfg/.stow
    export MR_STOW_OVER=.
fi

if [ -e $up -a ! -L $up ]; then
    echo "Removing temporary $up"
    rm $up
fi

div ############################################################

# cfgctl used to be needed early on for lib/libhooks.sh, but that got
# moved to shell-env.  It's possibly needed for other things too,
# but let's try to manage without.
#mr -r cfgctl up

echo "Checking for files which distros are likely to provide ..."

for skelfile in \
    .profile .bashrc .bash_profile .inputrc .zshrc .emacs \
    .gnupg/{{pub,sec}ring,trustdb}.gpg
do
    if [ -e "$skelfile" -a ! -L "$skelfile" ]; then
        cat <<EOF >&2
Warning: $skelfile exists but is not a symlink.
This will cause conflicts when stowing shell-env.
Please correct now - launching a subshell ...

EOF
        $SHELL || fatal "Subshell failed; aborting."
    fi
done

echo

div ############################################################

# shell-env is needed by mr-util for zrec

echo "Retrieving shell-env ..."
mr -i -r shell-env up
echo

div ############################################################

boot=( ssh ssh.adam_spiers.sec mr-util git-config )
pkgs="${boot[@]}"
pkgs="${pkgs// /,}"
echo "Retrieving ${pkgs//,/, } ..."
mr -i -r $pkgs up
echo

div ############################################################

if ! grep -q 'bootstrap.sh-magic-cookie' ~/.ssh/config; then
    echo "bootstrap.sh magic cookie missing from ~/.ssh/config"
    if ! head -n1 ~/.ssh/config | grep -q 'Autogenerated'; then
        fatal "~/.ssh/config wasn't autogenerated; aborting."
    fi
fi

echo "Allowing mr to rebuild ssh config from scratch ..."
echo "rm ~/.ssh/config"
rm ~/.ssh/config
echo
echo "Running mr -r ssh fixups to build config ..."
mr -i -r ssh fixups

div ############################################################

echo "Running mr checkout ..."
mr -s -i up

cat <<EOF

Now fix the above errors and also run:

  ( cd && mr remotes )
EOF
