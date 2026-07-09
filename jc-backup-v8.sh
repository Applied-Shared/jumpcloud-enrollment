#!/bin/bash
#
# JumpCloud Pre-Enrollment Script — V8
#
# This script is interactive and must be downloaded before running.
# Do NOT pipe it directly from curl (curl | bash will break the prompts).
#
# Paste this single line into your terminal to download and run:
#
#   curl -fsSL "https://raw.githubusercontent.com/Applied-Shared/jumpcloud-enrollment/refs/heads/main/jc-backup-v8.sh" -o jc-backup.sh && chmod +x jc-backup.sh && ./jc-backup.sh

# ─── Helpers ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

header()  { echo ""; echo -e "${CYAN}${BOLD}=== $1 ===${NC}"; echo ""; }
success() { echo -e "${GREEN}✓${NC}  $1"; }
warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }

confirm() {
    local prompt="$1" default="${2:-y}" response
    [[ "$default" == "y" ]] && read -rp "$prompt [Y/n]: " response || read -rp "$prompt [y/N]: " response
    response="${response:-$default}"
    [[ "${response,,}" == "y" ]]
}

BACKED_UP=()
WARNINGS=()
SKIPPED=()

# ─── Dependency check ─────────────────────────────────────────────────────────

MISSING_DEPS=()
for cmd in curl git; do
    command -v "$cmd" &>/dev/null || MISSING_DEPS+=("$cmd")
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo "The following required tools are not installed: ${MISSING_DEPS[*]}"
    echo ""
    if confirm "Install them now via apt-get?"; then
        sudo apt-get update -qq && sudo apt-get install -y "${MISSING_DEPS[@]}" || {
            echo -e "${RED}Failed to install dependencies. Install manually and re-run:${NC}"
            echo "  sudo apt-get install ${MISSING_DEPS[*]}"
            exit 1
        }
        success "Dependencies installed: ${MISSING_DEPS[*]}"
    else
        echo "Install the missing tools and re-run the script."
        exit 1
    fi
fi

# ─── Intro ────────────────────────────────────────────────────────────────────

clear
header "JumpCloud Pre-Enrollment Backup"

cat <<EOF
This script walks you through backing up what you need before enrolling your
device in JumpCloud.

What you need to know:
  • The JumpCloud agent does not delete your files, but it takes over
    account management on your device.
  • IT does not have access to your personal files and cannot recover
    them on your behalf.
  • You don't need to back up everything — just what you'd need to get
    your next weekly task done.

EOF

warn "If your local username matches your JumpCloud/Okta username, JumpCloud"
echo "    will automatically take over your existing local account and replace"
echo "    your local password with your Okta password. This is expected"
echo "    behaviour — but it can be disorienting if you're not prepared."
echo ""
read -rp "Press Enter to continue (Ctrl+C to cancel)..."

# ─── Phase 1: Account setup ───────────────────────────────────────────────────

header "Phase 1 — Set Up Your JumpCloud Account"

echo "Complete these steps before the backup. You'll need the JumpCloud portal"
echo "open in a browser: https://console.jumpcloud.com"
echo ""
read -rp "Press Enter when you're ready..."

# Step 1 — Log in
header "Phase 1, Step 1 — Log In and Verify Your Account"

cat <<EOF
  1. Go to https://console.jumpcloud.com and log in
  2. Confirm your username and password match your Okta credentials

EOF

warn "JumpCloud syncs from Okta but does not authenticate through it."
echo "    Okta is always the source of truth — if you need to reset your"
echo "    password, do it in Okta, not JumpCloud."
echo ""

until confirm "Have you logged in and verified your credentials?"; do
    echo "  Take your time — complete this step before continuing."
    echo ""
done
success "Account login verified."

# Step 2 — MFA
header "Phase 1, Step 2 — Enable MFA"

cat <<EOF
  1. In the JumpCloud portal, go to Security → Multi-Factor Authentication
  2. Click Enroll a device and install JumpCloud Protect on your phone
     for push notification MFA

     Alternatively, you can enroll an existing authenticator app
     (Google Authenticator or Okta Verify) — push notifications are
     not available with this option.

EOF

until confirm "Have you enrolled an MFA device?"; do
    echo "  MFA is required — complete this step before continuing."
    echo ""
done
success "MFA enrolled."

# Step 3 — SSH key (developers only)
header "Phase 1, Step 3 — Add Your SSH Key (Developers Only)"

cat <<EOF
  If you SSH from another machine (e.g. your MacBook) into this device,
  add your public SSH key to JumpCloud so it carries over after enrollment.

