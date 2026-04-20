#!/bin/bash
# ============================================================
# 🔄 sync-fork.sh — Sync fork with upstream repository
# Usage: ./scripts/sync-fork.sh [--rebase]
#   --rebase : Also rebase current working branch onto main
# ============================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

REBASE_FLAG=false
if [[ "$1" == "--rebase" ]]; then
  REBASE_FLAG=true
fi

echo -e "${CYAN}🔄 Fork Sync — Starting...${NC}"
echo ""

# --- Step 1: Detect current state ---
CURRENT_BRANCH=$(git branch --show-current)
echo -e "${BLUE}📌 Current branch:${NC} $CURRENT_BRANCH"

# --- Step 2: Ensure upstream exists ---
if ! git remote | grep -q upstream; then
  echo -e "${YELLOW}⚠️  No 'upstream' remote found. Detecting parent repo...${NC}"
  
  REPO_SLUG=$(git remote get-url origin | sed -E 's#.*[:/]([^/]+/[^.]+)(\.git)?$#\1#')
  PARENT_INFO=$(curl -s "https://api.github.com/repos/$REPO_SLUG" | python3 -c "
import sys,json
d=json.load(sys.stdin)
p=d.get('parent',{})
if p:
    print(p['clone_url'])
else:
    print('')
" 2>/dev/null || echo "")

  if [[ -z "$PARENT_INFO" ]]; then
    echo -e "${RED}❌ Could not detect upstream. Please add manually:${NC}"
    echo "   git remote add upstream <upstream-url>"
    exit 1
  fi

  echo -e "${GREEN}✅ Found upstream:${NC} $PARENT_INFO"
  git remote add upstream "$PARENT_INFO"
fi

UPSTREAM_URL=$(git remote get-url upstream)
echo -e "${BLUE}🔗 Upstream:${NC} $UPSTREAM_URL"
echo ""

# --- Step 3: Fetch upstream ---
echo -e "${CYAN}📥 Fetching upstream...${NC}"
git fetch upstream
echo ""

# --- Step 4: Check if already in sync ---
LOCAL_MAIN=$(git rev-parse main 2>/dev/null || echo "none")
UPSTREAM_MAIN=$(git rev-parse upstream/main 2>/dev/null || echo "none")

if [[ "$LOCAL_MAIN" == "$UPSTREAM_MAIN" ]]; then
  echo -e "${GREEN}✅ Already in sync! Nothing to do.${NC}"
  echo ""
  echo -e "  upstream/main : $(git rev-parse --short upstream/main)"
  echo -e "  local main    : $(git rev-parse --short main)"
  echo -e "  origin/main   : $(git rev-parse --short origin/main)"
  exit 0
fi

# --- Step 5: Stash, switch, merge ---
echo -e "${CYAN}📦 Stashing uncommitted changes...${NC}"
STASH_RESULT=$(git stash --include-untracked -m "sync-fork-auto-stash" 2>&1 || true)
STASHED=false
if [[ "$STASH_RESULT" == *"Saved working directory"* ]]; then
  STASHED=true
  echo -e "${YELLOW}   Stashed changes${NC}"
else
  echo -e "   No changes to stash"
fi

echo -e "${CYAN}🔀 Merging upstream/main into main...${NC}"
git checkout main
if ! git merge upstream/main --no-edit; then
  echo ""
  echo -e "${RED}❌ Merge conflict detected!${NC}"
  echo -e "   Resolve conflicts manually, then run:"
  echo -e "   ${YELLOW}git add . && git commit${NC}"
  echo -e "   ${YELLOW}git push origin main${NC}"
  echo -e "   ${YELLOW}git checkout $CURRENT_BRANCH${NC}"
  exit 1
fi

# --- Step 6: Push to fork ---
echo -e "${CYAN}📤 Pushing to origin/main...${NC}"
git push origin main

# --- Step 7: Return to working branch ---
echo -e "${CYAN}🔙 Switching back to ${CURRENT_BRANCH}...${NC}"
git checkout "$CURRENT_BRANCH"

if [[ "$STASHED" == true ]]; then
  echo -e "${CYAN}📦 Restoring stashed changes...${NC}"
  git stash pop || echo -e "${YELLOW}⚠️  Could not auto-pop stash. Run: git stash pop${NC}"
fi

# --- Step 8: Optional rebase ---
if [[ "$REBASE_FLAG" == true ]]; then
  echo ""
  echo -e "${CYAN}🔄 Rebasing ${CURRENT_BRANCH} onto main...${NC}"
  if ! git rebase main; then
    echo -e "${RED}❌ Rebase conflict! Resolve manually:${NC}"
    echo -e "   ${YELLOW}git rebase --continue${NC}  (after resolving)"
    echo -e "   ${YELLOW}git rebase --abort${NC}     (to cancel)"
    exit 1
  fi
  echo -e "${GREEN}✅ Rebase complete${NC}"
fi

# --- Step 9: Final report ---
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  🔄 Fork Sync Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo ""

MAIN_HASH=$(git rev-parse --short main)
UPSTREAM_HASH=$(git rev-parse --short upstream/main)
ORIGIN_HASH=$(git rev-parse --short origin/main)

echo -e "  upstream/main : ${CYAN}$UPSTREAM_HASH${NC}"
echo -e "  local main    : ${CYAN}$MAIN_HASH${NC}"
echo -e "  origin/main   : ${CYAN}$ORIGIN_HASH${NC}"
echo ""

if [[ "$MAIN_HASH" == "$UPSTREAM_HASH" ]] && [[ "$MAIN_HASH" == "$ORIGIN_HASH" ]]; then
  echo -e "  ${GREEN}✅ All branches in sync!${NC}"
else
  echo -e "  ${YELLOW}⚠️  Branches may be out of sync${NC}"
fi

echo ""
echo -e "  Current branch: ${BLUE}$(git branch --show-current)${NC}"
echo ""
echo -e "  Latest upstream commits:"
git log --oneline -3 upstream/main | sed 's/^/    /'
echo ""
