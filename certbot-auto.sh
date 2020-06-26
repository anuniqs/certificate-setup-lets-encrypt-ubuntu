#!/bin/sh
#
# Download and run the latest release version of the Certbot client.
#
# NOTE: THIS SCRIPT IS AUTO-GENERATED AND SELF-UPDATING
#
# IF YOU WANT TO EDIT IT LOCALLY, *ALWAYS* RUN YOUR COPY WITH THE
# "--no-self-upgrade" FLAG
#
# IF YOU WANT TO SEND PULL REQUESTS, THE REAL SOURCE FOR THIS FILE IS
# letsencrypt-auto-source/letsencrypt-auto.template AND
# letsencrypt-auto-source/pieces/bootstrappers/*

set -e  # Work even if somebody does "sh thisscript.sh".

# Note: you can set XDG_DATA_HOME or VENV_PATH before running this script,
# if you want to change where the virtual environment will be installed

# HOME might not be defined when being run through something like systemd
if [ -z "$HOME" ]; then
  HOME=~root
fi
if [ -z "$XDG_DATA_HOME" ]; then
  XDG_DATA_HOME=~/.local/share
fi
if [ -z "$VENV_PATH" ]; then
  # We export these values so they are preserved properly if this script is
  # rerun with sudo/su where $HOME/$XDG_DATA_HOME may have a different value.
  export OLD_VENV_PATH="$XDG_DATA_HOME/letsencrypt"
  export VENV_PATH="/opt/eff.org/certbot/venv"
fi
VENV_BIN="$VENV_PATH/bin"
BOOTSTRAP_VERSION_PATH="$VENV_PATH/certbot-auto-bootstrap-version.txt"
LE_AUTO_VERSION="1.5.0"
BASENAME=$(basename $0)
USAGE="Usage: $BASENAME [OPTIONS]
A self-updating wrapper script for the Certbot ACME client. When run, updates
to both this script and certbot will be downloaded and installed. After
ensuring you have the latest versions installed, certbot will be invoked with
all arguments you have provided.

Help for certbot itself cannot be provided until it is installed.

  --debug                                   attempt experimental installation
  -h, --help                                print this help
  -n, --non-interactive, --noninteractive   run without asking for user input
  --no-bootstrap                            do not install OS dependencies
  --no-permissions-check                    do not warn about file system permissions
  --no-self-upgrade                         do not download updates
  --os-packages-only                        install OS dependencies and exit
  --install-only                            install certbot, upgrade if needed, and exit
  -v, --verbose                             provide more output
  -q, --quiet                               provide only update/error output;
                                            implies --non-interactive

All arguments are accepted and forwarded to the Certbot client when run."
export CERTBOT_AUTO="$0"

for arg in "$@" ; do
  case "$arg" in
    --debug)
      DEBUG=1;;
    --os-packages-only)
      OS_PACKAGES_ONLY=1;;
    --install-only)
      INSTALL_ONLY=1;;
    --no-self-upgrade)
      # Do not upgrade this script (also prevents client upgrades, because each
      # copy of the script pins a hash of the python client)
      NO_SELF_UPGRADE=1;;
    --no-permissions-check)
      NO_PERMISSIONS_CHECK=1;;
    --no-bootstrap)
      NO_BOOTSTRAP=1;;
    --help)
      HELP=1;;
    --noninteractive|--non-interactive)
      NONINTERACTIVE=1;;
    --quiet)
      QUIET=1;;
    renew)
      ASSUME_YES=1;;
    --verbose)
      VERBOSE=1;;
    -[!-]*)
      OPTIND=1
      while getopts ":hnvq" short_arg $arg; do
        case "$short_arg" in
          h)
            HELP=1;;
          n)
            NONINTERACTIVE=1;;
          q)
            QUIET=1;;
          v)
            VERBOSE=1;;
        esac
      done;;
  esac
done

if [ $BASENAME = "letsencrypt-auto" ]; then
  # letsencrypt-auto does not respect --help or --yes for backwards compatibility
  NONINTERACTIVE=1
  HELP=0
fi

# Set ASSUME_YES to 1 if QUIET or NONINTERACTIVE
if [ "$QUIET" = 1 -o "$NONINTERACTIVE" = 1 ]; then
  ASSUME_YES=1
fi

say() {
    if [  "$QUIET" != 1 ]; then
        echo "$@"
    fi
}

error() {
    echo "$@"
}

# Support for busybox and others where there is no "command",
# but "which" instead
if command -v command > /dev/null 2>&1 ; then
  export EXISTS="command -v"
elif which which > /dev/null 2>&1 ; then
  export EXISTS="which"
else
  error "Cannot find command nor which... please install one!"
  exit 1
fi

# Certbot itself needs root access for almost all modes of operation.
# certbot-auto needs root access to bootstrap OS dependencies and install
# Certbot at a protected path so it can be safely run as root. To accomplish
# this, this script will attempt to run itself as root if it doesn't have the
# necessary privileges by using `sudo` or falling back to `su` if it is not
# available. The mechanism used to obtain root access can be set explicitly by
# setting the environment variable LE_AUTO_SUDO to 'sudo', 'su', 'su_sudo',
# 'SuSudo', or '' as used below.

# Because the parameters in `su -c` has to be a string,
# we need to properly escape it.
SuSudo() {
  args=""
  # This `while` loop iterates over all parameters given to this function.
  # For each parameter, all `'` will be replace by `'"'"'`, and the escaped string
  # will be wrapped in a pair of `'`, then appended to `$args` string
  # For example, `echo "It's only 1\$\!"` will be escaped to:
  #   'echo' 'It'"'"'s only 1$!'
  #     │       │└┼┘│
  #     │       │ │ └── `'s only 1$!'` the literal string
  #     │       │ └── `\"'\"` is a single quote (as a string)
  #     │       └── `'It'`, to be concatenated with the strings following it
  #     └── `echo` wrapped in a pair of `'`, it's totally fine for the shell command itself
  while [ $# -ne 0 ]; do
    args="$args'$(printf "%s" "$1" | sed -e "s/'/'\"'\"'/g")' "
    shift
  done
  su root -c "$args"
}

# Sets the environment variable SUDO to be the name of the program or function
# to call to get root access. If this script already has root privleges, SUDO
# is set to an empty string. The value in SUDO should be run with the command
# to called with root privileges as arguments.
SetRootAuthMechanism() {
  SUDO=""
  if [ -n "${LE_AUTO_SUDO+x}" ]; then
    case "$LE_AUTO_SUDO" in
      SuSudo|su_sudo|su)
        SUDO=SuSudo
        ;;
      sudo)
        SUDO="sudo -E"
        ;;
      '')
        # If we're not running with root, don't check that this script can only
        # be modified by system users and groups.
        NO_PERMISSIONS_CHECK=1
        ;;
      *)
        error "Error: unknown root authorization mechanism '$LE_AUTO_SUDO'."
        exit 1
    esac
    say "Using preset root authorization mechanism '$LE_AUTO_SUDO'."
  else
    if test "`id -u`" -ne "0" ; then
      if $EXISTS sudo 1>/dev/null 2>&1; then
        SUDO="sudo -E"
      else
        say \"sudo\" is not available, will use \"su\" for installation steps...
        SUDO=SuSudo
      fi
    fi
  fi
}

if [ "$1" = "--cb-auto-has-root" ]; then
  shift 1
else
  SetRootAuthMechanism
  if [ -n "$SUDO" ]; then
    say "Requesting to rerun $0 with root privileges..."
    $SUDO "$0" --cb-auto-has-root "$@"
    exit 0
  fi
fi

# Runs this script again with the given arguments. --cb-auto-has-root is added
# to the command line arguments to ensure we don't try to acquire root a
# second time. After the script is rerun, we exit the current script.
RerunWithArgs() {
    "$0" --cb-auto-has-root "$@"
    exit 0
}

BootstrapMessage() {
  # Arguments: Platform name
  say "Bootstrapping dependencies for $1... (you can skip this with --no-bootstrap)"
}

ExperimentalBootstrap() {
  # Arguments: Platform name, bootstrap function name
  if [ "$DEBUG" = 1 ]; then
    if [ "$2" != "" ]; then
      BootstrapMessage $1
      $2
    fi
  else
    error "FATAL: $1 support is very experimental at present..."
    error "if you would like to work on improving it, please ensure you have backups"
    error "and then run this script again with the --debug flag!"
    error "Alternatively, you can install OS dependencies yourself and run this script"
    error "again with --no-bootstrap."
    exit 1
  fi
}

DeprecationBootstrap() {
  # Arguments: Platform name, bootstrap function name
  if [ "$DEBUG" = 1 ]; then
    if [ "$2" != "" ]; then
      BootstrapMessage $1
      $2
    fi
  else
    error "WARNING: certbot-auto support for this $1 is DEPRECATED!"
    error "Please visit certbot.eff.org to learn how to download a version of"
    error "Certbot that is packaged for your system. While an existing version"
    error "of certbot-auto may work currently, we have stopped supporting updating"
    error "system packages for your system. Please switch to a packaged version"
    error "as soon as possible."
    exit 1
  fi
}

MIN_PYTHON_2_VERSION="2.7"
MIN_PYVER2=$(echo "$MIN_PYTHON_2_VERSION" | sed 's/\.//')
MIN_PYTHON_3_VERSION="3.5"
MIN_PYVER3=$(echo "$MIN_PYTHON_3_VERSION" | sed 's/\.//')
# Sets LE_PYTHON to Python version string and PYVER to the first two
# digits of the python version.
# MIN_PYVER and MIN_PYTHON_VERSION are also set by this function, and their
# values depend on if we try to use Python 3 or Python 2.
DeterminePythonVersion() {
  # Arguments: "NOCRASH" if we shouldn't crash if we don't find a good python
  #
  # If no Python is found, PYVER is set to 0.
  if [ "$USE_PYTHON_3" = 1 ]; then
    MIN_PYVER=$MIN_PYVER3
    MIN_PYTHON_VERSION=$MIN_PYTHON_3_VERSION
    for LE_PYTHON in "$LE_PYTHON" python3; do
      # Break (while keeping the LE_PYTHON value) if found.
      $EXISTS "$LE_PYTHON" > /dev/null && break
    done
  else
    MIN_PYVER=$MIN_PYVER2
    MIN_PYTHON_VERSION=$MIN_PYTHON_2_VERSION
    for LE_PYTHON in "$LE_PYTHON" python2.7 python27 python2 python; do
      # Break (while keeping the LE_PYTHON value) if found.
      $EXISTS "$LE_PYTHON" > /dev/null && break
    done
  fi
  if [ "$?" != "0" ]; then
    if [ "$1" != "NOCRASH" ]; then
      error "Cannot find any Pythons; please install one!"
      exit 1
    else
      PYVER=0
      return 0
    fi
  fi

  PYVER=$("$LE_PYTHON" -V 2>&1 | cut -d" " -f 2 | cut -d. -f1,2 | sed 's/\.//')
  if [ "$PYVER" -lt "$MIN_PYVER" ]; then
    if [ "$1" != "NOCRASH" ]; then
      error "You have an ancient version of Python entombed in your operating system..."
      error "This isn't going to work; you'll need at least version $MIN_PYTHON_VERSION."
      exit 1
    fi
  fi
}

# If new packages are installed by BootstrapDebCommon below, this version
# number must be increased.
BOOTSTRAP_DEB_COMMON_VERSION=1

