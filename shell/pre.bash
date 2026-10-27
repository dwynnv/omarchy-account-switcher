# account-switcher, sourced from ~/.bashrc after its non-interactive return and before Omarchy's
# rc: the terminal's mode picks its git/gh accounts, AWS files, history, z jumps and link
# opener. The switcher's launchers set ACCOUNT_SWITCHER_MODE; anything else is Work.
source "${BASH_SOURCE[0]%/shell/*}/lib/mode.bash"
dm_env "${ACCOUNT_SWITCHER_MODE:-work}"
# The starship prompt shows one of these (one module per mode, each with its colour).
if [[ $ACCOUNT_SWITCHER_MODE == personal ]]; then
  export ACCOUNT_SWITCHER_PERSONAL=1
  unset ACCOUNT_SWITCHER_WORK
else
  export ACCOUNT_SWITCHER_WORK=1
  unset ACCOUNT_SWITCHER_PERSONAL
fi
