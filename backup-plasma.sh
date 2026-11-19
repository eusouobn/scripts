#!/usr/bin/env bash
#
# backup-plasma.sh — Backup automatizado do KDE Plasma 6
# Uso: ./backup-plasma.sh [--encrypt]
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${BLUE}[*]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }

ENCRYPT=false
for arg in "$@"; do
    case "$arg" in
        --encrypt) ENCRYPT=true ;;
        -h|--help)
            echo "Uso: $0 [--encrypt]"
            echo "  --encrypt   Criptografa os tarballs com GPG (AES256)"
            exit 0 ;;
        *) err "Argumento desconhecido: $arg"; exit 1 ;;
    esac
done

if [ "$EUID" -eq 0 ]; then
    err "Não execute como root. Rode como seu usuário normal."
    exit 1
fi

echo -e "${BOLD}==========================================${NC}"
echo -e "${BOLD}   Backup do KDE Plasma 6${NC}"
echo -e "${BOLD}==========================================${NC}"
echo

log "Verificando dependências..."
for cmd in plasmasafe pacman tar; do
    command -v "$cmd" &>/dev/null || { err "$cmd não encontrado."; exit 1; }
done
[ "$ENCRYPT" = true ] && ! command -v gpg &>/dev/null && { err "gpg não encontrado."; exit 1; }
ok "Dependências OK"

if pgrep -x plasmashell &>/dev/null; then
    warn "plasmashell está em execução. O estado do painel pode não estar 100% atualizado."
    warn "Recomendado: fazer logout e rodar em um TTY (Ctrl+Alt+F3)."
    read -rp "Continuar mesmo assim? [s/N] " ans
    [[ "$ans" =~ ^[sS]$ ]] || { err "Abortado."; exit 1; }
fi

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="$HOME/plasma-backup-$TIMESTAMP"
SNAPSHOT_NAME="backup-$TIMESTAMP"

log "Diretório de backup: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
ok "Diretório criado"

log "Verificando efeitos de zoom..."
ZOOM=false
if grep -qi -E 'zoom|magnif' ~/.config/kwinrc 2>/dev/null; then
    warn "Efeito de zoom encontrado no kwinrc."
    ZOOM=true
fi
if grep -qi 'zoom' ~/.config/kaccessrc 2>/dev/null; then
    warn "Zoom de acessibilidade encontrado no kaccessrc."
    ZOOM=true
fi
[ "$ZOOM" = false ] && ok "Nenhum zoom ativo detectado"

log "Criando snapshot com perfil 'desktop' (sem splash screen)..."
plasmasafe save "$SNAPSHOT_NAME" --profile desktop
ok "Snapshot criado: $SNAPSHOT_NAME"

log "Exportando snapshot..."
plasmasafe export "$SNAPSHOT_NAME" "$BACKUP_DIR/backup-plasma-arch.tar.gz"
ok "Exportado: backup-plasma-arch.tar.gz"

log "Verificando se ksplashrc ficou fora do backup..."
if tar -tzf "$BACKUP_DIR/backup-plasma-arch.tar.gz" | grep -qi ksplash; then
    warn "ATENÇÃO: ksplashrc foi incluído no backup!"
else
    ok "ksplashrc confirmadamente ausente"
fi

log "Empacotando extras (fontes, favoritos do Dolphin, Spectacle, etc.)..."
EXTRAS_REL=(
    ".local/share/fonts"
    ".local/share/color-schemes"
    ".local/share/wallpapers"
    ".local/share/user-places.xbel"
    ".config/fontconfig"
    ".config/gtk-3.0"
    ".config/gtk-4.0"
    ".config/spectaclerc"
)
EXTRAS_FOUND=()
for p in "${EXTRAS_REL[@]}"; do
    [ -e "$HOME/$p" ] && EXTRAS_FOUND+=("$p")