BootstrapDebCommon() {
  # Current version tested with:
  #
  # - Ubuntu
  #     - 14.04 (x64)
  #     - 15.04 (x64)
  # - Debian
  #     - 7.9 "wheezy" (x64)
  #     - sid (2015-10-21) (x64)

  # Past versions tested with:
  #
  # - Debian 8.0 "jessie" (x64)
  # - Raspbian 7.8 (armhf)

  # Believed not to work:
  #
  # - Debian 6.0.10 "squeeze" (x64)

  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG='-qq'
  fi

  apt-get $QUIET_FLAG update || error apt-get update hit problems but continuing anyway...

  # virtualenv binary can be found in different packages depending on
  # distro version (#346)

  virtualenv=
  # virtual env is known to apt and is installable
  if apt-cache show virtualenv > /dev/null 2>&1 ; then
    if ! LC_ALL=C apt-cache --quiet=0 show virtualenv 2>&1 | grep -q 'No packages found'; then
      virtualenv="virtualenv"
    fi
  fi

  if apt-cache show python-virtualenv > /dev/null 2>&1; then
    virtualenv="$virtualenv python-virtualenv"
  fi

  augeas_pkg="libaugeas0 augeas-lenses"

  if [ "$ASSUME_YES" = 1 ]; then
    YES_FLAG="-y"
  fi

  apt-get install $QUIET_FLAG $YES_FLAG --no-install-recommends \
    python \
    python-dev \
    $virtualenv \
    gcc \
    $augeas_pkg \
    libssl-dev \
    openssl \
    libffi-dev \
    ca-certificates \


  if ! $EXISTS virtualenv > /dev/null ; then
    error Failed to install a working \"virtualenv\" command, exiting
    exit 1
  fi
}

# If new packages are installed by BootstrapRpmCommonBase below, version
# numbers in rpm_common.sh and rpm_python3.sh must be increased.

# Sets TOOL to the name of the package manager
# Sets appropriate values for YES_FLAG and QUIET_FLAG based on $ASSUME_YES and $QUIET_FLAG.
# Note: this function is called both while selecting the bootstrap scripts and
# during the actual bootstrap. Some things like prompting to user can be done in the latter
# case, but not in the former one.
InitializeRPMCommonBase() {
  if type dnf 2>/dev/null
  then
    TOOL=dnf
  elif type yum 2>/dev/null
  then
    TOOL=yum

  else
    error "Neither yum nor dnf found. Aborting bootstrap!"
    exit 1
  fi

  if [ "$ASSUME_YES" = 1 ]; then
    YES_FLAG="-y"
  fi
  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG='--quiet'
  fi
}

BootstrapRpmCommonBase() {
  # Arguments: whitespace-delimited python packages to install

  InitializeRPMCommonBase # This call is superfluous in practice

  pkgs="
    gcc
    augeas-libs
    openssl
    openssl-devel
    libffi-devel
    redhat-rpm-config
    ca-certificates
  "

  # Add the python packages
  pkgs="$pkgs
    $1
  "

  if $TOOL list installed "httpd" >/dev/null 2>&1; then
    pkgs="$pkgs
      mod_ssl
    "
  fi

  if ! $TOOL install $YES_FLAG $QUIET_FLAG $pkgs; then
    error "Could not install OS dependencies. Aborting bootstrap!"
    exit 1
  fi
}

# If new packages are installed by BootstrapRpmCommon below, this version
# number must be increased.
BOOTSTRAP_RPM_COMMON_VERSION=1

BootstrapRpmCommon() {
  # Tested with:
  #   - Fedora 20, 21, 22, 23 (x64)
  #   - Centos 7 (x64: on DigitalOcean droplet)
  #   - CentOS 7 Minimal install in a Hyper-V VM
  #   - CentOS 6

  InitializeRPMCommonBase

  # Most RPM distros use the "python" or "python-" naming convention.  Let's try that first.
  if $TOOL list python >/dev/null 2>&1; then
    python_pkgs="$python
      python-devel
      python-virtualenv
      python-tools
      python-pip
    "
  # Fedora 26 starts to use the prefix python2 for python2 based packages.
  # this elseif is theoretically for any Fedora over version 26:
  elif $TOOL list python2 >/dev/null 2>&1; then
    python_pkgs="$python2
      python2-libs
      python2-setuptools
      python2-devel
      python2-virtualenv
      python2-tools
      python2-pip
    "
  # Some distros and older versions of current distros use a "python27"
  # instead of the "python" or "python-" naming convention.
  else
    python_pkgs="$python27
      python27-devel
      python27-virtualenv
      python27-tools
      python27-pip
    "
  fi

  BootstrapRpmCommonBase "$python_pkgs"
}

# If new packages are installed by BootstrapRpmPython3 below, this version
# number must be increased.
BOOTSTRAP_RPM_PYTHON3_LEGACY_VERSION=1

