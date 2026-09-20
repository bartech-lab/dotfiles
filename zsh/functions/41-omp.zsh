# omp runs against the local bonsai-2-27b model only, so its 200K window is the
# scarce resource. By default omp ships 11 tool schemas plus the xd:// device
# docs on every request.
#
# Measured 2026-09-20 on the Mac (PI_REQ_DEBUG capture, counted with the model
# server's own tokenizer):
#   default             26,033 tokens  13.0% of 200K
#   list below          21,490 tokens  10.7% of 200K
#
# Dropped:
#   eval   persistent Python/Bun kernel and the browser automation API.
#          `task` already fans out natively, so workpool() is not needed.
#   todo   session task list. Bookkeeping only; plan mode rides `write`.
#   debug  DAP client. Its adapters are gdb, lldb-dap, debugpy, dlv, rdbg —
#          none installed on either machine, and no dap.json exists. Add it
#          back when a JS adapter is configured.
#
# Kept deliberately:
#   hub    `task` depends on it for `hub cancel` on a hung worker, `hub jobs`
#          snapshots, and sibling coordination before same-file edits.
#   lsp, ast_edit          worth their 1,620 tokens on a large codebase.
#   retain/recall/reflect/memory_edit   the Mnemopi memory suite, 986 tokens.
OMP_TOOLS="read,bash,edit,write,grep,glob,task,web_search,lsp,ast_edit,retain,recall,reflect,memory_edit,hub"

omp() {
  command omp --tools="$OMP_TOOLS" "$@"
}