EOF

if confirm "Are you a developer who SSHs into this machine?"; then
    cat <<EOF
  1. In the JumpCloud portal, go to Security → SSH Keys
  2. Add the public key from the machine you SSH from
     (most commonly your MacBook's ~/.ssh/id_rsa.pub or ~/.ssh/id_ed25519.pub)

EOF
    until confirm "Have you added your SSH key?"; do
        echo "  Complete this step or skip it if it doesn't apply."
        echo ""
    done
    success "SSH key added."
else
    echo "  Skipping — not applicable."
fi

# ─── Phase 2: Backup ──────────────────────────────────────────────────────────

header "Phase 2 — Back Up Your Data"

echo "Now let's back up what you need before running the JumpCloud installer."
echo ""
read -rp "Press Enter to continue..."

# ─── Step 1: Backup destination ───────────────────────────────────────────────

header "Step 1 — Backup Destination"

DEFAULT_DIR="$HOME/jc-backup-$(date +%Y%m%d-%H%M%S)"
echo "Where would you like to save your backup?"
echo "Default: $DEFAULT_DIR"
echo ""
read -rp "Enter path (or press Enter for default): " BACKUP_DIR
BACKUP_DIR="${BACKUP_DIR:-$DEFAULT_DIR}"
BACKUP_DIR="${BACKUP_DIR/#\~/$HOME}"

mkdir -p "$BACKUP_DIR" || { echo -e "${RED}Could not create $BACKUP_DIR — check the path and try again.${NC}"; exit 1; }
success "Backup directory: $BACKUP_DIR"

# ─── Step 2: Username check ───────────────────────────────────────────────────

header "Step 2 — Username Check"

LOCAL_USER="$(whoami)"
echo -e "Your local username is: ${BOLD}${LOCAL_USER}${NC}"
echo ""
echo "What is your JumpCloud/Okta username? (visible at console.jumpcloud.com)"
echo ""
read -rp "JumpCloud username: " JC_USERNAME

echo ""
if [[ "${LOCAL_USER,,}" == "${JC_USERNAME,,}" ]]; then
    warn "Your local username matches your JumpCloud username (Scenario B)."
    echo ""
    echo "    When IT binds your device, JumpCloud will take over your existing"
    echo "    local account — your Okta password replaces your local password."
    echo "    Your files stay intact, but some tools referencing your home"
    echo "    directory path may need to be re-pointed afterward."
    echo ""
    echo "    Post in #temp-jumpcloud-adoption before the binding happens if you"
    echo "    want IT to rename your local account first to avoid this."
    echo ""
    WARNINGS+=("Local username matches JumpCloud username — read the Scenario B note in the setup guide.")
    read -rp "Press Enter to continue..."
else
    success "Local username does not match your JumpCloud username. JumpCloud will create a fresh account — your existing local account is untouched."
fi

# ─── Step 3: SSH keys ─────────────────────────────────────────────────────────

header "Step 3 — SSH Keys"

if [[ -d "$HOME/.ssh" ]]; then
    KEY_COUNT=$(find "$HOME/.ssh" -type f ! -name "*.pub" ! -name "known_hosts" ! -name "config" | wc -l)
    echo "Found ~/.ssh with $KEY_COUNT private key(s)."
    echo "Back up any keys you can't easily regenerate — Ansible keys, deploy keys, etc."
    echo ""
    if confirm "Back up ~/.ssh?"; then
        cp -r "$HOME/.ssh" "$BACKUP_DIR/.ssh"
        chmod 700 "$BACKUP_DIR/.ssh"
        find "$BACKUP_DIR/.ssh" -type f ! -name "*.pub" ! -name "known_hosts" -exec chmod 600 {} \; 2>/dev/null || true
        success "SSH keys backed up → $BACKUP_DIR/.ssh"
        success "Permissions: directory 700, private keys 600"
        BACKED_UP+=("SSH keys (~/.ssh)")
    else
        SKIPPED+=("SSH keys")
    fi
else
    echo "No ~/.ssh directory found — skipping."
fi

# ─── Step 4: Git repositories ─────────────────────────────────────────────────

header "Step 4 — Git Repositories"

echo "Scanning for git repositories in your home directory..."
echo ""

REPOS=()
while IFS= read -r -d '' gitdir; do
    repo="${gitdir%/.git}"
    [[ "$repo" == "$BACKUP_DIR"* ]] && continue
    REPOS+=("$repo")
done < <(find "$HOME" -maxdepth 6 -name ".git" -not -path "$BACKUP_DIR/*" -print0 2>/dev/null)

if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo "No git repositories found."
else
    echo "Found ${#REPOS[@]} repositor$([ ${#REPOS[@]} -eq 1 ] && echo 'y' || echo 'ies'):"
    echo ""

    DIRTY_REPOS=()
    for repo in "${REPOS[@]}"; do
        uncommitted=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l)
        unpushed=$(git -C "$repo" log @{u}.. --oneline 2>/dev/null | wc -l)
        short="${repo/#$HOME/~}"

        parts=()
        [[ "$uncommitted" -gt 0 ]] && parts+=("$uncommitted uncommitted")
        [[ "$unpushed" -gt 0 ]]    && parts+=("$unpushed unpushed")

        if [[ ${#parts[@]} -gt 0 ]]; then
            label=$(IFS=', '; echo "${parts[*]}")
            warn "$short — $label"
            DIRTY_REPOS+=("$short")
        else
            success "$short — clean"
        fi
    done

    echo ""

    if [[ ${#DIRTY_REPOS[@]} -gt 0 ]]; then
        echo ""
        warn "${#DIRTY_REPOS[@]} repositor$([ ${#DIRTY_REPOS[@]} -eq 1 ] && echo 'y has' || echo 'ies have') uncommitted or unpushed work."
        echo ""
        echo "    Commit and push before enrolling. If a branch only exists locally,"
        echo "    push it to a remote first."
        echo ""
        WARNINGS+=("Uncommitted/unpushed work in: ${DIRTY_REPOS[*]}")

        if ! confirm "Have you committed and pushed everything you need?" n; then
            echo ""
            echo "Take care of your git repos, then re-run this script."
            exit 0
        fi
    else
        echo ""
        success "All repositories are clean."
    fi
fi

# ─── Step 5: Dotfiles ─────────────────────────────────────────────────────────

header "Step 5 — Dotfiles and Tool Configs"

DOTFILES=()
for f in .bashrc .zshrc .gitconfig .profile .bash_profile .bash_aliases; do
    [[ -f "$HOME/$f" ]] && DOTFILES+=("$f")
done
CONFIG_EXISTS=false
[[ -d "$HOME/.config" ]] && CONFIG_EXISTS=true

if [[ ${#DOTFILES[@]} -gt 0 ]] || $CONFIG_EXISTS; then
    echo "Found:"
    for f in "${DOTFILES[@]}"; do echo "  $f"; done
    $CONFIG_EXISTS && echo "  .config/"
    echo ""

    if confirm "Back up dotfiles and ~/.config?"; then
        DOTFILE_DIR="$BACKUP_DIR/dotfiles"
        mkdir -p "$DOTFILE_DIR"
        for f in "${DOTFILES[@]}"; do cp "$HOME/$f" "$DOTFILE_DIR/"; done
        $CONFIG_EXISTS && cp -r "$HOME/.config" "$DOTFILE_DIR/.config"
        success "Dotfiles backed up → $DOTFILE_DIR"
        BACKED_UP+=("Dotfiles (${DOTFILES[*]}${CONFIG_EXISTS:+ .config/})")
    else
        SKIPPED+=("Dotfiles")
    fi
else
    echo "No common dotfiles found — skipping."
fi

# ─── Step 6: Documents, Desktop, Downloads ────────────────────────────────────

header "Step 6 — Documents, Desktop, Downloads"

cat <<EOF
These folders can be large and are best copied to an external drive or cloud
storage rather than to a local folder. This script will not copy them.

EOF

for dir in Documents Desktop Downloads; do
    [[ -d "$HOME/$dir" ]] && echo "  ~/$dir — $(du -sh "$HOME/$dir" 2>/dev/null | cut -f1)"
done
echo ""

if confirm "Have you copied Documents, Desktop, and Downloads to an external drive or cloud storage?" n; then
    success "Confirmed."
    BACKED_UP+=("Documents/Desktop/Downloads (confirmed by you)")
else
    warn "Remember to back these up before enrolling — IT cannot recover them."
    WARNINGS+=("Documents/Desktop/Downloads not confirmed backed up.")
fi

# ─── Phase 2, Step 2: Generate install command ────────────────────────────────

header "Phase 2, Step 2 — Generate the Install Command"

cat <<EOF
  1. Go to https://console.jumpcloud.com and sign in with your Okta credentials
  2. Go to Security → Device Enrollment → Linux
  3. Click Generate Command and copy the full one-liner

EOF

warn "The token is only valid for 1 hour — generate it right before running the installer."
echo ""
read -rp "Press Enter once you have the command copied..."
echo ""
echo "Paste your connect key or the full curl command below."
echo "(The key looks like: jcc_eyJ... or a long hex string)"
echo ""
read -rp "Connect key or command: " CONNECT_KEY_INPUT

# Extract key from full curl command if pasted
if [[ "$CONNECT_KEY_INPUT" == *"x-connect-key"* ]]; then
    CONNECT_KEY_INPUT=$(echo "$CONNECT_KEY_INPUT" | grep -oP "x-connect-key: ['\"]?\K[^'\" ]+")
fi

if [[ -z "$CONNECT_KEY_INPUT" ]]; then
    echo "No key found — exiting. Re-run the script and paste your key when prompted."
    exit 1
fi

success "Connect key captured."

# ─── Phase 2, Step 3: Run installer ──────────────────────────────────────────

header "Phase 2, Step 3 — Run the Installer"

echo "The installer will now run. You will be prompted for your sudo password."
echo ""

if confirm "Run the JumpCloud installer now?"; then
    echo ""
    KICKSTART_TMP=$(mktemp)
    curl --tlsv1.2 --silent --show-error \
         --header "x-connect-key: ${CONNECT_KEY_INPUT}" \
         https://kickstart.jumpcloud.com/Kickstart -o "$KICKSTART_TMP" || {
        echo ""
        echo -e "${RED}Failed to download the installer. Check your internet connection and try again.${NC}"
        rm -f "$KICKSTART_TMP"
        exit 1
    }
    sudo bash "$KICKSTART_TMP"
    INSTALL_EXIT=$?
    rm -f "$KICKSTART_TMP"

    echo ""
    if [[ $INSTALL_EXIT -ne 0 ]]; then
        echo -e "${RED}Installer exited with status $INSTALL_EXIT.${NC}"
        echo "Copy the output above and post it in #temp-jumpcloud-adoption."
        exit $INSTALL_EXIT
    fi

    success "Installer completed."
    echo ""
    warn "The installer creates system services and registers the device."
    echo "    Your IT admin receives an automatic email notification when your"
    echo "    device comes online."
fi

# ─── Phase 2, Step 4: Verify agent ───────────────────────────────────────────

header "Phase 2, Step 4 — Verify the Agent is Running"

echo "Waiting for the agent to start..."
sleep 5
echo ""

echo -e "${BOLD}Service status:${NC}"
sudo systemctl status jcagent 2>/dev/null || sudo systemctl status jcp 2>/dev/null || echo "Service not found yet."
echo ""

echo -e "${BOLD}Process check:${NC}"
ps aux | grep -E 'jumpcloud|jcp' | grep -v grep || echo "No JumpCloud processes visible yet."
echo ""

if ! confirm "Is the agent showing as active/running?" n; then
    echo ""
    echo "Pulling logs — copy the output below and include it in #temp-jumpcloud-adoption:"
    echo ""
    sudo journalctl -u jumpcloud -n 200 --no-pager 2>/dev/null \
        || sudo journalctl -u jcp -n 200 --no-pager 2>/dev/null \
        || true
    echo ""
    WARNINGS+=("Agent not confirmed running — logs pulled above.")
else
    success "Agent is running."
    BACKED_UP+=("JumpCloud agent installed and verified")
fi

# ─── Phase 2, Step 5: Let IT know ────────────────────────────────────────────

header "Phase 2, Step 5 — Let IT Know You're Ready"

DEVICE_HOSTNAME=$(hostname)

echo "Post the following in #temp-jumpcloud-adoption:"
echo ""
echo -e "  ${BOLD}Hostname:${NC}   $DEVICE_HOSTNAME"
echo -e "  ${BOLD}Asset Tag:${NC}  (silver sticker on device, format A####)"
echo "              If you don't have one, IT will assign one."
echo ""
echo "IT will bind your device to your account and confirm when done."
echo "Do not sign out of your current account until you receive confirmation."
echo ""

warn "Read before IT binds your device:"
echo ""
echo -e "  ${GREEN}Scenario A${NC} — your local username does NOT match your JumpCloud username"
echo "  (Most common for firstname.lastname@applied.co accounts)"
echo "  JumpCloud creates a fresh account. Your existing local account is untouched."
echo "  You'll log in going forward using your Okta credentials."
echo ""
echo -e "  ${YELLOW}Scenario B${NC} — your local username MATCHES your JumpCloud username"
echo "  (Affects firstname@applied.co accounts)"
echo "  JumpCloud takes over your existing local account. Your Okta password"
echo "  replaces your local password. Files stay intact."
echo "  You may see a GID issue after login — fix it with:"
echo ""
echo "    id username"
echo "    sudo usermod -g XXXX username"
echo "    sudo chown -R username:username /home/username"
echo ""
echo "  Not sure which applies to you? Post in #temp-jumpcloud-adoption before"
echo "  the binding — IT can check and rename your local account first if needed."
echo ""

until confirm "Have you posted in #temp-jumpcloud-adoption?"; do
    echo "  Post the hostname and asset tag above, then confirm here."
    echo ""
done
success "IT notified."

# ─── Phase 2, Step 6: Sign in ─────────────────────────────────────────────────

header "Phase 2, Step 6 — Sign In to Your New Account"

cat <<EOF
Once IT confirms the binding is complete:
  1. Sign out of your current account
  2. Sign back in using your Okta credentials
  3. Verify your files and applications are accessible

Do not sign out until IT confirms.
EOF
echo ""
read -rp "Press Enter to continue to the optional migration section..."

# ─── Optional: Migration ──────────────────────────────────────────────────────

header "Optional — Migrate Files to Your New Account"

echo "If IT created a new account for you (Scenario A) and you need to pull"
echo "files across from your old local account, this section will do that."
echo "Skip it if your existing account was taken over (Scenario B)."
echo ""

if confirm "Do you need to migrate files from an old local account?" n; then
    echo ""
    read -rp "Old local username (the account you're migrating FROM): " OLD_USER
    read -rp "New local username (the JumpCloud account you're migrating TO): " NEW_USER

    if [[ -z "$OLD_USER" || -z "$NEW_USER" ]]; then
        echo "Both usernames are required — skipping migration."
    elif [[ ! -d "/home/$OLD_USER" ]]; then
        echo -e "${RED}No home directory found for '$OLD_USER' at /home/$OLD_USER.${NC}"
        echo "Check the username and re-run the script if needed."
    elif [[ ! -d "/home/$NEW_USER" ]]; then
        echo -e "${RED}No home directory found for '$NEW_USER' at /home/$NEW_USER.${NC}"
        echo "Make sure you've logged into the new account at least once before migrating."
    else
        echo ""
        echo "This will copy files from /home/$OLD_USER to /home/$NEW_USER."
        warn "AppData-equivalent directories are excluded — applications will regenerate them on first launch."
        echo ""

        if confirm "Run the migration now?"; then
            sudo mkdir -p "/home/$NEW_USER"
            sudo chown "$NEW_USER:$(id -gn "$NEW_USER" 2>/dev/null || echo "$NEW_USER")" "/home/$NEW_USER"
            sudo rsync -aHAX --numeric-ids --progress "/home/$OLD_USER/" "/home/$NEW_USER/"
            sudo chown -R "$NEW_USER:$(id -gn "$NEW_USER" 2>/dev/null || echo "$NEW_USER")" "/home/$NEW_USER"

            # SELinux restorecon if available
            if command -v restorecon &>/dev/null; then
                sudo restorecon -R -v "/home/$NEW_USER"
            fi

            echo ""
            success "Migration complete."
            echo ""
            echo "Verify the following before signing into your new account:"
            echo ""

            [[ -f "/home/$NEW_USER/.bashrc" ]]   && success ".bashrc present"   || warn ".bashrc not found"
            [[ -f "/home/$NEW_USER/.zshrc" ]]    && success ".zshrc present"    || warn ".zshrc not found"
            [[ -f "/home/$NEW_USER/.gitconfig" ]] && success ".gitconfig present" || warn ".gitconfig not found"
            [[ -d "/home/$NEW_USER/.ssh" ]]      && success ".ssh present"      || warn ".ssh not found"

            echo ""
            warn "Your old profile at /home/$OLD_USER will be removed within 1-2 weeks. Use that window to retrieve anything you missed."
        fi
    fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────────

header "Summary"

if [[ ${#BACKED_UP[@]} -gt 0 ]]; then
    echo -e "${GREEN}${BOLD}Completed:${NC}"
    for item in "${BACKED_UP[@]}"; do success "$item"; done
    echo ""
fi

if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo -e "${BOLD}Skipped:${NC}"
    for item in "${SKIPPED[@]}"; do echo "  - $item"; done
    echo ""
fi

if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo -e "${YELLOW}${BOLD}Warnings:${NC}"
    for item in "${WARNINGS[@]}"; do warn "$item"; done
    echo ""
fi

echo "Backup location: $BACKUP_DIR"
echo ""
echo "Enrollment is complete. IT will confirm when your device is bound."
echo "Post in #temp-jumpcloud-adoption if you run into anything."
echo ""
