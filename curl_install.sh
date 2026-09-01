#!/bin/bash
set -o errexit

if [[ "$SHELL" == *"bash"* ]]; then
    SHELL_PROFILE=~/.bashrc
    SHELL_DOT_DIR=~/.bash.d/
elif [[ "$SHELL" == *"zsh"* ]]; then
    SHELL_PROFILE=~/.zshrc
    SHELL_DOT_DIR=~/.zsh.d/
else
    SHELL_UNSUPPORTED=true
fi

if [ "$1" = "cleanup" ]; then 
    if [ -z ${SHELL_UNSUPPORTED+x} ]; then
        rm "$SHELL_DOT_DIR"cnti-testsuite
    fi
    rm -rf ~/.cnti-testsuite
    exit 0
fi


get_latest_release() {
    curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
        grep '"tag_name":' |                                            # Get tag line
        sed -E 's/.*"([^"]+)".*/\1/'                                    # Pluck JSON value
}

# Install CNTI Test Suite
LATEST_RELEASE=$(get_latest_release lfn-cnti/testsuite)
mkdir -p ~/.cnti-testsuite
DOWNLOAD_BASE=https://github.com/lfn-cnti/testsuite/releases/download/$LATEST_RELEASE
# Releases published before the binary rename ship the tarball and binary as cnf-testsuite.
if ! curl --fail --silent -L $DOWNLOAD_BASE/cnti-testsuite-$LATEST_RELEASE.tar.gz -o ~/.cnti-testsuite/cnti-testsuite.tar.gz; then
    # shellcheck disable=SC2015 # intentionally the pre-rename asset name
    curl --fail --silent -L $DOWNLOAD_BASE/cnf-testsuite-$LATEST_RELEASE.tar.gz -o ~/.cnti-testsuite/cnti-testsuite.tar.gz
fi
tar -C ~/.cnti-testsuite -xf ~/.cnti-testsuite/cnti-testsuite.tar.gz
if [ ! -f ~/.cnti-testsuite/cnti-testsuite ] && [ -f ~/.cnti-testsuite/cnf-testsuite ]; then
    mv ~/.cnti-testsuite/cnf-testsuite ~/.cnti-testsuite/cnti-testsuite
fi
chmod a+x ~/.cnti-testsuite/cnti-testsuite
rm ~/.cnti-testsuite/cnti-testsuite.tar.gz

if [ -z ${SHELL_UNSUPPORTED+x} ]; then

    if ! grep -Fxq "for s in $SHELL_DOT_DIR*" $SHELL_PROFILE; then
        echo "for s in $SHELL_DOT_DIR*" >> $SHELL_PROFILE
        echo 'do' >> $SHELL_PROFILE
        echo '   [[ -f "$s" ]] && source $s' >> $SHELL_PROFILE
        echo 'done' >> $SHELL_PROFILE
    fi

    mkdir -p $SHELL_DOT_DIR
    echo 'export PATH=$HOME/.cnti-testsuite:$PATH' > ${SHELL_DOT_DIR}cnti-testsuite
fi


if [ -z ${SHELL_UNSUPPORTED+x} ]; then

    if (return 0 2>/dev/null); then
        export PATH=$HOME/.cnti-testsuite:$PATH
        echo "cnti-testsuite has been successfully installed to ~/.cnti-testsuite and added to your PATH"
    else
        echo "cnti-testsuite has been successfully installed to: ~/.cnti-testsuite"
        echo "To use the cnti-testsuite please restart you terminal session to load the new PATH"
        echo "Or you can manually run 'export PATH=\$HOME/.cnti-testsuite:\$PATH' in your current session"
    fi
else
    echo "Because an unsupported shell was detected you will need to manually set you PATH, eg.:"
    echo "'export PATH=\$HOME/.cnti-testsuite:\$PATH'"
fi

