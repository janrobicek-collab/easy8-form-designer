#!/bin/bash
# Copy the git-tracked engine + frontend from the Windows repo into the WSL
# native filesystem.
#
# NOT symlinks: Rails scans these paths constantly, and every stat/read over
# the /mnt/c 9p mount costs milliseconds — enough to stall `easy8:setup` for
# 20+ minutes (blocked in p9_client_rpc). Copying is instant; re-run after edits.
set -euo pipefail
REPO="/mnt/c/Users/jrob/.claude/projects/easy8-form-designer/repo"
APP="/root/easy8"

rm -rf "$APP/easy_engines/easy_form_designer"
cp -a "$REPO/easy_form_designer" "$APP/easy_engines/easy_form_designer"

rm -rf "$APP/app/frontend/src/easy_form_designer"
cp -a "$REPO/frontend/easy_form_designer" "$APP/app/frontend/src/easy_form_designer"

rm -f "$APP/app/frontend/entrypoints/easy_form_designer.ts"
cp -a "$REPO/frontend/entrypoints/easy_form_designer.ts" "$APP/app/frontend/entrypoints/easy_form_designer.ts"

echo "synced:"
echo "  engine   $(find "$APP/easy_engines/easy_form_designer" -type f | wc -l) files"
echo "  frontend $(find "$APP/app/frontend/src/easy_form_designer" -type f | wc -l) files"