done
if [ ${#EXTRAS_FOUND[@]} -gt 0 ]; then
    tar -czf "$BACKUP_DIR/backup-plasma-extras.tar.gz" -C "$HOME" "${EXTRAS_FOUND[@]}"
    ok "Extras salvos (${#EXTRAS_FOUND[@]} itens)"
else
    warn "Nenhum extra encontrado"
fi

log "Gerando listas de pacotes..."
pacman -Qqen > "$BACKUP_DIR/pkglist-oficial.txt"
pacman -Qqem > "$BACKUP_DIR/pkglist-aur.txt"
NAT=$(wc -l < "$BACKUP_DIR/pkglist-oficial.txt")
AUR=$(wc -l < "$BACKUP_DIR/pkglist-aur.txt")
ok "Listas: $NAT oficiais + $AUR AUR"

# ---------- Copiar o próprio script de backup ----------
log "Incluindo backup-plasma.sh na pasta de saída..."
SELF_PATH="$(readlink -f "$0")"
if [ -f "$SELF_PATH" ]; then
    cp "$SELF_PATH" "$BACKUP_DIR/backup-plasma.sh"
    chmod +x "$BACKUP_DIR/backup-plasma.sh"
    ok "backup-plasma.sh incluído"
else
    warn "Não foi possível localizar o script em: $SELF_PATH"
fi

if [ "$ENCRYPT" = true ]; then
    log "Criptografando tarballs (GPG AES256)..."
    gpg --symmetric --cipher-algo AES256 --batch --yes "$BACKUP_DIR/backup-plasma-arch.tar.gz"
    [ -f "$BACKUP_DIR/backup-plasma-extras.tar.gz" ] && \
        gpg --symmetric --cipher-algo AES256 --batch --yes "$BACKUP_DIR/backup-plasma-extras.tar.gz"
    ok "Tarballs criptografados"
fi

# ---------- Gerar restore.sh ----------
log "Gerando restore.sh..."
cat > "$BACKUP_DIR/restore.sh" <<RESTORE_EOF
#!/usr/bin/env bash
# restore.sh — gerado por backup-plasma.sh em $TIMESTAMP
#
# O que este script faz:
#   1. Configura ParallelDownloads em /etc/pacman.conf
#   2. Configura MAKEFLAGS em /etc/makepkg.conf (threads - 1)
#   3. Instala yay (via yay-bin) se não existir
#   4. Instala pacotes oficiais + AUR
#   5. Restaura snapshot plasmasafe (perfil desktop, sem splash)
#   6. Restaura extras (fontes, favoritos do Dolphin, Spectacle, etc.)
#
set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_NAME="$SNAPSHOT_NAME"

PARALLEL_DOWNLOADS=16

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "\${BLUE}[*]\${NC} \$*"; }
ok()   { echo -e "\${GREEN}[✓]\${NC} \$*"; }
warn() { echo -e "\${YELLOW}[!]\${NC} \$*"; }
err()  { echo -e "\${RED}[✗]\${NC} \$*" >&2; }

if [ "\$EUID" -eq 0 ]; then err "Não rode como root."; exit 1; fi

echo -e "\${BOLD}==========================================\${NC}"
echo -e "\${BOLD}   Restauração do Plasma\${NC}"
echo -e "\${BOLD}==========================================\${NC}"
echo "Diretório: \$SCRIPT_DIR"
echo
warn "Este script sobrescreve configurações existentes."
read -rp "Continuar? [s/N] " ans
[[ "\$ans" =~ ^[sS]\$ ]] || { err "Abortado."; exit 1; }

log "Solicitando credenciais sudo..."
sudo -v

( while true; do sudo -n true; sleep 60; kill -0 "\$\$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE_PID=\$!
trap 'kill \$SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT

# ---------- 1. /etc/pacman.conf ----------
log "Configurando ParallelDownloads = \$PARALLEL_DOWNLOADS em /etc/pacman.conf..."
if grep -q '^ParallelDownloads' /etc/pacman.conf; then
    sudo sed -i "s/^ParallelDownloads.*/ParallelDownloads = \$PARALLEL_DOWNLOADS/" /etc/pacman.conf
    ok "ParallelDownloads atualizado"
elif grep -q '^#ParallelDownloads' /etc/pacman.conf; then
    sudo sed -i "s/^#ParallelDownloads.*/ParallelDownloads = \$PARALLEL_DOWNLOADS/" /etc/pacman.conf
    ok "ParallelDownloads habilitado"
else
    sudo sed -i "/^\[options\]/a ParallelDownloads = \$PARALLEL_DOWNLOADS" /etc/pacman.conf
    ok "ParallelDownloads adicionado"
fi

# ---------- 2. /etc/makepkg.conf ----------
THREADS=\$(nproc)
JOBS=\$((THREADS - 1))
[ "\$JOBS" -lt 1 ] && JOBS=1
log "Configurando MAKEFLAGS=\"-j\$JOBS\" (\$THREADS threads detectados)..."
if grep -q '^MAKEFLAGS' /etc/makepkg.conf; then
    sudo sed -i "s|^MAKEFLAGS.*|MAKEFLAGS=\"-j\${JOBS}\"|" /etc/makepkg.conf
elif grep -q '^#MAKEFLAGS' /etc/makepkg.conf; then
    sudo sed -i "s|^#MAKEFLAGS.*|MAKEFLAGS=\"-j\${JOBS}\"|" /etc/makepkg.conf
else
    echo "MAKEFLAGS=\"-j\${JOBS}\"" | sudo tee -a /etc/makepkg.conf > /dev/null
fi
ok "MAKEFLAGS configurado para -j\$JOBS"

# ---------- 3. Instalar yay ----------
if command -v yay &>/dev/null; then
    ok "yay já instalado"
    AUR_HELPER=yay
elif command -v paru &>/dev/null; then
    ok "paru encontrado, será usado como AUR helper"
    AUR_HELPER=paru
else
    log "Instalando yay (via yay-bin)..."
    sudo pacman -S --needed --noconfirm git base-devel
    YAY_BUILD=\$(mktemp -d)
    git clone https://aur.archlinux.org/yay-bin.git "\$YAY_BUILD/yay-bin"
    ( cd "\$YAY_BUILD/yay-bin" && makepkg -si --noconfirm )
    rm -rf "\$YAY_BUILD"
    command -v yay &>/dev/null || { err "Falha ao instalar yay."; exit 1; }
    ok "yay instalado"
    AUR_HELPER=yay
fi

# ---------- 4. Pacotes oficiais ----------
log "Instalando pacotes oficiais..."
sudo pacman -S --needed --noconfirm - < "\$SCRIPT_DIR/pkglist-oficial.txt"
ok "Pacotes oficiais instalados"

# ---------- 5. Pacotes AUR ----------
log "Instalando pacotes do AUR..."
\$AUR_HELPER -S --needed --noconfirm - < "\$SCRIPT_DIR/pkglist-aur.txt"
ok "Pacotes AUR instalados"

# ---------- 6. Snapshot plasmasafe ----------
log "Importando snapshot..."
SNAP="\$SCRIPT_DIR/backup-plasma-arch.tar.gz"
if [ -f "\$SNAP.gpg" ]; then
    warn "Descriptografando snapshot..."
    gpg -d "\$SNAP.gpg" > "\$SNAP"
fi
plasmasafe import "\$SNAP"
ok "Snapshot importado"

log "Restaurando snapshot \$SNAPSHOT_NAME..."
plasmasafe restore "\$SNAPSHOT_NAME" --force
ok "Configurações restauradas"

# ---------- 7. Extras ----------
if [ -f "\$SCRIPT_DIR/backup-plasma-extras.tar.gz" ]; then
    log "Restaurando extras..."
    tar -xzf "\$SCRIPT_DIR/backup-plasma-extras.tar.gz" -C "\$HOME"
    ok "Extras restaurados"
fi
if [ -f "\$SCRIPT_DIR/backup-plasma-extras.tar.gz.gpg" ]; then
    log "Descriptografando e restaurando extras..."
    gpg -d "\$SCRIPT_DIR/backup-plasma-extras.tar.gz.gpg" | tar -xzf - -C "\$HOME"
    ok "Extras restaurados"
fi

echo
echo -e "\${GREEN}==========================================\${NC}"
echo -e "\${GREEN}   Restauração concluída!\${NC}"
echo -e "\${GREEN}==========================================\${NC}"
warn "Faça logout e login novamente para aplicar tudo."
RESTORE_EOF
chmod +x "$BACKUP_DIR/restore.sh"
ok "restore.sh criado"

# ---------- README ----------
log "Gerando README.md..."
cat > "$BACKUP_DIR/README.md" <<README_EOF
# Backup do KDE Plasma 6

Gerado em: $TIMESTAMP

## Conteúdo

- \`backup-plasma-arch.tar.gz\` — Snapshot do Plasma (perfil \`desktop\`, sem splash)
- \`backup-plasma-extras.tar.gz\` — Fontes, favoritos do Dolphin, esquemas de cor, GTK, **Spectacle**
- \`pkglist-oficial.txt\` — Pacotes dos repositórios oficiais
- \`pkglist-aur.txt\` — Pacotes do AUR
- \`backup-plasma.sh\` — Script de backup (para reusar na máquina nova)
- \`restore.sh\` — Script de restauração automatizado
- \`README.md\` — Este arquivo

---

## O que o \`restore.sh\` faz

1. Configura \`ParallelDownloads = 16\` em \`/etc/pacman.conf\`
2. Configura \`MAKEFLAGS="-j(N-1)"\` em \`/etc/makepkg.conf\` (N = nº de threads via \`nproc\`)
3. Instala \`yay\` (via \`yay-bin\`) se não existir
4. Instala pacotes oficiais e do AUR
5. Restaura snapshot do Plasma (perfil \`desktop\`, sem splash)
6. Restaura extras (fontes, favoritos do Dolphin, Spectacle, etc.)

---

## Arquitetura: o que é original vs. o que usa ferramentas existentes

Este script foi escrito do zero, mas **orquestra ferramentas existentes** em vez de reimplementar tudo.

### ✅ Escrito do zero (original)

| Parte | Descrição |
| :--- | :--- |
| \`backup-plasma.sh\` | Fluxo completo: dependências, aviso do plasmashell, timestamp, verificação de zoom, extras, cópia do próprio script, geração do \`restore.sh\` e do README |
| \`restore.sh\` (gerado) | Lógica de restaurar em ordem: \`pacman.conf\` → \`makepkg.conf\` → yay → pacotes → snapshot → extras |
| Edição de \`pacman.conf\` / \`makepkg.conf\` | \`sed\` cobrindo 3 casos (linha ativa, comentada, ausente) + \`-j\$(nproc-1)\` |
| Instalação do yay | Build via \`yay-bin\` em \`mktemp -d\` com limpeza |
| Sudo keepalive | \`sudo -v\` + loop em background |
| Tratamento de erros | \`set -euo pipefail\`, funções \`log/ok/warn/err\`, verificação de \`EUID\` |
| README gerado | Conteúdo e estrutura |

### 🔧 Ferramentas existentes usadas (não reimplementadas)

| Ferramenta | Para quê |
| :--- | :--- |
| **\`plasmasafe\`** (AUR) | **Peça central** — é ele que sabe *quais* arquivos do Plasma salvar/restaurar por perfil (\`desktop\`, \`full\`, etc.). Sem ele, o script não saberia a lista correta de \`*rc\` nem geraria o \`manifest.json\`/\`pacman.txt\` do tarball |
| \`pacman -Qqen\` / \`-Qqem\` | Separar pacotes nativos vs. AUR |
| \`tar\` | Empacotar extras e ler o tarball do snapshot |
| \`gpg\` | Criptografia AES256 opcional |
| \`sed\` | Edição de \`pacman.conf\` e \`makepkg.conf\` |
| \`nproc\` | Detectar threads para \`-j(N-1)\` |
| \`yay\` / \`paru\` | AUR helper (instalado sob demanda via \`yay-bin\`) |
| \`git\` + \`base-devel\` + \`makepkg\` | Build do \`yay-bin\` se não existir |
| \`readlink\` | Resolver caminho do próprio script mesmo via symlink |
| \`pgrep\` | Detectar se \`plasmashell\` está rodando |

### 🧩 Por que essa divisão faz sentido

Eu **poderia** ter escrito um script que copiasse \`~/.config/*rc\` manualmente, sem o \`plasmasafe\`. Mas isso teria dois problemas:

1. **Manutenção frágil** — a lista de arquivos do Plasma muda entre versões. O \`plasmasafe\` já mantém isso por perfil (\`desktop\` exclui splash, \`full\` inclui, etc.).
2. **Menos segurança** — o \`plasmasafe\` faz backup antes de restaurar, valida integridade (\`verify\`), tem \`--dry-run\` e exporta no formato \`manifest.json\` + \`pacman.txt\` embutido.

A arquitetura é: **o \`plasmasafe\` faz o trabalho difícil do KDE; este script automatiza o ciclo completo de provisionamento em volta dele** — configuração do sistema (\`pacman.conf\`, \`makepkg.conf\`), instalação do AUR helper, listas de pacotes, extras, e gera um \`restore.sh\` autocontido.

### 🔍 Analogia

Seria como um script que automatiza a instalação do Arch: ele não reimplementa o \`pacman\` nem o \`mkfs\`, mas orquestra as ferramentas certas na ordem certa com os parâmetros certos. A "inteligência" do script é **a ordem, o tratamento de erros e a portabilidade** — não a reimplementação de cada passo.

### ⚠️ O que isso implica para o Plasma 7

Como o conhecimento de "quais arquivos do Plasma" está no **\`plasmasafe\`** (e não neste script), a adaptação ao Plasma 7 dependerá de o \`plasmasafe\` ser atualizado pelos mantenedores. Se ele for abandonado:

1. Substitua as linhas \`plasmasafe save/export/import/restore\` por um \`tar\` manual dos \`~/.config/*rc\` relevantes.
2. Mantenha uma lista própria de arquivos (que é justamente o que o \`plasmasafe\` faz por você hoje).

As demais etapas (\`pacman.conf\`, \`makepkg.conf\`, \`yay\`, listas de pacotes, extras) são bem estáveis e provavelmente sobreviverão sem mudanças.

---

## Notas específicas

### Spectacle

A configuração do Spectacle (\`spectaclerc\`, incluindo a opção de **não incluir a sombra da janela**) está no \`backup-plasma-extras.tar.gz\` e é restaurada automaticamente.

> **Aviso de versão:** No Spectacle **6.5.1** em Wayland, a opção "Incluir sombra da janela" pode não ter efeito (bug KDE #510982). Corrigido em **6.5.2+**. Se você estiver em 6.5.1, verifique novamente após atualizar.

### Splash screen

Não está incluído (perfil \`desktop\` do plasmasafe exclui \`ksplashrc\`), conforme desejado.

---

## Restaurar em máquina nova

1. Instale Arch + Plasma 6
2. Faça login uma vez, depois logout (para criar o \`HOME\`)
3. Copie este diretório para a máquina nova (ou extraia o \`.tar\` de \`~/backups/\`)
4. Execute:
   \`\`\`bash
   cd ~/plasma-backup-*
   ./restore.sh
   \`\`\`
5. Logout/login

## Notas

- Splash screen **não** está incluído (conforme desejado)
- Se houver arquivos \`.gpg\`, o \`restore.sh\` descriptografa automaticamente
- O \`backup-plasma.sh\` incluído pode ser reusado na máquina nova para gerar novos snapshots
- O tarball sem compressão em \`~/backups/\` preserva metadados e é mais rápido de extrair
README_EOF
ok "README.md criado"

# ---------- Tarball sem compressão em ~/backups ----------
log "Criando tarball sem compressão em ~/backups/..."
mkdir -p "$HOME/backups"
TARBALL="$HOME/backups/$(basename "$BACKUP_DIR").tar"
tar -cf "$TARBALL" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
ok "Tarball criado: $TARBALL"
TARBALL_SIZE=$(du -h "$TARBALL" | cut -f1)

# ---------- Sumário ----------
echo
echo -e "${BOLD}==========================================${NC}"
echo -e "${GREEN}   Backup concluído com sucesso!${NC}"
echo -e "${BOLD}==========================================${NC}"
echo
echo -e "Pasta de backup: ${BOLD}$BACKUP_DIR${NC}"
echo -e "Tarball (.tar):  ${BOLD}$TARBALL${NC}  ($TARBALL_SIZE)"
echo
echo "Conteúdo da pasta:"
ls -lh "$BACKUP_DIR" | tail -n +2 | awk '{printf "  %-42s %s\n", $9, $5}'
echo
echo "Tarballs em ~/backups/:"
ls -lh "$HOME/backups"/*.tar 2>/dev/null | awk '{printf "  %-42s %s\n", $9, $5}' || echo "  (nenhum)"
echo
echo -e "Para copiar para pendrive:"
echo -e "  ${BLUE}cp $TARBALL /run/media/\$USER/<SEU_PENDRIVE>/${NC}"
echo -e "  ${BLUE}# ou a pasta inteira:${NC}"
echo -e "  ${BLUE}cp -r $BACKUP_DIR /run/media/\$USER/<SEU_PENDRIVE>/${NC}"
echo
