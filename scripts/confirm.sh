#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Confirmation gate for destructive / irreversible platform operations
#
# Usage:
#   bash scripts/confirm.sh "<phrase>" ["<warning line>" ...]
#
# The caller is only allowed to proceed when the exact <phrase> is supplied,
# either by a human typing it at the terminal or via CONFIRM=<phrase>.
#
# Why the phrase is operation-specific rather than a generic "yes":
#   This platform is driven by AI agents through the .claude/commands/*
#   wizards. A generic CONFIRM=yes is trivially satisfiable by anything that
#   has read the Makefile, which makes the gate decorative. Requiring the
#   literal target ("destroy my-app-prod") means the bypass cannot be
#   produced without deliberately naming the thing being destroyed.
#
#   Agents must never set CONFIRM on the user's behalf — see CLAUDE.md,
#   "Blast radius and confirmation gates".
# =============================================================================

RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PHRASE="${1:?confirm.sh: missing confirmation phrase}"
shift || true

echo ""
for line in "$@"; do
  echo -e "${YELLOW}${BOLD}!! ${line}${NC}"
done
echo ""

# --- Non-interactive path -----------------------------------------------------
if [ -n "${CONFIRM:-}" ]; then
  if [ "$CONFIRM" = "$PHRASE" ]; then
    echo -e "${YELLOW}Confirmation supplied non-interactively (CONFIRM='${PHRASE}').${NC}"
    echo -e "${YELLOW}No human reviewed this at a terminal.${NC}"
    echo ""
    exit 0
  fi
  echo -e "${RED}CONFIRM is set but does not match.${NC}"
  echo -e "  expected: ${BOLD}${PHRASE}${NC}"
  echo -e "  received: ${BOLD}${CONFIRM}${NC}"
  echo ""
  exit 1
fi

# --- Interactive path ---------------------------------------------------------
if [ ! -r /dev/tty ]; then
  echo -e "${RED}Refusing to continue: no terminal available to confirm on.${NC}"
  echo -e "Re-run from an interactive shell, or pass the exact phrase:"
  echo -e "  ${BOLD}CONFIRM='${PHRASE}' <your command>${NC}"
  echo ""
  exit 1
fi

echo -ne "Type ${BOLD}'${PHRASE}'${NC} to continue (anything else aborts): "
read -r answer < /dev/tty || answer=""

if [ "$answer" != "$PHRASE" ]; then
  echo -e "${RED}Aborted — confirmation phrase did not match.${NC}"
  echo ""
  exit 1
fi

echo ""