# Checks if rh-python36 can be installed.
Python36SclIsAvailable() {
  InitializeRPMCommonBase >/dev/null 2>&1;

  if "${TOOL}" list rh-python36 >/dev/null 2>&1; then
    return 0
  fi
  if "${TOOL}" list centos-release-scl >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Try to enable rh-python36 from SCL if it is necessary and possible.
EnablePython36SCL() {
  if "$EXISTS" python3.6 > /dev/null 2> /dev/null; then
      return 0
  fi
  if [ ! -f /opt/rh/rh-python36/enable ]; then
      return 0
  fi
  set +e
  if ! . /opt/rh/rh-python36/enable; then
    error 'Unable to enable rh-python36!'
    exit 1
  fi
  set -e
}

# This bootstrap concerns old RedHat-based distributions that do not ship by default
# with Python 2.7, but only Python 2.6. We bootstrap them by enabling SCL and installing
# Python 3.6. Some of these distributions are: CentOS/RHEL/OL/SL 6.
BootstrapRpmPython3Legacy() {
  # Tested with:
  #   - CentOS 6

  InitializeRPMCommonBase

  if ! "${TOOL}" list rh-python36 >/dev/null 2>&1; then
    echo "To use Certbot on this operating system, packages from the SCL repository need to be installed."
    if ! "${TOOL}" list centos-release-scl >/dev/null 2>&1; then
      error "Enable the SCL repository and try running Certbot again."
      exit 1
    fi
    if [ "${ASSUME_YES}" = 1 ]; then
      /bin/echo -n "Enabling the SCL repository in 3 seconds... (Press Ctrl-C to cancel)"
      sleep 1s
      /bin/echo -ne "\e[0K\rEnabling the SCL repository in 2 seconds... (Press Ctrl-C to cancel)"
      sleep 1s
      /bin/echo -e "\e[0K\rEnabling the SCL repository in 1 second... (Press Ctrl-C to cancel)"
      sleep 1s
    fi
    if ! "${TOOL}" install "${YES_FLAG}" "${QUIET_FLAG}" centos-release-scl; then
      error "Could not enable SCL. Aborting bootstrap!"
      exit 1
    fi
  fi

  # CentOS 6 must use rh-python36 from SCL
  if "${TOOL}" list rh-python36 >/dev/null 2>&1; then
    python_pkgs="rh-python36-python
      rh-python36-python-virtualenv
      rh-python36-python-devel
    "
  else
    error "No supported Python package available to install. Aborting bootstrap!"
    exit 1
  fi

  BootstrapRpmCommonBase "${python_pkgs}"

  # Enable SCL rh-python36 after bootstrapping.
  EnablePython36SCL
}

# If new packages are installed by BootstrapRpmPython3 below, this version
# number must be increased.
BOOTSTRAP_RPM_PYTHON3_VERSION=1

BootstrapRpmPython3() {
  # Tested with:
  #   - Fedora 29

  InitializeRPMCommonBase

  # Fedora 29 must use python3-virtualenv
  if $TOOL list python3-virtualenv >/dev/null 2>&1; then
    python_pkgs="python3
      python3-virtualenv
      python3-devel
    "
  else
    error "No supported Python package available to install. Aborting bootstrap!"
    exit 1
  fi

  BootstrapRpmCommonBase "$python_pkgs"
}

# If new packages are installed by BootstrapSuseCommon below, this version
# number must be increased.
BOOTSTRAP_SUSE_COMMON_VERSION=1

BootstrapSuseCommon() {
  # SLE12 don't have python-virtualenv

  if [ "$ASSUME_YES" = 1 ]; then
    zypper_flags="-nq"
    install_flags="-l"
  fi

  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG='-qq'
  fi

  if zypper search -x python-virtualenv >/dev/null 2>&1; then
    OPENSUSE_VIRTUALENV_PACKAGES="python-virtualenv"
  else
    # Since Leap 15.0 (and associated Tumbleweed version), python-virtualenv
    # is a source package, and python2-virtualenv must be used instead.
    # Also currently python2-setuptools is not a dependency of python2-virtualenv,
    # while it should be. Installing it explicitly until upstream fix.
    OPENSUSE_VIRTUALENV_PACKAGES="python2-virtualenv python2-setuptools"
  fi

  zypper $QUIET_FLAG $zypper_flags in $install_flags \
    python \
    python-devel \
    $OPENSUSE_VIRTUALENV_PACKAGES \
    gcc \
    augeas-lenses \
    libopenssl-devel \
    libffi-devel \
    ca-certificates
}

# If new packages are installed by BootstrapArchCommon below, this version
# number must be increased.
BOOTSTRAP_ARCH_COMMON_VERSION=1

BootstrapArchCommon() {
  # Tested with:
  #   - ArchLinux (x86_64)
  #
  # "python-virtualenv" is Python3, but "python2-virtualenv" provides
  # only "virtualenv2" binary, not "virtualenv".

  deps="
    python2
    python-virtualenv
    gcc
    augeas
    openssl
    libffi
    ca-certificates
    pkg-config
  "

  # pacman -T exits with 127 if there are missing dependencies
  missing=$(pacman -T $deps) || true

  if [ "$ASSUME_YES" = 1 ]; then
    noconfirm="--noconfirm"
  fi

  if [ "$missing" ]; then
    if [ "$QUIET" = 1 ]; then
      pacman -S --needed $missing $noconfirm > /dev/null
    else
      pacman -S --needed $missing $noconfirm
    fi
  fi
}

# If new packages are installed by BootstrapGentooCommon below, this version
# number must be increased.
BOOTSTRAP_GENTOO_COMMON_VERSION=1

BootstrapGentooCommon() {
  PACKAGES="
    dev-lang/python:2.7
    dev-python/virtualenv
    app-admin/augeas
    dev-libs/openssl
    dev-libs/libffi
    app-misc/ca-certificates
    virtual/pkgconfig"

  ASK_OPTION="--ask"
  if [ "$ASSUME_YES" = 1 ]; then
    ASK_OPTION=""
  fi

  case "$PACKAGE_MANAGER" in
    (paludis)
      cave resolve --preserve-world --keep-targets if-possible $PACKAGES -x
      ;;
    (pkgcore)
      pmerge --noreplace --oneshot $ASK_OPTION $PACKAGES
      ;;
    (portage|*)
      emerge --noreplace --oneshot $ASK_OPTION $PACKAGES
      ;;
  esac
}

# If new packages are installed by BootstrapFreeBsd below, this version number
# must be increased.
BOOTSTRAP_FREEBSD_VERSION=1

BootstrapFreeBsd() {
  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG="--quiet"
  fi

  pkg install -Ay $QUIET_FLAG \
    python \
    py27-virtualenv \
    augeas \
    libffi
}

# If new packages are installed by BootstrapMac below, this version number must
# be increased.
BOOTSTRAP_MAC_VERSION=1

BootstrapMac() {
  if hash brew 2>/dev/null; then
    say "Using Homebrew to install dependencies..."
    pkgman=brew
    pkgcmd="brew install"
  elif hash port 2>/dev/null; then
    say "Using MacPorts to install dependencies..."
    pkgman=port
    pkgcmd="port install"
  else
    say "No Homebrew/MacPorts; installing Homebrew..."
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    pkgman=brew
    pkgcmd="brew install"
  fi

  $pkgcmd augeas
  if [ "$(which python)" = "/System/Library/Frameworks/Python.framework/Versions/2.7/bin/python" \
      -o "$(which python)" = "/usr/bin/python" ]; then
    # We want to avoid using the system Python because it requires root to use pip.
    # python.org, MacPorts or HomeBrew Python installations should all be OK.
    say "Installing python..."
    $pkgcmd python
  fi

  # Workaround for _dlopen not finding augeas on macOS
  if [ "$pkgman" = "port" ] && ! [ -e "/usr/local/lib/libaugeas.dylib" ] && [ -e "/opt/local/lib/libaugeas.dylib" ]; then
    say "Applying augeas workaround"
    mkdir -p /usr/local/lib/
    ln -s /opt/local/lib/libaugeas.dylib /usr/local/lib/
  fi

  if ! hash pip 2>/dev/null; then
    say "pip not installed"
    say "Installing pip..."
    curl --silent --show-error --retry 5 https://bootstrap.pypa.io/get-pip.py | python
  fi

  if ! hash virtualenv 2>/dev/null; then
    say "virtualenv not installed."
    say "Installing with pip..."
    pip install virtualenv
  fi
}

# If new packages are installed by BootstrapSmartOS below, this version number
# must be increased.
BOOTSTRAP_SMARTOS_VERSION=1

BootstrapSmartOS() {
  pkgin update
  pkgin -y install 'gcc49' 'py27-augeas' 'py27-virtualenv'
}

# If new packages are installed by BootstrapMageiaCommon below, this version
# number must be increased.
BOOTSTRAP_MAGEIA_COMMON_VERSION=1

BootstrapMageiaCommon() {
  if [ "$QUIET" = 1 ]; then
    QUIET_FLAG='--quiet'
  fi

  if ! urpmi --force $QUIET_FLAG \
      python \
      libpython-devel \
      python-virtualenv
    then
      error "Could not install Python dependencies. Aborting bootstrap!"
      exit 1
  fi

  if ! urpmi --force $QUIET_FLAG \
      git \
      gcc \
      python-augeas \
      libopenssl-devel \
      libffi-devel \
      rootcerts
    then
      error "Could not install additional dependencies. Aborting bootstrap!"
      exit 1
    fi
}


# Set Bootstrap to the function that installs OS dependencies on this system
# and BOOTSTRAP_VERSION to the unique identifier for the current version of
# that function. If Bootstrap is set to a function that doesn't install any
# packages BOOTSTRAP_VERSION is not set.
if [ -f /etc/debian_version ]; then
  Bootstrap() {
    BootstrapMessage "Debian-based OSes"
    BootstrapDebCommon
  }
  BOOTSTRAP_VERSION="BootstrapDebCommon $BOOTSTRAP_DEB_COMMON_VERSION"
elif [ -f /etc/mageia-release ]; then
  # Mageia has both /etc/mageia-release and /etc/redhat-release
  Bootstrap() {
    ExperimentalBootstrap "Mageia" BootstrapMageiaCommon
  }
  BOOTSTRAP_VERSION="BootstrapMageiaCommon $BOOTSTRAP_MAGEIA_COMMON_VERSION"
elif [ -f /etc/redhat-release ]; then
  # Run DeterminePythonVersion to decide on the basis of available Python versions
  # whether to use 2.x or 3.x on RedHat-like systems.
  # Then, revert LE_PYTHON to its previous state.
  prev_le_python="$LE_PYTHON"
  unset LE_PYTHON
  DeterminePythonVersion "NOCRASH"

  RPM_DIST_NAME=`(. /etc/os-release 2> /dev/null && echo $ID) || echo "unknown"`

  if [ "$PYVER" -eq 26 -a $(uname -m) != 'x86_64' ]; then
    # 32 bits CentOS 6 and affiliates are not supported anymore by certbot-auto.
    DEPRECATED_OS=1
  fi

  # Set RPM_DIST_VERSION to VERSION_ID from /etc/os-release after splitting on
  # '.' characters (e.g. "8.0" becomes "8"). If the command exits with an
  # error, RPM_DIST_VERSION is set to "unknown".
  RPM_DIST_VERSION=$( (. /etc/os-release 2> /dev/null && echo "$VERSION_ID") | cut -d '.' -f1 || echo "unknown")

  # If RPM_DIST_VERSION is an empty string or it contains any nonnumeric
  # characters, the value is unexpected so we set RPM_DIST_VERSION to 0.
  if [ -z "$RPM_DIST_VERSION" ] || [ -n "$(echo "$RPM_DIST_VERSION" | tr -d '[0-9]')" ]; then
     RPM_DIST_VERSION=0
  fi

  # Handle legacy RPM distributions
  if [ "$PYVER" -eq 26 ]; then
    # Check if an automated bootstrap can be achieved on this system.
    if ! Python36SclIsAvailable; then
      INTERACTIVE_BOOTSTRAP=1
    fi

    Bootstrap() {
      BootstrapMessage "Legacy RedHat-based OSes that will use Python3"
      BootstrapRpmPython3Legacy
    }
    USE_PYTHON_3=1
    BOOTSTRAP_VERSION="BootstrapRpmPython3Legacy $BOOTSTRAP_RPM_PYTHON3_LEGACY_VERSION"

    # Try now to enable SCL rh-python36 for systems already bootstrapped
    # NB: EnablePython36SCL has been defined along with BootstrapRpmPython3Legacy in certbot-auto
    EnablePython36SCL
  else
    # Starting to Fedora 29, python2 is on a deprecation path. Let's move to python3 then.
    # RHEL 8 also uses python3 by default.
    if [ "$RPM_DIST_NAME" = "fedora" -a "$RPM_DIST_VERSION" -ge 29 ]; then
      RPM_USE_PYTHON_3=1
    elif [ "$RPM_DIST_NAME" = "rhel" -a "$RPM_DIST_VERSION" -ge 8 ]; then
      RPM_USE_PYTHON_3=1
    elif [ "$RPM_DIST_NAME" = "centos" -a "$RPM_DIST_VERSION" -ge 8 ]; then
      RPM_USE_PYTHON_3=1
    else
      RPM_USE_PYTHON_3=0
    fi

    if [ "$RPM_USE_PYTHON_3" = 1 ]; then
      Bootstrap() {
        BootstrapMessage "RedHat-based OSes that will use Python3"
        BootstrapRpmPython3
      }
      USE_PYTHON_3=1
      BOOTSTRAP_VERSION="BootstrapRpmPython3 $BOOTSTRAP_RPM_PYTHON3_VERSION"
    else
      Bootstrap() {
        BootstrapMessage "RedHat-based OSes"
        BootstrapRpmCommon
      }
      BOOTSTRAP_VERSION="BootstrapRpmCommon $BOOTSTRAP_RPM_COMMON_VERSION"
    fi
  fi

  LE_PYTHON="$prev_le_python"
elif [ -f /etc/os-release ] && `grep -q openSUSE /etc/os-release` ; then
  Bootstrap() {
    BootstrapMessage "openSUSE-based OSes"
    BootstrapSuseCommon
  }
  BOOTSTRAP_VERSION="BootstrapSuseCommon $BOOTSTRAP_SUSE_COMMON_VERSION"
elif [ -f /etc/arch-release ]; then
  Bootstrap() {
    if [ "$DEBUG" = 1 ]; then
      BootstrapMessage "Archlinux"
      BootstrapArchCommon
    else
      error "Please use pacman to install letsencrypt packages:"
      error "# pacman -S certbot certbot-apache"
      error
      error "If you would like to use the virtualenv way, please run the script again with the"
      error "--debug flag."
      exit 1
    fi
  }
  BOOTSTRAP_VERSION="BootstrapArchCommon $BOOTSTRAP_ARCH_COMMON_VERSION"
elif [ -f /etc/manjaro-release ]; then
  Bootstrap() {
    ExperimentalBootstrap "Manjaro Linux" BootstrapArchCommon
  }
  BOOTSTRAP_VERSION="BootstrapArchCommon $BOOTSTRAP_ARCH_COMMON_VERSION"
elif [ -f /etc/gentoo-release ]; then
  DEPRECATED_OS=1
elif uname | grep -iq FreeBSD ; then
  DEPRECATED_OS=1
elif uname | grep -iq Darwin ; then
  DEPRECATED_OS=1
elif [ -f /etc/issue ] && grep -iq "Amazon Linux" /etc/issue ; then
  Bootstrap() {
    ExperimentalBootstrap "Amazon Linux" BootstrapRpmCommon
  }
  BOOTSTRAP_VERSION="BootstrapRpmCommon $BOOTSTRAP_RPM_COMMON_VERSION"
elif [ -f /etc/product ] && grep -q "Joyent Instance" /etc/product ; then
  Bootstrap() {
    ExperimentalBootstrap "Joyent SmartOS Zone" BootstrapSmartOS
  }
  BOOTSTRAP_VERSION="BootstrapSmartOS $BOOTSTRAP_SMARTOS_VERSION"
else
  Bootstrap() {
    error "Sorry, I don't know how to bootstrap Certbot on your operating system!"
    error
    error "You will need to install OS dependencies, configure virtualenv, and run pip install manually."
    error "Please see https://letsencrypt.readthedocs.org/en/latest/contributing.html#prerequisites"
    error "for more info."
    exit 1
  }
fi

# We handle this case after determining the normal bootstrap version to allow
# variables like USE_PYTHON_3 to be properly set. As described above, if the
# Bootstrap function doesn't install any packages, BOOTSTRAP_VERSION should not
# be set so we unset it here.
if [ "$NO_BOOTSTRAP" = 1 ]; then
  Bootstrap() {
    :
  }
  unset BOOTSTRAP_VERSION
fi

if [ "$DEPRECATED_OS" = 1 ]; then
  Bootstrap() {
    error "Skipping bootstrap because certbot-auto is deprecated on this system."
  }
  unset BOOTSTRAP_VERSION
fi

# Sets PREV_BOOTSTRAP_VERSION to the identifier for the bootstrap script used
# to install OS dependencies on this system. PREV_BOOTSTRAP_VERSION isn't set
# if it is unknown how OS dependencies were installed on this system.
SetPrevBootstrapVersion() {
  if [ -f $BOOTSTRAP_VERSION_PATH ]; then
    PREV_BOOTSTRAP_VERSION=$(cat "$BOOTSTRAP_VERSION_PATH")
  # The list below only contains bootstrap version strings that existed before
  # we started writing them to disk.
  #
  # DO NOT MODIFY THIS LIST UNLESS YOU KNOW WHAT YOU'RE DOING!
  elif grep -Fqx "$BOOTSTRAP_VERSION" << "UNLIKELY_EOF"
BootstrapDebCommon 1
BootstrapMageiaCommon 1
BootstrapRpmCommon 1
BootstrapSuseCommon 1
BootstrapArchCommon 1
BootstrapGentooCommon 1
BootstrapFreeBsd 1
BootstrapMac 1
BootstrapSmartOS 1
UNLIKELY_EOF
  then
    # If there's no bootstrap version saved to disk, but the currently selected
    # bootstrap script is from before we started saving the version number,
    # return the currently selected version to prevent us from rebootstrapping
    # unnecessarily.
    PREV_BOOTSTRAP_VERSION="$BOOTSTRAP_VERSION"
  fi
}

TempDir() {
  mktemp -d 2>/dev/null || mktemp -d -t 'le'  # Linux || macOS
}

# Returns 0 if a letsencrypt installation exists at $OLD_VENV_PATH, otherwise,
# returns a non-zero number.
OldVenvExists() {
    [ -n "$OLD_VENV_PATH" -a -f "$OLD_VENV_PATH/bin/letsencrypt" ]
}

# Given python path, version 1 and version 2, check if version 1 is outdated compared to version 2.
# An unofficial version provided as version 1 (eg. 0.28.0.dev0) will be treated
# specifically by printing "UNOFFICIAL". Otherwise, print "OUTDATED" if version 1
# is outdated, and "UP_TO_DATE" if not.
# This function relies only on installed python environment (2.x or 3.x) by certbot-auto.
CompareVersions() {
    "$1" - "$2" "$3" << "UNLIKELY_EOF"
import sys
from distutils.version import StrictVersion

try:
    current = StrictVersion(sys.argv[1])
except ValueError:
    sys.stdout.write('UNOFFICIAL')
    sys.exit()

try:
    remote = StrictVersion(sys.argv[2])
except ValueError:
    sys.stdout.write('UP_TO_DATE')
    sys.exit()

if current < remote:
    sys.stdout.write('OUTDATED')
else:
    sys.stdout.write('UP_TO_DATE')
UNLIKELY_EOF
}

# Create a new virtual environment for Certbot. It will overwrite any existing one.
# Parameters: LE_PYTHON, VENV_PATH, PYVER, VERBOSE
CreateVenv() {
    "$1" - "$2" "$3" "$4" << "UNLIKELY_EOF"
#!/usr/bin/env python
import os
import shutil
import subprocess
import sys


def create_venv(venv_path, pyver, verbose):
    if os.path.exists(venv_path):
        shutil.rmtree(venv_path)

    stdout = sys.stdout if verbose == '1' else open(os.devnull, 'w')

    if int(pyver) <= 27:
        # Use virtualenv binary
        environ = os.environ.copy()
        environ['VIRTUALENV_NO_DOWNLOAD'] = '1'
        command = ['virtualenv', '--no-site-packages', '--python', sys.executable, venv_path]
        subprocess.check_call(command, stdout=stdout, env=environ)
    else:
        # Use embedded venv module in Python 3
        command = [sys.executable, '-m', 'venv', venv_path]
        subprocess.check_call(command, stdout=stdout)


if __name__ == '__main__':
    create_venv(*sys.argv[1:])

UNLIKELY_EOF
}

# Check that the given PATH_TO_CHECK has secured permissions.
# Parameters: LE_PYTHON, PATH_TO_CHECK
CheckPathPermissions() {
    "$1" - "$2" << "UNLIKELY_EOF"
"""Verifies certbot-auto cannot be modified by unprivileged users.

This script takes the path to certbot-auto as its only command line
argument.  It then checks that the file can only be modified by uid/gid
< 1000 and if other users can modify the file, it prints a warning with
a suggestion on how to solve the problem.

Permissions on symlinks in the absolute path of certbot-auto are ignored
and only the canonical path to certbot-auto is checked. There could be
permissions problems due to the symlinks that are unreported by this
script, however, issues like this were not caused by our documentation
and are ignored for the sake of simplicity.

All warnings are printed to stdout rather than stderr so all stderr
output from this script can be suppressed to avoid printing messages if
this script fails for some reason.

"""
from __future__ import print_function

import os
import stat
import sys


FORUM_POST_URL = 'https://community.letsencrypt.org/t/certbot-auto-deployment-best-practices/91979/'


def has_safe_permissions(path):
    """Returns True if the given path has secure permissions.

    The permissions are considered safe if the file is only writable by
    uid/gid < 1000.

    The reason we allow more IDs than 0 is because on some systems such
    as Debian, system users/groups other than uid/gid 0 are used for the
    path we recommend in our instructions which is /usr/local/bin.  1000
    was chosen because on Debian 0-999 is reserved for system IDs[1] and
    on RHEL either 0-499 or 0-999 is reserved depending on the
    version[2][3]. Due to these differences across different OSes, this
    detection isn't perfect so we only determine permissions are
    insecure when we can be reasonably confident there is a problem
    regardless of the underlying OS.

    [1] https://www.debian.org/doc/debian-policy/ch-opersys.html#uid-and-gid-classes
    [2] https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/deployment_guide/ch-managing_users_and_groups
    [3] https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/system_administrators_guide/ch-managing_users_and_groups

    :param str path: filesystem path to check
    :returns: True if the path has secure permissions, otherwise, False
    :rtype: bool

    """
    # os.stat follows symlinks before obtaining information about a file.
    stat_result = os.stat(path)
    if stat_result.st_mode & stat.S_IWOTH:
        return False
    if stat_result.st_mode & stat.S_IWGRP and stat_result.st_gid >= 1000:
        return False
    if stat_result.st_mode & stat.S_IWUSR and stat_result.st_uid >= 1000:
        return False
    return True


def main(certbot_auto_path):
    current_path = os.path.realpath(certbot_auto_path)
    last_path = None
    permissions_ok = True
    # This loop makes use of the fact that os.path.dirname('/') == '/'.
    while current_path != last_path and permissions_ok:
        permissions_ok = has_safe_permissions(current_path)
        last_path = current_path
        current_path = os.path.dirname(current_path)

    if not permissions_ok:
        print('{0} has insecure permissions!'.format(certbot_auto_path))
        print('To learn how to fix them, visit {0}'.format(FORUM_POST_URL))


if __name__ == '__main__':
    main(sys.argv[1])

UNLIKELY_EOF
}

if [ "$1" = "--le-auto-phase2" ]; then
  # Phase 2: Create venv, install LE, and run.

  shift 1  # the --le-auto-phase2 arg

  if [ "$DEPRECATED_OS" = 1 ]; then
    # Phase 2 damage control mode for deprecated OSes.
    # In this situation, we bypass any bootstrap or certbot venv setup.
    error "Your system is not supported by certbot-auto anymore."

    if [ ! -d "$VENV_PATH" ] && OldVenvExists; then
      VENV_BIN="$OLD_VENV_PATH/bin"
    fi

    if [ -f "$VENV_BIN/letsencrypt" -a "$INSTALL_ONLY" != 1 ]; then
      error "Certbot will no longer receive updates."
      error "Please visit https://certbot.eff.org/ to check for other alternatives."
      "$VENV_BIN/letsencrypt" "$@"
      exit 0
    else
      error "Certbot cannot be installed."
      error "Please visit https://certbot.eff.org/ to check for other alternatives."
      exit 1
    fi
  fi

  SetPrevBootstrapVersion

  if [ -z "$PHASE_1_VERSION" -a "$USE_PYTHON_3" = 1 ]; then
    unset LE_PYTHON
  fi

  INSTALLED_VERSION="none"
  if [ -d "$VENV_PATH" ] || OldVenvExists; then
    # If the selected Bootstrap function isn't a noop and it differs from the
    # previously used version
    if [ -n "$BOOTSTRAP_VERSION" -a "$BOOTSTRAP_VERSION" != "$PREV_BOOTSTRAP_VERSION" ]; then
      # Check if we can rebootstrap without manual user intervention: this requires that
      # certbot-auto is in non-interactive mode AND selected bootstrap does not claim to
      # require a manual user intervention.
      if [ "$NONINTERACTIVE" = 1 -a "$INTERACTIVE_BOOTSTRAP" != 1 ]; then
        CAN_REBOOTSTRAP=1
      fi
      # Check if rebootstrap can be done non-interactively and current shell is non-interactive
      # (true if stdin and stdout are not attached to a terminal).
      if [ \( "$CAN_REBOOTSTRAP" = 1 \) -o \( \( -t 0 \) -a \( -t 1 \) \) ]; then
        if [ -d "$VENV_PATH" ]; then
          rm -rf "$VENV_PATH"
        fi
        # In the case the old venv was just a symlink to the new one,
        # OldVenvExists is now false because we deleted the venv at VENV_PATH.
        if OldVenvExists; then
          rm -rf "$OLD_VENV_PATH"
          ln -s "$VENV_PATH" "$OLD_VENV_PATH"
        fi
        RerunWithArgs "$@"
      # Otherwise bootstrap needs to be done manually by the user.
      else
        # If it is because bootstrapping is interactive, --non-interactive will be of no use.
        if [ "$INTERACTIVE_BOOTSTRAP" = 1 ]; then
          error "Skipping upgrade because new OS dependencies may need to be installed."
          error "This requires manual user intervention: please run this script again manually."
        # If this is because of the environment (eg. non interactive shell without
        # --non-interactive flag set), help the user in that direction.
        else
          error "Skipping upgrade because new OS dependencies may need to be installed."
          error
          error "To upgrade to a newer version, please run this script again manually so you can"
          error "approve changes or with --non-interactive on the command line to automatically"
          error "install any required packages."
        fi
        # Set INSTALLED_VERSION to be the same so we don't update the venv
        INSTALLED_VERSION="$LE_AUTO_VERSION"
        # Continue to use OLD_VENV_PATH if the new venv doesn't exist
        if [ ! -d "$VENV_PATH" ]; then
          VENV_BIN="$OLD_VENV_PATH/bin"
        fi
      fi
    elif [ -f "$VENV_BIN/letsencrypt" ]; then
      # --version output ran through grep due to python-cryptography DeprecationWarnings
      # grep for both certbot and letsencrypt until certbot and shim packages have been released
      INSTALLED_VERSION=$("$VENV_BIN/letsencrypt" --version 2>&1 | grep "^certbot\|^letsencrypt" | cut -d " " -f 2)
      if [ -z "$INSTALLED_VERSION" ]; then
          error "Error: couldn't get currently installed version for $VENV_BIN/letsencrypt: " 1>&2
          "$VENV_BIN/letsencrypt" --version
          exit 1
      fi
    fi
  fi

  if [ "$LE_AUTO_VERSION" != "$INSTALLED_VERSION" ]; then
    say "Creating virtual environment..."
    DeterminePythonVersion
    CreateVenv "$LE_PYTHON" "$VENV_PATH" "$PYVER" "$VERBOSE"

    if [ -n "$BOOTSTRAP_VERSION" ]; then
      echo "$BOOTSTRAP_VERSION" > "$BOOTSTRAP_VERSION_PATH"
    elif [ -n "$PREV_BOOTSTRAP_VERSION" ]; then
      echo "$PREV_BOOTSTRAP_VERSION" > "$BOOTSTRAP_VERSION_PATH"
    fi

    say "Installing Python packages..."
    TEMP_DIR=$(TempDir)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    # There is no $ interpolation due to quotes on starting heredoc delimiter.
    # -------------------------------------------------------------------------
    cat << "UNLIKELY_EOF" > "$TEMP_DIR/letsencrypt-auto-requirements.txt"
# This is the flattened list of packages certbot-auto installs.
# To generate this, do (with docker and package hashin installed):
# ```
# letsencrypt-auto-source/rebuild_dependencies.py \
#   letsencrypt-auto-source/pieces/dependency-requirements.txt
# ```
# If you want to update a single dependency, run commands similar to these:
# ```
# pip install hashin
# hashin -r dependency-requirements.txt cryptography==1.5.2
# ```
ConfigArgParse==1.0 \
    --hash=sha256:bf378245bc9cdc403a527e5b7406b991680c2a530e7e81af747880b54eb57133
certifi==2019.11.28 \
    --hash=sha256:017c25db2a153ce562900032d5bc68e9f191e44e9a0f762f373977de9df1fbb3 \
    --hash=sha256:25b64c7da4cd7479594d035c08c2d809eb4aab3a26e5a990ea98cc450c320f1f
cffi==1.13.2 \
    --hash=sha256:0b49274afc941c626b605fb59b59c3485c17dc776dc3cc7cc14aca74cc19cc42 \
    --hash=sha256:0e3ea92942cb1168e38c05c1d56b0527ce31f1a370f6117f1d490b8dcd6b3a04 \
    --hash=sha256:135f69aecbf4517d5b3d6429207b2dff49c876be724ac0c8bf8e1ea99df3d7e5 \
    --hash=sha256:19db0cdd6e516f13329cba4903368bff9bb5a9331d3410b1b448daaadc495e54 \
    --hash=sha256:2781e9ad0e9d47173c0093321bb5435a9dfae0ed6a762aabafa13108f5f7b2ba \
    --hash=sha256:291f7c42e21d72144bb1c1b2e825ec60f46d0a7468f5346841860454c7aa8f57 \
    --hash=sha256:2c5e309ec482556397cb21ede0350c5e82f0eb2621de04b2633588d118da4396 \
    --hash=sha256:2e9c80a8c3344a92cb04661115898a9129c074f7ab82011ef4b612f645939f12 \
    --hash=sha256:32a262e2b90ffcfdd97c7a5e24a6012a43c61f1f5a57789ad80af1d26c6acd97 \
    --hash=sha256:3c9fff570f13480b201e9ab69453108f6d98244a7f495e91b6c654a47486ba43 \
    --hash=sha256:415bdc7ca8c1c634a6d7163d43fb0ea885a07e9618a64bda407e04b04333b7db \
    --hash=sha256:42194f54c11abc8583417a7cf4eaff544ce0de8187abaf5d29029c91b1725ad3 \
    --hash=sha256:4424e42199e86b21fc4db83bd76909a6fc2a2aefb352cb5414833c030f6ed71b \
    --hash=sha256:4a43c91840bda5f55249413037b7a9b79c90b1184ed504883b72c4df70778579 \
    --hash=sha256:599a1e8ff057ac530c9ad1778293c665cb81a791421f46922d80a86473c13346 \
    --hash=sha256:5c4fae4e9cdd18c82ba3a134be256e98dc0596af1e7285a3d2602c97dcfa5159 \
    --hash=sha256:5ecfa867dea6fabe2a58f03ac9186ea64da1386af2159196da51c4904e11d652 \
    --hash=sha256:62f2578358d3a92e4ab2d830cd1c2049c9c0d0e6d3c58322993cc341bdeac22e \
    --hash=sha256:6471a82d5abea994e38d2c2abc77164b4f7fbaaf80261cb98394d5793f11b12a \
    --hash=sha256:6d4f18483d040e18546108eb13b1dfa1000a089bcf8529e30346116ea6240506 \
    --hash=sha256:71a608532ab3bd26223c8d841dde43f3516aa5d2bf37b50ac410bb5e99053e8f \
    --hash=sha256:74a1d8c85fb6ff0b30fbfa8ad0ac23cd601a138f7509dc617ebc65ef305bb98d \
    --hash=sha256:7b93a885bb13073afb0aa73ad82059a4c41f4b7d8eb8368980448b52d4c7dc2c \
    --hash=sha256:7d4751da932caaec419d514eaa4215eaf14b612cff66398dd51129ac22680b20 \
    --hash=sha256:7f627141a26b551bdebbc4855c1157feeef18241b4b8366ed22a5c7d672ef858 \
    --hash=sha256:8169cf44dd8f9071b2b9248c35fc35e8677451c52f795daa2bb4643f32a540bc \
    --hash=sha256:aa00d66c0fab27373ae44ae26a66a9e43ff2a678bf63a9c7c1a9a4d61172827a \
    --hash=sha256:ccb032fda0873254380aa2bfad2582aedc2959186cce61e3a17abc1a55ff89c3 \
    --hash=sha256:d754f39e0d1603b5b24a7f8484b22d2904fa551fe865fd0d4c3332f078d20d4e \
    --hash=sha256:d75c461e20e29afc0aee7172a0950157c704ff0dd51613506bd7d82b718e7410 \
    --hash=sha256:dcd65317dd15bc0451f3e01c80da2216a31916bdcffd6221ca1202d96584aa25 \
    --hash=sha256:e570d3ab32e2c2861c4ebe6ffcad6a8abf9347432a37608fe1fbd157b3f0036b \
    --hash=sha256:fd43a88e045cf992ed09fa724b5315b790525f2676883a6ea64e3263bae6549d
chardet==3.0.4 \
    --hash=sha256:84ab92ed1c4d4f16916e05906b6b75a6c0fb5db821cc65e70cbd64a3e2a5eaae \
    --hash=sha256:fc323ffcaeaed0e0a02bf4d117757b98aed530d9ed4531e3e15460124c106691
configobj==5.0.6 \
    --hash=sha256:a2f5650770e1c87fb335af19a9b7eb73fc05ccf22144eb68db7d00cd2bcb0902
cryptography==2.8 \
    --hash=sha256:02079a6addc7b5140ba0825f542c0869ff4df9a69c360e339ecead5baefa843c \
    --hash=sha256:1df22371fbf2004c6f64e927668734070a8953362cd8370ddd336774d6743595 \
    --hash=sha256:369d2346db5934345787451504853ad9d342d7f721ae82d098083e1f49a582ad \
    --hash=sha256:3cda1f0ed8747339bbdf71b9f38ca74c7b592f24f65cdb3ab3765e4b02871651 \
    --hash=sha256:44ff04138935882fef7c686878e1c8fd80a723161ad6a98da31e14b7553170c2 \
    --hash=sha256:4b1030728872c59687badcca1e225a9103440e467c17d6d1730ab3d2d64bfeff \
    --hash=sha256:58363dbd966afb4f89b3b11dfb8ff200058fbc3b947507675c19ceb46104b48d \
    --hash=sha256:6ec280fb24d27e3d97aa731e16207d58bd8ae94ef6eab97249a2afe4ba643d42 \
    --hash=sha256:7270a6c29199adc1297776937a05b59720e8a782531f1f122f2eb8467f9aab4d \
    --hash=sha256:73fd30c57fa2d0a1d7a49c561c40c2f79c7d6c374cc7750e9ac7c99176f6428e \
    --hash=sha256:7f09806ed4fbea8f51585231ba742b58cbcfbfe823ea197d8c89a5e433c7e912 \
    --hash=sha256:90df0cc93e1f8d2fba8365fb59a858f51a11a394d64dbf3ef844f783844cc793 \
    --hash=sha256:971221ed40f058f5662a604bd1ae6e4521d84e6cad0b7b170564cc34169c8f13 \
    --hash=sha256:a518c153a2b5ed6b8cc03f7ae79d5ffad7315ad4569b2d5333a13c38d64bd8d7 \
    --hash=sha256:b0de590a8b0979649ebeef8bb9f54394d3a41f66c5584fff4220901739b6b2f0 \
    --hash=sha256:b43f53f29816ba1db8525f006fa6f49292e9b029554b3eb56a189a70f2a40879 \
    --hash=sha256:d31402aad60ed889c7e57934a03477b572a03af7794fa8fb1780f21ea8f6551f \
    --hash=sha256:de96157ec73458a7f14e3d26f17f8128c959084931e8997b9e655a39c8fde9f9 \
    --hash=sha256:df6b4dca2e11865e6cfbfb708e800efb18370f5a46fd601d3755bc7f85b3a8a2 \
    --hash=sha256:ecadccc7ba52193963c0475ac9f6fa28ac01e01349a2ca48509667ef41ffd2cf \
    --hash=sha256:fb81c17e0ebe3358486cd8cc3ad78adbae58af12fc2bf2bc0bb84e8090fa5ce8
distro==1.4.0 \
    --hash=sha256:362dde65d846d23baee4b5c058c8586f219b5a54be1cf5fc6ff55c4578392f57 \
    --hash=sha256:eedf82a470ebe7d010f1872c17237c79ab04097948800029994fa458e52fb4b4
# Package enum34 needs to be explicitly limited to Python2.x, in order to avoid
# certbot-auto failures on Python 3.6+ which enum34 doesn't support. See #5456.
enum34==1.1.6 ; python_version < '3.4' \
    --hash=sha256:2d81cbbe0e73112bdfe6ef8576f2238f2ba27dd0d55752a776c41d38b7da2850 \
    --hash=sha256:644837f692e5f550741432dd3f223bbb9852018674981b1664e5dc339387588a \
    --hash=sha256:6bd0f6ad48ec2aa117d3d141940d484deccda84d4fcd884f5c3d93c23ecd8c79 \
    --hash=sha256:8ad8c4783bf61ded74527bffb48ed9b54166685e4230386a9ed9b1279e2df5b1
funcsigs==1.0.2 \
    --hash=sha256:330cc27ccbf7f1e992e69fef78261dc7c6569012cf397db8d3de0234e6c937ca \
    --hash=sha256:a7bb0f2cf3a3fd1ab2732cb49eba4252c2af4240442415b4abce3b87022a8f50
idna==2.8 \
    --hash=sha256:c357b3f628cf53ae2c4c05627ecc484553142ca23264e593d327bcde5e9c3407 \
    --hash=sha256:ea8b7f6188e6fa117537c3df7da9fc686d485087abf6ac197f9c46432f7e4a3c
ipaddress==1.0.23 \
    --hash=sha256:6e0f4a39e66cb5bb9a137b00276a2eff74f93b71dcbdad6f10ff7df9d3557fcc \
    --hash=sha256:b7f8e0369580bb4a24d5ba1d7cc29660a4a6987763faf1d8a8046830e020e7e2
josepy==1.2.0 \
    --hash=sha256:8ea15573203f28653c00f4ac0142520777b1c59d9eddd8da3f256c6ba3cac916 \
    --hash=sha256:9cec9a839fe9520f0420e4f38e7219525daccce4813296627436fe444cd002d3
mock==1.3.0 \
    --hash=sha256:1e247dbecc6ce057299eb7ee019ad68314bb93152e81d9a6110d35f4d5eca0f6 \
    --hash=sha256:3f573a18be94de886d1191f27c168427ef693e8dcfcecf95b170577b2eb69cbb
parsedatetime==2.5 \
    --hash=sha256:3b835fc54e472c17ef447be37458b400e3fefdf14bb1ffdedb5d2c853acf4ba1 \
    --hash=sha256:d2e9ddb1e463de871d32088a3f3cea3dc8282b1b2800e081bd0ef86900451667
pbr==5.4.4 \
    --hash=sha256:139d2625547dbfa5fb0b81daebb39601c478c21956dc57e2e07b74450a8c506b \
    --hash=sha256:61aa52a0f18b71c5cc58232d2cf8f8d09cd67fcad60b742a60124cb8d6951488
pyOpenSSL==19.1.0 \
    --hash=sha256:621880965a720b8ece2f1b2f54ea2071966ab00e2970ad2ce11d596102063504 \
    --hash=sha256:9a24494b2602aaf402be5c9e30a0b82d4a5c67528fe8fb475e3f3bc00dd69507
pyRFC3339==1.1 \
    --hash=sha256:67196cb83b470709c580bb4738b83165e67c6cc60e1f2e4f286cfcb402a926f4 \
    --hash=sha256:81b8cbe1519cdb79bed04910dd6fa4e181faf8c88dff1e1b987b5f7ab23a5b1a
pycparser==2.19 \
    --hash=sha256:a988718abfad80b6b157acce7bf130a30876d27603738ac39f140993246b25b3
pyparsing==2.4.6 \
    --hash=sha256:4c830582a84fb022400b85429791bc551f1f4871c33f23e44f353119e92f969f \
    --hash=sha256:c342dccb5250c08d45fd6f8b4a559613ca603b57498511740e65cd11a2e7dcec
python-augeas==0.5.0 \
    --hash=sha256:67d59d66cdba8d624e0389b87b2a83a176f21f16a87553b50f5703b23f29bac2
pytz==2019.3 \
    --hash=sha256:1c557d7d0e871de1f5ccd5833f60fb2550652da6be2693c1e02300743d21500d \
    --hash=sha256:b02c06db6cf09c12dd25137e563b31700d3b80fcc4ad23abb7a315f2789819be
requests==2.22.0 \
    --hash=sha256:11e007a8a2aa0323f5a921e9e6a2d7e4e67d9877e85773fba9ba6419025cbeb4 \
    --hash=sha256:9cf5292fcd0f598c671cfc1e0d7d1a7f13bb8085e9a590f48c010551dc6c4b31
requests-toolbelt==0.9.1 \
    --hash=sha256:380606e1d10dc85c3bd47bf5a6095f815ec007be7a8b69c878507068df059e6f \
    --hash=sha256:968089d4584ad4ad7c171454f0a5c6dac23971e9472521ea3b6d49d610aa6fc0
six==1.14.0 \
    --hash=sha256:236bdbdce46e6e6a3d61a337c0f8b763ca1e8717c03b369e87a7ec7ce1319c0a \
    --hash=sha256:8f3cd2e254d8f793e7f3d6d9df77b92252b52637291d0f0da013c76ea2724b6c
urllib3==1.25.8 \
    --hash=sha256:2f3db8b19923a873b3e5256dc9c2dedfa883e33d87c690d9c7913e1f40673cdc \
    --hash=sha256:87716c2d2a7121198ebcb7ce7cccf6ce5e9ba539041cfbaeecfb641dc0bf6acc
zope.component==4.6 \
    --hash=sha256:ec2afc5bbe611dcace98bb39822c122d44743d635dafc7315b9aef25097db9e6
zope.deferredimport==4.3.1 \
    --hash=sha256:57b2345e7b5eef47efcd4f634ff16c93e4265de3dcf325afc7315ade48d909e1 \
    --hash=sha256:9a0c211df44aa95f1c4e6d2626f90b400f56989180d3ef96032d708da3d23e0a
zope.deprecation==4.4.0 \
    --hash=sha256:0d453338f04bacf91bbfba545d8bcdf529aa829e67b705eac8c1a7fdce66e2df \
    --hash=sha256:f1480b74995958b24ce37b0ef04d3663d2683e5d6debc96726eff18acf4ea113
zope.event==4.4 \
    --hash=sha256:69c27debad9bdacd9ce9b735dad382142281ac770c4a432b533d6d65c4614bcf \
    --hash=sha256:d8e97d165fd5a0997b45f5303ae11ea3338becfe68c401dd88ffd2113fe5cae7
zope.hookable==5.0.0 \
    --hash=sha256:0992a0dd692003c09fb958e1480cebd1a28f2ef32faa4857d864f3ca8e9d6952 \
    --hash=sha256:0f325838dbac827a1e2ed5d482c1f2656b6844dc96aa098f7727e76395fcd694 \
    --hash=sha256:22a317ba00f61bac99eac1a5e330be7cb8c316275a21269ec58aa396b602af0c \
    --hash=sha256:25531cb5e7b35e8a6d1d6eddef624b9a22ce5dcf8f4448ef0f165acfa8c3fc21 \
    --hash=sha256:30890892652766fc80d11f078aca9a5b8150bef6b88aba23799581a53515c404 \
    --hash=sha256:342d682d93937e5b8c232baffb32a87d5eee605d44f74566657c64a239b7f342 \
    --hash=sha256:46b2fddf1f5aeb526e02b91f7e62afbb9fff4ffd7aafc97cdb00a0d717641567 \
    --hash=sha256:523318ff96df9b8d378d997c00c5d4cbfbff68dc48ff5ee5addabdb697d27528 \
    --hash=sha256:53aa02eb8921d4e667c69d76adeed8fe426e43870c101cb08dcd2f3468aff742 \
    --hash=sha256:62e79e8fdde087cb20822d7874758f5acbedbffaf3c0fbe06309eb8a41ee4e06 \
    --hash=sha256:74bf2f757f7385b56dc3548adae508d8b3ef952d600b4b12b88f7d1706b05dcc \
    --hash=sha256:751ee9d89eb96e00c1d7048da9725ce392a708ed43406416dc5ed61e4d199764 \
    --hash=sha256:7b83bc341e682771fe810b360cd5d9c886a948976aea4b979ff214e10b8b523b \
    --hash=sha256:81eeeb27dbb0ddaed8070daee529f0d1bfe4f74c7351cce2aaca3ea287c4cc32 \
    --hash=sha256:856509191e16930335af4d773c0fc31a17bae8991eb6f167a09d5eddf25b56cc \
    --hash=sha256:8853e81fd07b18fa9193b19e070dc0557848d9945b1d2dac3b7782543458c87d \
    --hash=sha256:94506a732da2832029aecdfe6ea07eb1b70ee06d802fff34e1b3618fe7cdf026 \
    --hash=sha256:95ad874a8cc94e786969215d660143817f745225579bfe318c4676e218d3147c \
    --hash=sha256:9758ec9174966ffe5c499b6c3d149f80aa0a9238020006a2b87c6af5963fcf48 \
    --hash=sha256:a169823e331da939aa7178fc152e65699aeb78957e46c6f80ccb50ee4c3616c2 \
    --hash=sha256:a67878a798f6ca292729a28c2226592b3d000dc6ee7825d31887b553686c7ac7 \
    --hash=sha256:a9a6d9eb2319a09905670810e2de971d6c49013843700b4975e2fc0afe96c8db \
    --hash=sha256:b3e118b58a3d2301960e6f5f25736d92f6b9f861728d3b8c26d69f54d8a157d2 \
    --hash=sha256:ca6705c2a1fb5059a4efbe9f5426be4cdf71b3c9564816916fc7aa7902f19ede \
    --hash=sha256:cf711527c9d4ae72085f137caffb4be74fc007ffb17cd103628c7d5ba17e205f \
    --hash=sha256:d087602a6845ebe9d5a1c5a949fedde2c45f372d77fbce4f7fe44b68b28a1d03 \
    --hash=sha256:d1080e1074ddf75ad6662a9b34626650759c19a9093e1a32a503d37e48da135b \
    --hash=sha256:db9c60368aff2b7e6c47115f3ad9bd6e96aa298b12ed5f8cb13f5673b30be565 \
    --hash=sha256:dbeb127a04473f5a989169eb400b67beb921c749599b77650941c21fe39cb8d9 \
    --hash=sha256:dca336ca3682d869d291d7cd18284f6ff6876e4244eb1821430323056b000e2c \
    --hash=sha256:dd69a9be95346d10c853b6233fcafe3c0315b89424b378f2ad45170d8e161568 \
    --hash=sha256:dd79f8fae5894f1ee0a0042214685f2d039341250c994b825c10a4cd075d80f6 \
    --hash=sha256:e647d850aa1286d98910133cee12bd87c354f7b7bb3f3cd816a62ba7fa2f7007 \
    --hash=sha256:f37a210b5c04b2d4e4bac494ab15b70196f219a1e1649ddca78560757d4278fb \
    --hash=sha256:f67820b6d33a705dc3c1c457156e51686f7b350ff57f2112e1a9a4dad38ec268 \
    --hash=sha256:f68969978ccf0e6123902f7365aae5b7a9e99169d4b9105c47cf28e788116894 \
    --hash=sha256:f717a0b34460ae1ac0064e91b267c0588ac2c098ffd695992e72cd5462d97a67 \
    --hash=sha256:f9d58ccec8684ca276d5a4e7b0dfacca028336300a8f715d616d9f0ce9ae8096 \
    --hash=sha256:fcc3513a54e656067cbf7b98bab0d6b9534b9eabc666d1f78aad6acdf0962736
zope.interface==4.7.1 \
    --hash=sha256:048b16ac882a05bc7ef534e8b9f15c9d7a6c190e24e8938a19b7617af4ed854a \
    --hash=sha256:05816cf8e7407cf62f2ec95c0a5d69ec4fa5741d9ccd10db9f21691916a9a098 \
    --hash=sha256:065d6a1ac89d35445168813bed45048ed4e67a4cdfc5a68fdb626a770378869f \
    --hash=sha256:14157421f4121a57625002cc4f48ac7521ea238d697c4a4459a884b62132b977 \
    --hash=sha256:18dc895945694f397a0be86be760ff664b790f95d8e7752d5bab80284ff9105d \
    --hash=sha256:1962c9f838bd6ae4075d0014f72697510daefc7e1c7e48b2607df0b6e157989c \
    --hash=sha256:1a67408cacd198c7e6274a19920bb4568d56459e659e23c4915528686ac1763a \
    --hash=sha256:21bf781076dd616bd07cf0223f79d61ab4f45176076f90bc2890e18c48195da4 \
    --hash=sha256:21c0a5d98650aebb84efa16ce2c8df1a46bdc4fe8a9e33237d0ca0b23f416ead \
    --hash=sha256:23cfeea25d1e42ff3bf4f9a0c31e9d5950aa9e7c4b12f0c4bd086f378f7b7a71 \
    --hash=sha256:24b6fce1fb71abf9f4093e3259084efcc0ef479f89356757780685bd2b06ef37 \
    --hash=sha256:24f84ce24eb6b5fcdcb38ad9761524f1ae96f7126abb5e597f8a3973d9921409 \
    --hash=sha256:25e0ef4a824017809d6d8b0ce4ab3288594ba283e4d4f94d8cfb81d73ed65114 \
    --hash=sha256:2e8fdd625e9aba31228e7ddbc36bad5c38dc3ee99a86aa420f89a290bd987ce9 \
    --hash=sha256:2f3bc2f49b67b1bea82b942d25bc958d4f4ea6709b411cb2b6b9718adf7914ce \
    --hash=sha256:35d24be9d04d50da3a6f4d61de028c1dd087045385a0ff374d93ef85af61b584 \
    --hash=sha256:35dbe4e8c73003dff40dfaeb15902910a4360699375e7b47d3c909a83ff27cd0 \
    --hash=sha256:3dfce831b824ab5cf446ed0c350b793ac6fa5fe33b984305cb4c966a86a8fb79 \
    --hash=sha256:3f7866365df5a36a7b8de8056cd1c605648f56f9a226d918ed84c85d25e8d55f \
    --hash=sha256:455cc8c01de3bac6f9c223967cea41f4449f58b4c2e724ec8177382ddd183ab4 \
    --hash=sha256:4bb937e998be9d5e345f486693e477ba79e4344674484001a0b646be1d530487 \
    --hash=sha256:52303a20902ca0888dfb83230ca3ee6fbe63c0ad1dd60aa0bba7958ccff454d8 \
    --hash=sha256:6e0a897d4e09859cc80c6a16a29697406ead752292ace17f1805126a4f63c838 \
    --hash=sha256:6e1816e7c10966330d77af45f77501f9a68818c065dec0ad11d22b50a0e212e7 \
    --hash=sha256:73b5921c5c6ce3358c836461b5470bf675601c96d5e5d8f2a446951470614f67 \
    --hash=sha256:8093cd45cdb5f6c8591cfd1af03d32b32965b0f79b94684cd0c9afdf841982bb \
    --hash=sha256:864b4a94b60db301899cf373579fd9ef92edddbf0fb2cd5ae99f53ef423ccc56 \
    --hash=sha256:8a27b4d3ea9c6d086ce8e7cdb3e8d319b6752e2a03238a388ccc83ccbe165f50 \
    --hash=sha256:91b847969d4784abd855165a2d163f72ac1e58e6dce09a5e46c20e58f19cc96d \
    --hash=sha256:b47b1028be4758c3167e474884ccc079b94835f058984b15c145966c4df64d27 \
    --hash=sha256:b68814a322835d8ad671b7acc23a3b2acecba527bb14f4b53fc925f8a27e44d8 \
    --hash=sha256:bcb50a032c3b6ec7fb281b3a83d2b31ab5246c5b119588725b1350d3a1d9f6a3 \
    --hash=sha256:c56db7d10b25ce8918b6aec6b08ac401842b47e6c136773bfb3b590753f7fb67 \
    --hash=sha256:c94b77a13d4f47883e4f97f9fa00f5feadd38af3e6b3c7be45cfdb0a14c7149b \
    --hash=sha256:db381f6fdaef483ad435f778086ccc4890120aff8df2ba5cfeeac24d280b3145 \
    --hash=sha256:e6487d01c8b7ed86af30ea141fcc4f93f8a7dde26f94177c1ad637c353bd5c07 \
    --hash=sha256:e86923fa728dfba39c5bb6046a450bd4eec8ad949ac404eca728cfce320d1732 \
    --hash=sha256:f6ca36dc1e9eeb46d779869c60001b3065fb670b5775c51421c099ea2a77c3c9 \
    --hash=sha256:fb62f2cbe790a50d95593fb40e8cca261c31a2f5637455ea39440d6457c2ba25
zope.proxy==4.3.3 \
    --hash=sha256:04646ac04ffa9c8e32fb2b5c3cd42995b2548ea14251f3c21ca704afae88e42c \
    --hash=sha256:07b6bceea232559d24358832f1cd2ed344bbf05ca83855a5b9698b5f23c5ed60 \
    --hash=sha256:1ef452cc02e0e2f8e3c917b1a5b936ef3280f2c2ca854ee70ac2164d1655f7e6 \
    --hash=sha256:22bf61857c5977f34d4e391476d40f9a3b8c6ab24fb0cac448d42d8f8b9bf7b2 \
    --hash=sha256:299870e3428cbff1cd9f9b34144e76ecdc1d9e3192a8cf5f1b0258f47a239f58 \
    --hash=sha256:2bfc36bfccbe047671170ea5677efd3d5ab730a55d7e45611d76d495e5b96766 \
    --hash=sha256:32e82d5a640febc688c0789e15ea875bf696a10cf358f049e1ed841f01710a9b \
    --hash=sha256:3b2051bdc4bc3f02fa52483f6381cf40d4d48167645241993f9d7ebbd142ed9b \
    --hash=sha256:3f734bd8a08f5185a64fb6abb8f14dc97ec27a689ca808fb7a83cdd38d745e4f \
    --hash=sha256:3f78dd8de3112df8bbd970f0916ac876dc3fbe63810bd1cf7cc5eec4cbac4f04 \
    --hash=sha256:4eabeb48508953ba1f3590ad0773b8daea9e104eec66d661917e9bbcd7125a67 \
    --hash=sha256:4f05ecc33808187f430f249cb1ccab35c38f570b181f2d380fbe253da94b18d8 \
    --hash=sha256:4f4f4cbf23d3afc1526294a31e7b3eaa0f682cc28ac5366065dc1d6bb18bd7be \
    --hash=sha256:5483d5e70aacd06f0aa3effec9fed597c0b50f45060956eeeb1203c44d4338c3 \
    --hash=sha256:56a5f9b46892b115a75d0a1f2292431ad5988461175826600acc69a24cb3edee \
    --hash=sha256:64bb63af8a06f736927d260efdd4dfc5253d42244f281a8063e4b9eea2ddcbc5 \
    --hash=sha256:653f8cbefcf7c6ac4cece2cdef367c4faa2b7c19795d52bd7cbec11a8739a7c1 \
    --hash=sha256:664211d63306e4bd4eec35bf2b4bd9db61c394037911cf2d1804c43b511a49f1 \
    --hash=sha256:6651e6caed66a8fff0fef1a3e81c0ed2253bf361c0fdc834500488732c5d16e9 \
    --hash=sha256:6c1fba6cdfdf105739d3069cf7b07664f2944d82a8098218ab2300a82d8f40fc \
    --hash=sha256:6e64246e6e9044a4534a69dca1283c6ddab6e757be5e6874f69024329b3aa61f \
    --hash=sha256:838390245c7ec137af4993c0c8052f49d5ec79e422b4451bfa37fee9b9ccaa01 \
    --hash=sha256:856b410a14793069d8ba35f33fff667213ea66f2df25a0024cc72a7493c56d4c \
    --hash=sha256:8b932c364c1d1605a91907a41128ed0ee8a2d326fc0fafb2c55cd46f545f4599 \
    --hash=sha256:9086cf6d20f08dae7f296a78f6c77d1f8d24079d448f023ee0eb329078dd35e1 \
    --hash=sha256:9698533c14afa0548188de4968a7932d1f3f965f3f5ba1474de673596bb875af \
    --hash=sha256:9b12b05dd7c28f5068387c1afee8cb94f9d02501e7ef495a7c5c7e27139b96ad \
    --hash=sha256:a884c7426a5bc6fb7fc71a55ad14e66818e13f05b78b20a6f37175f324b7acb8 \
    --hash=sha256:abe9e7f1a3e76286c5f5baf2bf5162d41dc0310da493b34a2c36555f38d928f7 \
    --hash=sha256:bd6fde63b015a27262be06bd6bbdd895273cc2bdf2d4c7e1c83711d26a8fbace \
    --hash=sha256:bda7c62c954f47b87ed9a89f525eee1b318ec7c2162dfdba76c2ccfa334e0caa \
    --hash=sha256:be8a4908dd3f6e965993c0068b006bdbd0474fbcbd1da4893b49356e73fc1557 \
    --hash=sha256:ced65fc3c7d7205267506d854bb1815bb445899cca9d21d1d4b949070a635546 \
    --hash=sha256:dac4279aa05055d3897ab5e5ee5a7b39db121f91df65a530f8b1ac7f9bd93119 \
    --hash=sha256:e4f1863056e3e4f399c285b67fa816f411a7bfa1c81ef50e186126164e396e59 \
    --hash=sha256:ecd85f68b8cd9ab78a0141e87ea9a53b2f31fd9b1350a1c44da1f7481b5363ef \
    --hash=sha256:ed269b83750413e8fc5c96276372f49ee3fcb7ed61c49fe8e5a67f54459a5a4a \
    --hash=sha256:f19b0b80cba73b204dee68501870b11067711d21d243fb6774256d3ca2e5391f \
    --hash=sha256:ffdafb98db7574f9da84c489a10a5d582079a888cb43c64e9e6b0e3fe1034685

# Contains the requirements for the letsencrypt package.
#
# Since the letsencrypt package depends on certbot and using pip with hashes
# requires that all installed packages have hashes listed, this allows
# dependency-requirements.txt to be used without requiring a hash for a
# (potentially unreleased) Certbot package.

letsencrypt==0.7.0 \
    --hash=sha256:105a5fb107e45bcd0722eb89696986dcf5f08a86a321d6aef25a0c7c63375ade \
    --hash=sha256:c36e532c486a7e92155ee09da54b436a3c420813ec1c590b98f635d924720de9

certbot==1.5.0 \
    --hash=sha256:ec1f01af06b52a6f079f5b02cb70e88f0671a7b13ecb3e45b040563e32c6e53a \
    --hash=sha256:c52017a4f84137e1312c898d6ae69c5f7977d79d2bd4c2df013cbbf39b6539bf
acme==1.5.0 \
    --hash=sha256:66de67b394bb7606f97f2c21507e6eb6a88936db2a940f5c4893025f87e3852a \
    --hash=sha256:b051ff7dd3935b2032c2f8c8386e905d9b658eba9f3455e352650d85bea9c8f0
certbot-apache==1.5.0 \
    --hash=sha256:d2c28be6dcd6c56a8040c8c733e72c1341238b1b47fb59f544eb832b9d5c81ba \
    --hash=sha256:3eec5a49ae4fcf86213f962eb1e11d8a725b65e7dcee18f9b92c7aa73f821764
certbot-nginx==1.5.0 \
    --hash=sha256:3d27fd02ebe15b07ce5fa9525ceeda82aa5fdc45aa064729434faff0442d1f91 \
    --hash=sha256:b38f101588af6d2b8ea7c2e3334f249afbe14461a85add2f1420091d860df983

UNLIKELY_EOF
    # -------------------------------------------------------------------------
    cat << "UNLIKELY_EOF" > "$TEMP_DIR/pipstrap.py"
#!/usr/bin/env python
"""A small script that can act as a trust root for installing pip >=8
Embed this in your project, and your VCS checkout is all you have to trust. In
a post-peep era, this lets you claw your way to a hash-checking version of pip,
with which you can install the rest of your dependencies safely. All it assumes
is Python 2.6 or better and *some* version of pip already installed. If
anything goes wrong, it will exit with a non-zero status code.
"""
# This is here so embedded copies are MIT-compliant:
# Copyright (c) 2016 Erik Rose
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
from __future__ import print_function
from distutils.version import StrictVersion
from hashlib import sha256
from os import environ
from os.path import join
from shutil import rmtree
try:
    from subprocess import check_output
except ImportError:
    from subprocess import CalledProcessError, PIPE, Popen

    def check_output(*popenargs, **kwargs):
        if 'stdout' in kwargs:
            raise ValueError('stdout argument not allowed, it will be '
                             'overridden.')
        process = Popen(stdout=PIPE, *popenargs, **kwargs)
        output, unused_err = process.communicate()
        retcode = process.poll()
        if retcode:
            cmd = kwargs.get("args")
            if cmd is None:
                cmd = popenargs[0]
            raise CalledProcessError(retcode, cmd)
        return output
import sys
from tempfile import mkdtemp
try:
    from urllib2 import build_opener, HTTPHandler, HTTPSHandler
except ImportError:
    from urllib.request import build_opener, HTTPHandler, HTTPSHandler
try:
    from urlparse import urlparse
except ImportError:
    from urllib.parse import urlparse  # 3.4


__version__ = 1, 5, 1
PIP_VERSION = '9.0.1'
DEFAULT_INDEX_BASE = 'https://pypi.python.org'


# wheel has a conditional dependency on argparse:
maybe_argparse = (
    [('18/dd/e617cfc3f6210ae183374cd9f6a26b20514bbb5a792af97949c5aacddf0f/'
      'argparse-1.4.0.tar.gz',
      '62b089a55be1d8949cd2bc7e0df0bddb9e028faefc8c32038cc84862aefdd6e4')]
    if sys.version_info < (2, 7, 0) else [])


PACKAGES = maybe_argparse + [
    # Pip has no dependencies, as it vendors everything:
    ('11/b6/abcb525026a4be042b486df43905d6893fb04f05aac21c32c638e939e447/'
     'pip-{0}.tar.gz'.format(PIP_VERSION),
     '09f243e1a7b461f654c26a725fa373211bb7ff17a9300058b205c61658ca940d'),
    # This version of setuptools has only optional dependencies:
    ('37/1b/b25507861991beeade31473868463dad0e58b1978c209de27384ae541b0b/'
     'setuptools-40.6.3.zip',
     '3b474dad69c49f0d2d86696b68105f3a6f195f7ab655af12ef9a9c326d2b08f8'),
    ('c9/1d/bd19e691fd4cfe908c76c429fe6e4436c9e83583c4414b54f6c85471954a/'
     'wheel-0.29.0.tar.gz',
     '1ebb8ad7e26b448e9caa4773d2357849bf80ff9e313964bcaf79cbf0201a1648')
]


class HashError(Exception):
    def __str__(self):
        url, path, actual, expected = self.args
        return ('{url} did not match the expected hash {expected}. Instead, '
                'it was {actual}. The file (left at {path}) may have been '
                'tampered with.'.format(**locals()))


def hashed_download(url, temp, digest):
    """Download ``url`` to ``temp``, make sure it has the SHA-256 ``digest``,
    and return its path."""
    # Based on pip 1.4.1's URLOpener but with cert verification removed. Python
    # >=2.7.9 verifies HTTPS certs itself, and, in any case, the cert
    # authenticity has only privacy (not arbitrary code execution)
    # implications, since we're checking hashes.
    def opener(using_https=True):
        opener = build_opener(HTTPSHandler())
        if using_https:
            # Strip out HTTPHandler to prevent MITM spoof:
            for handler in opener.handlers:
                if isinstance(handler, HTTPHandler):
                    opener.handlers.remove(handler)
        return opener

    def read_chunks(response, chunk_size):
        while True:
            chunk = response.read(chunk_size)
            if not chunk:
                break
            yield chunk

    parsed_url = urlparse(url)
    response = opener(using_https=parsed_url.scheme == 'https').open(url)
    path = join(temp, parsed_url.path.split('/')[-1])
    actual_hash = sha256()
    with open(path, 'wb') as file:
        for chunk in read_chunks(response, 4096):
            file.write(chunk)
            actual_hash.update(chunk)

    actual_digest = actual_hash.hexdigest()
    if actual_digest != digest:
        raise HashError(url, path, actual_digest, digest)
    return path


def get_index_base():
    """Return the URL to the dir containing the "packages" folder.
    Try to wring something out of PIP_INDEX_URL, if set. Hack "/simple" off the
    end if it's there; that is likely to give us the right dir.
    """
    env_var = environ.get('PIP_INDEX_URL', '').rstrip('/')
    if env_var:
        SIMPLE = '/simple'
        if env_var.endswith(SIMPLE):
            return env_var[:-len(SIMPLE)]
        else:
            return env_var
    else:
        return DEFAULT_INDEX_BASE


def main():
    python = sys.executable or 'python'
    pip_version = StrictVersion(check_output([python, '-m', 'pip', '--version'])
                                .decode('utf-8').split()[1])
    has_pip_cache = pip_version >= StrictVersion('6.0')
    index_base = get_index_base()
    temp = mkdtemp(prefix='pipstrap-')
    try:
        downloads = [hashed_download(index_base + '/packages/' + path,
                                     temp,
                                     digest)
                     for path, digest in PACKAGES]
        # Calling pip as a module is the preferred way to avoid problems about pip self-upgrade.
        command = [python, '-m', 'pip', 'install', '--no-index', '--no-deps', '-U']
        # Disable cache since it is not used and it otherwise sometimes throws permission warnings:
        command.extend(['--no-cache-dir'] if has_pip_cache else [])
        command.extend(downloads)
        check_output(command)
    except HashError as exc:
        print(exc)
    except Exception:
        rmtree(temp)
        raise
    else:
        rmtree(temp)
        return 0
    return 1


if __name__ == '__main__':
    sys.exit(main())

UNLIKELY_EOF
    # -------------------------------------------------------------------------
    # Set PATH so pipstrap upgrades the right (v)env:
    PATH="$VENV_BIN:$PATH" "$VENV_BIN/python" "$TEMP_DIR/pipstrap.py"
    set +e
    if [ "$VERBOSE" = 1 ]; then
      "$VENV_BIN/pip" install --disable-pip-version-check --no-cache-dir --require-hashes -r "$TEMP_DIR/letsencrypt-auto-requirements.txt"
    else
      PIP_OUT=`"$VENV_BIN/pip" install --disable-pip-version-check --no-cache-dir --require-hashes -r "$TEMP_DIR/letsencrypt-auto-requirements.txt" 2>&1`
    fi
    PIP_STATUS=$?
    set -e
    if [ "$PIP_STATUS" != 0 ]; then
      # Report error. (Otherwise, be quiet.)
      error "Had a problem while installing Python packages."
      if [ "$VERBOSE" != 1 ]; then
        error
        error "pip prints the following errors: "
        error "====================================================="
        error "$PIP_OUT"
        error "====================================================="
        error
        error "Certbot has problem setting up the virtual environment."

        if `echo $PIP_OUT | grep -q Killed` || `echo $PIP_OUT | grep -q "allocate memory"` ; then
          error
          error "Based on your pip output, the problem can likely be fixed by "
          error "increasing the available memory."
        else
          error
          error "We were not be able to guess the right solution from your pip "
          error "output."
        fi

        error
        error "Consult https://certbot.eff.org/docs/install.html#problems-with-python-virtual-environment"
        error "for possible solutions."
        error "You may also find some support resources at https://certbot.eff.org/support/ ."
      fi
      rm -rf "$VENV_PATH"
      exit 1
    fi

    if [ -d "$OLD_VENV_PATH" -a ! -L "$OLD_VENV_PATH" ]; then
      rm -rf "$OLD_VENV_PATH"
      ln -s "$VENV_PATH" "$OLD_VENV_PATH"
    fi

    say "Installation succeeded."
  fi

  # If you're modifying any of the code after this point in this current `if` block, you
  # may need to update the "$DEPRECATED_OS" = 1 case at the beginning of phase 2 as well.

  if [ "$INSTALL_ONLY" = 1 ]; then
    say "Certbot is installed."
    exit 0
  fi

  "$VENV_BIN/letsencrypt" "$@"

else
  # Phase 1: Upgrade certbot-auto if necessary, then self-invoke.
  #
  # Each phase checks the version of only the thing it is responsible for
  # upgrading. Phase 1 checks the version of the latest release of
  # certbot-auto (which is always the same as that of the certbot
  # package). Phase 2 checks the version of the locally installed certbot.
  export PHASE_1_VERSION="$LE_AUTO_VERSION"

  if [ ! -f "$VENV_BIN/letsencrypt" ]; then
    if ! OldVenvExists; then
      if [ "$HELP" = 1 ]; then
        echo "$USAGE"
        exit 0
      fi
      # If it looks like we've never bootstrapped before, bootstrap:
      Bootstrap
    fi
  fi
  if [ "$OS_PACKAGES_ONLY" = 1 ]; then
    say "OS packages installed."
    exit 0
  fi

  DeterminePythonVersion "NOCRASH"
  # Don't warn about file permissions if the user disabled the check or we
  # can't find an up-to-date Python.
  if [ "$PYVER" -ge "$MIN_PYVER" -a "$NO_PERMISSIONS_CHECK" != 1 ]; then
    # If the script fails for some reason, don't break certbot-auto.
    set +e
    # Suppress unexpected error output.
    CHECK_PERM_OUT=$(CheckPathPermissions "$LE_PYTHON" "$0" 2>/dev/null)
    CHECK_PERM_STATUS="$?"
    set -e
    # Only print output if the script ran successfully and it actually produced
    # output. The latter check resolves
    # https://github.com/certbot/certbot/issues/7012.
    if [ "$CHECK_PERM_STATUS" = 0 -a -n "$CHECK_PERM_OUT" ]; then
      error "$CHECK_PERM_OUT"
    fi
  fi

  if [ "$NO_SELF_UPGRADE" != 1 ]; then
    TEMP_DIR=$(TempDir)
    trap 'rm -rf "$TEMP_DIR"' EXIT
    # ---------------------------------------------------------------------------
    cat << "UNLIKELY_EOF" > "$TEMP_DIR/fetch.py"
"""Do downloading and JSON parsing without additional dependencies. ::

    # Print latest released version of LE to stdout:
    python fetch.py --latest-version

    # Download letsencrypt-auto script from git tag v1.2.3 into the folder I'm
    # in, and make sure its signature verifies:
    python fetch.py --le-auto-script v1.2.3

On failure, return non-zero.

"""

from __future__ import print_function, unicode_literals

from distutils.version import LooseVersion
from json import loads
from os import devnull, environ
from os.path import dirname, join
import re
import ssl
from subprocess import check_call, CalledProcessError
from sys import argv, exit
try:
    from urllib2 import build_opener, HTTPHandler, HTTPSHandler
    from urllib2 import HTTPError, URLError
except ImportError:
    from urllib.request import build_opener, HTTPHandler, HTTPSHandler
    from urllib.error import HTTPError, URLError

PUBLIC_KEY = environ.get('LE_AUTO_PUBLIC_KEY', """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA6MR8W/galdxnpGqBsYbq
OzQb2eyW15YFjDDEMI0ZOzt8f504obNs920lDnpPD2/KqgsfjOgw2K7xWDJIj/18
xUvWPk3LDkrnokNiRkA3KOx3W6fHycKL+zID7zy+xZYBuh2fLyQtWV1VGQ45iNRp
9+Zo7rH86cdfgkdnWTlNSHyTLW9NbXvyv/E12bppPcEvgCTAQXgnDVJ0/sqmeiij
n9tTFh03aM+R2V/21h8aTraAS24qiPCz6gkmYGC8yr6mglcnNoYbsLNYZ69zF1XH
cXPduCPdPdfLlzVlKK1/U7hkA28eG3BIAMh6uJYBRJTpiGgaGdPd7YekUB8S6cy+
CQIDAQAB
-----END PUBLIC KEY-----
""")

class ExpectedError(Exception):
    """A novice-readable exception that also carries the original exception for
    debugging"""


class HttpsGetter(object):
    def __init__(self):
        """Build an HTTPS opener."""
        # Based on pip 1.4.1's URLOpener
        # This verifies certs on only Python >=2.7.9, and when NO_CERT_VERIFY isn't set.
        if environ.get('NO_CERT_VERIFY') == '1' and hasattr(ssl, 'SSLContext'):
            self._opener = build_opener(HTTPSHandler(context=cert_none_context()))
        else:
            self._opener = build_opener(HTTPSHandler())
        # Strip out HTTPHandler to prevent MITM spoof:
        for handler in self._opener.handlers:
            if isinstance(handler, HTTPHandler):
                self._opener.handlers.remove(handler)

    def get(self, url):
        """Return the document contents pointed to by an HTTPS URL.

        If something goes wrong (404, timeout, etc.), raise ExpectedError.

        """
        try:
            # socket module docs say default timeout is None: that is, no
            # timeout
            return self._opener.open(url, timeout=30).read()
        except (HTTPError, IOError) as exc:
            raise ExpectedError("Couldn't download %s." % url, exc)


def write(contents, dir, filename):
    """Write something to a file in a certain directory."""
    with open(join(dir, filename), 'wb') as file:
        file.write(contents)


def latest_stable_version(get):
    """Return the latest stable release of letsencrypt."""
    metadata = loads(get(
        environ.get('LE_AUTO_JSON_URL',
                    'https://pypi.python.org/pypi/certbot/json')).decode('UTF-8'))
    # metadata['info']['version'] actually returns the latest of any kind of
    # release release, contrary to https://wiki.python.org/moin/PyPIJSON.
    # The regex is a sufficient regex for picking out prereleases for most
    # packages, LE included.
    return str(max(LooseVersion(r) for r
                   in metadata['releases'].keys()
                   if re.match('^[0-9.]+$', r)))


def verified_new_le_auto(get, tag, temp_dir):
    """Return the path to a verified, up-to-date letsencrypt-auto script.

    If the download's signature does not verify or something else goes wrong
    with the verification process, raise ExpectedError.

    """
    le_auto_dir = environ.get(
        'LE_AUTO_DIR_TEMPLATE',
        'https://raw.githubusercontent.com/certbot/certbot/%s/'
        'letsencrypt-auto-source/') % tag
    write(get(le_auto_dir + 'letsencrypt-auto'), temp_dir, 'letsencrypt-auto')
    write(get(le_auto_dir + 'letsencrypt-auto.sig'), temp_dir, 'letsencrypt-auto.sig')
    write(PUBLIC_KEY.encode('UTF-8'), temp_dir, 'public_key.pem')
    try:
        with open(devnull, 'w') as dev_null:
            check_call(['openssl', 'dgst', '-sha256', '-verify',
                        join(temp_dir, 'public_key.pem'),
                        '-signature',
                        join(temp_dir, 'letsencrypt-auto.sig'),
                        join(temp_dir, 'letsencrypt-auto')],
                       stdout=dev_null,
                       stderr=dev_null)
    except CalledProcessError as exc:
        raise ExpectedError("Couldn't verify signature of downloaded "
                            "certbot-auto.", exc)


def cert_none_context():
    """Create a SSLContext object to not check hostname."""
    # PROTOCOL_TLS isn't available before 2.7.13 but this code is for 2.7.9+, so use this.
    context = ssl.SSLContext(ssl.PROTOCOL_SSLv23)
    context.verify_mode = ssl.CERT_NONE
    return context


def main():
    get = HttpsGetter().get
    flag = argv[1]
    try:
        if flag == '--latest-version':
            print(latest_stable_version(get))
        elif flag == '--le-auto-script':
            tag = argv[2]
            verified_new_le_auto(get, tag, dirname(argv[0]))
    except ExpectedError as exc:
        print(exc.args[0], exc.args[1])
        return 1
    else:
        return 0


if __name__ == '__main__':
    exit(main())

UNLIKELY_EOF
    # ---------------------------------------------------------------------------
    if [ "$PYVER" -lt "$MIN_PYVER" ]; then
      error "WARNING: couldn't find Python $MIN_PYTHON_VERSION+ to check for updates."
    elif ! REMOTE_VERSION=`"$LE_PYTHON" "$TEMP_DIR/fetch.py" --latest-version` ; then
      error "WARNING: unable to check for updates."
    fi

    # If for any reason REMOTE_VERSION is not set, let's assume certbot-auto is up-to-date,
    # and do not go into the self-upgrading process.
    if [ -n "$REMOTE_VERSION" ]; then
      LE_VERSION_STATE=`CompareVersions "$LE_PYTHON" "$LE_AUTO_VERSION" "$REMOTE_VERSION"`

      if [ "$LE_VERSION_STATE" = "UNOFFICIAL" ]; then
        say "Unofficial certbot-auto version detected, self-upgrade is disabled: $LE_AUTO_VERSION"
      elif [ "$LE_VERSION_STATE" = "OUTDATED" ]; then
        say "Upgrading certbot-auto $LE_AUTO_VERSION to $REMOTE_VERSION..."

        # Now we drop into Python so we don't have to install even more
        # dependencies (curl, etc.), for better flow control, and for the option of
        # future Windows compatibility.
        "$LE_PYTHON" "$TEMP_DIR/fetch.py" --le-auto-script "v$REMOTE_VERSION"

        # Install new copy of certbot-auto.
        # TODO: Deal with quotes in pathnames.
        say "Replacing certbot-auto..."
        # Clone permissions with cp. chmod and chown don't have a --reference
        # option on macOS or BSD, and stat -c on Linux is stat -f on macOS and BSD:
        cp -p "$0" "$TEMP_DIR/letsencrypt-auto.permission-clone"
        cp "$TEMP_DIR/letsencrypt-auto" "$TEMP_DIR/letsencrypt-auto.permission-clone"
        # Using mv rather than cp leaves the old file descriptor pointing to the
        # original copy so the shell can continue to read it unmolested. mv across
        # filesystems is non-atomic, doing `rm dest, cp src dest, rm src`, but the
        # cp is unlikely to fail if the rm doesn't.
        mv -f "$TEMP_DIR/letsencrypt-auto.permission-clone" "$0"
      fi  # A newer version is available.
    fi
  fi  # Self-upgrading is allowed.

  RerunWithArgs --le-auto-phase2 "$@"
fi
