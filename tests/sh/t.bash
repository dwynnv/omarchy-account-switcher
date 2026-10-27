# Tiny test harness for bash, sourced by tests/sh/*_test.sh. Each test runs in a
# subshell, so environment changes don't leak; t_eq/t_ok end that subshell on failure.
T_FAILED=0

t_test() {
  local name=$1 out status
  shift
  out=$("$@" 2>&1)
  status=$?
  if ((status == 0)); then
    echo "ok   $name"
  else
    T_FAILED=$((T_FAILED + 1))
    echo "FAIL $name: $out"
  fi
}

t_eq() {
  [[ "$1" == "$2" ]] && return 0
  printf 'expected %q, got %q%s\n' "$2" "$1" "${3:+ ($3)}"
  exit 1
}

t_ok() {
  "$@" && return 0
  echo "failed: $*"
  exit 1
}

# No line of FILE matches PATTERN.
t_none() {
  ! grep -q -- "$1" "$2" && return 0
  echo "unexpected: $(grep -- "$1" "$2" | head -n3)"
  exit 1
}

t_done() {
  if ((T_FAILED > 0)); then
    printf '\n%d failed\n' "$T_FAILED"
    exit 1
  fi
  printf '\nall passed\n'
  exit 0
}
