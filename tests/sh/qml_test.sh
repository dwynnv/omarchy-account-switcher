#!/usr/bin/env bash
# The setup window's QML: it lints, it's reachable over IPC, and it uses Commons.Color (a bare
# Color. is undefined in the Omarchy shell since Qt 6.12).
cd "$(dirname "$0")" || exit 1
source ./t.bash
PLUGIN=$(cd ../.. && pwd)
QMLLINT=/usr/lib/qt6/bin/qmllint

t_window() {
  t_ok test -f "$PLUGIN/AppsWindow.qml"
  # The Omarchy shell's own modules (qs.Commons, qs.Ui) on the import path; what's left besides
  # unqualified access in delegates and Style's untyped members is a real problem.
  local q=${TEST_TMPDIR:?run through tests/run.sh}/qs-import f
  mkdir -p "$q/qs"
  for f in Commons Ui services; do ln -sfn "/usr/share/omarchy/shell/$f" "$q/qs/$f"; done
  for f in AppsWindow Panel; do
    t_eq "$(cd "$q" && "$QMLLINT" -I "$q" "$PLUGIN/$f.qml" 2>&1 | grep '^Warning' | grep -v '\[unqualified\]' |
      grep -vc 'not found on type "QObject"')" 0 "$f.qml lints"
  done
  t_ok grep -qF 'target: "account-switcher.apps"' "$PLUGIN/Service.qml"
  t_eq "$(grep -cE '(^|[^.A-Za-z])Color\.' "$PLUGIN/AppsWindow.qml" "$PLUGIN/Panel.qml" | awk -F: '{s += $2} END {print s}')" 0
}
t_test "the setup window lints, opens over IPC and uses Commons.Color" t_window

t_done
