#!/usr/bin/env bash
#
# backup-heroic.sh - Backup do Heroic por prefixo/jogo: le o GamesConfig e leva
#                    junto a config daquele prefixo e o Proton que ele usa.
#
# Uso rapido:
#   backup-heroic.sh                     abre o menu (pergunta o que salvar)
#   backup-heroic.sh --prefix nfs-u2     prefixo + config do prefixo + Proton
#   backup-heroic.sh --prefix nfs-mw
#   backup-heroic.sh --all               todos os prefixos + todas as configs
#   backup-heroic.sh --config-only       ~/.config/heroic inteiro (sem prefixo)
#   backup-heroic.sh --path /caminho     uma pasta qualquer (sem config)
#
# O que entra num backup de prefixo:
#   - o prefixo Wine inteiro (jogo, saves, ReShade, dgVoodoo...)
#   - SOMENTE o(s) GamesConfig/*.json cujo "winePrefix" aponta para ele
#     (dali saem wineVersion e WINEDLLOVERRIDES, por exemplo)
#   - a entrada desse jogo na sideload_apps/library.json
#   - o Proton referenciado em "wineVersion.bin" (pode pular com --no-proton)
#
# Cada snapshot vira uma pasta "<slug>-<YYYYMMDDHHMM>", e dentro dela:
#   restaurar.sh     -> atalho (hardlink) que restaura ESTE snapshot
#   META.txt         -> metadados lidos pelo restaurar.sh
#   INFO.txt         -> descricao legivel
#   prefix/ (ou folder/ ou prefixes/...) + heroic-config/ + heroic-state/
#
# Na raiz do destino ele tambem cria/atualiza o restaurar-backup.sh, que
# lista/restaura todos os snapshots (util levar a pasta pra outra maquina).
# Depois de cada backup ele cria tambem "<slug>-<YYYYMMDDHHMM>.tar" sem
# compressao (tar -cf) ao lado da pasta; desligue com --no-tar.
#
# Outras opcoes:
#   -n, --dry-run        simula, nao escreve nada
#   -d, --dest DIR       outro destino
#   -k, --keep N         guarda N snapshots por alvo (padrao 3)
#   --no-config          nao inclui nada de ~/.config/heroic
#   --no-proton          inclui o JSON, mas nao copia o binario do Proton
#   --full-config        copia ~/.config/heroic inteiro (comportamento antigo)
#   --no-state           nao inclui ~/.local/state/Heroic (logs)
#   --no-tar             nao cria o .tar sem compressao ao lado do snapshot
#   --full               copia completa, sem hardlinks
#   -f, --force          permite com jogo/Wine aberto
#   --menu               forca o menu (mesmo sem terminal interativo)
#   --list               lista os snapshots
#   --verify NOME        confere um snapshot (rapido, so metadados)
#   --restore NOME       restaura um snapshot (pede confirmacao)
#
set -euo pipefail
umask 077

# ------------------------------- configuracao --------------------------------
HOME_DIR="${HOME:-/home/bn}"
PREFIXES_ROOT="${PREFIXES_ROOT:-$HOME_DIR/Games/Heroic/Prefixes}"
HEROIC_ROOT="${HEROIC_ROOT:-$HOME_DIR/Games/Heroic}"
HEROIC_CONFIG="${HEROIC_CONFIG:-$HOME_DIR/.config/heroic}"
HEROIC_STATE="${HEROIC_STATE:-$HOME_DIR/.local/state/Heroic}"

EXTERNAL_ROOT="/run/media/bn/5724daa5-eb92-4da8-9845-1ec5488b7be0"
EXTERNAL_DEST="$EXTERNAL_ROOT/bn/backups/heroic"

DEST_BASE=""
KEEP=3
DRY_RUN=0
FORCE=0
NO_STATE=0
NO_CONFIG=0
NO_PROTON=0
FULL_CONFIG=0
NO_LINK=0
NO_TAR=0
FORCE_MENU=0
ACTION="backup"
TARGET=""
SELECTIONS=()   # formato: "kind|arg"

CONFIG_MODE="none"   # none | targeted | full
CFG_APPS=()
CFG_PROTONS=()
PREFIX_ROOT_SET=0    # usado apenas pelo restaurar-backup.sh gerado

# ---------------------------------- helpers ----------------------------------
c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_bld=$'\033[1m'; c_rst=$'\033[0m'
info()  { printf '%s[*]%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$c_yel" "$c_rst" "$*"; }
die()   { printf '%s[x]%s %s\n' "$c_red" "$c_rst" "$*" >&2; exit 1; }

usage() {
  awk 'NR>1 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else { exit } }' "$0"
  exit 0
}

human() { numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "$1 bytes"; }

resolve_dest() {
  [[ -n "$DEST_BASE" ]] && return
  if [[ -d "$EXTERNAL_ROOT" ]] && mountpoint -q "$EXTERNAL_ROOT" && [[ -w "$EXTERNAL_ROOT/bn" ]]; then
    DEST_BASE="$EXTERNAL_DEST"
  else
    DEST_BASE="$HOME_DIR/Backups/heroic"
  fi
}

# Gera/atualiza o script de restauracao autocontido na raiz do backup.
# Assim a pasta de backups pode ser levada para outra maquina sem depender
# deste script: basta rodar restaurar-backup.sh de dentro dela.
# Cada snapshot recebe um hardlink chamado restaurar.sh para o mesmo arquivo,
# que restaura apenas aquele snapshot (sem menu).
ensure_restore_helper() {
  [[ -d "$DEST_BASE" ]] || return 0
  local dest="$DEST_BASE/restaurar-backup.sh" tmp
  tmp=$(mktemp "$DEST_BASE/.restaurar-backup.XXXXXX")
  cat > "$tmp" <<'RESTORE_HELPER'
#!/usr/bin/env bash
#
# restaurar-backup.sh / restaurar.sh - Restaura um snapshot do Heroic criado
#                                      pelo backup-heroic.sh.
#
# Na raiz da pasta de backups chama-se restaurar-backup.sh e abre um menu
# com todos os snapshots.
# Dentro da pasta de um snapshot chama-se restaurar.sh e restaura aquele
# snapshot direto (sem precisar de argumentos).
#
# Uso:
#   ./restaurar-backup.sh                    abre o menu de snapshots
#   ./restaurar-backup.sh --list             lista os snapshots
#   ./restaurar-backup.sh --verify NOME      confere um snapshot
#   ./restaurar-backup.sh --restore NOME     restaura (pede confirmacao)
#
#   ./restaurar.sh                           restaura este snapshot
#   ./restaurar.sh --verify                  confere este snapshot
#
# Opcoes:
#   -d, --dir DIR            pasta dos snapshots (padrao: a pasta deste script)
#   -f, --force              permite com jogo/Wine aberto
#       --yes                nao pede confirmacao (cuidado!)
#       --heroic-config DIR  outro ~/.config/heroic
#       --state DIR          outro ~/.local/state/Heroic
#       --prefix-root DIR    outro ~/Games/Heroic/Prefixes
#
# O que ele restaura (lido do META.txt de cada snapshot):
#   - o prefixo Wine (ou a pasta avulsa) no caminho original;
#   - se config_mode=targeted: somente o GamesConfig do jogo, a entrada
#     dele na library.json (mesclada) e o Proton referenciado;
#   - se config_mode=full: ~/.config/heroic por cima, sem apagar arquivos;
#   - os logs do Heroic, quando existem no snapshot.
#
set -euo pipefail
umask 077

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Se este script estiver dentro de um snapshot (tem META.txt), cuida so dele.
if [[ -f "$SELF_DIR/META.txt" ]]; then
  SNAP_FIXED="$SELF_DIR"
  SNAP_ROOT="$(dirname "$SELF_DIR")"
else
  SNAP_FIXED=""
  SNAP_ROOT="$SELF_DIR"
fi
HOME_DIR="${HOME:-/home/bn}"
HEROIC_CONFIG="${HEROIC_CONFIG:-$HOME_DIR/.config/heroic}"
HEROIC_STATE="${HEROIC_STATE:-$HOME_DIR/.local/state/Heroic}"
PREFIXES_ROOT="${PREFIXES_ROOT:-$HOME_DIR/Games/Heroic/Prefixes}"
PREFIX_ROOT_SET=0

FORCE=0
ASSUME_YES=0
ACTION=""
TARGET=""

c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_bld=$'\033[1m'; c_rst=$'\033[0m'
info()  { printf '%s[*]%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$c_yel" "$c_rst" "$*"; }
die()   { printf '%s[x]%s %s\n' "$c_red" "$c_rst" "$*" >&2; exit 1; }

usage() {
  awk 'NR>1 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else { exit } }' "$0"
  exit 0
}

snapshot_dirs() {
  local d b
  while IFS= read -r d; do
    b=$(basename "$d")
    if [[ -f "$d/META.txt" ]] || [[ "$b" =~ ^heroic- ]]; then
      echo "$d"
    fi
  done < <(find "$SNAP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null) | sort
}

find_snapshot() {
  local name="${1:-}" c
  [[ -n "$name" ]] || die "Informe o nome do snapshot (use --list)."
  if [[ -d "$name" ]]; then realpath "$name"; return; fi
  if [[ -d "$SNAP_ROOT/$name" ]]; then realpath "$SNAP_ROOT/$name"; return; fi
  c=$(find "$SNAP_ROOT" -mindepth 1 -maxdepth 1 -type d -name "$name" | head -1)
  [[ -n "$c" ]] || die "Snapshot nao encontrado: $name"
  realpath "$c"
}

meta_get() {   # meta_get SNAP chave
  local snap=$1 key=$2
  sed -n "s/^${key}=//p" "$snap/META.txt" 2>/dev/null | head -1
}

game_running() {
  pgrep -x speed2.exe >/dev/null 2>&1 && return 0
  pgrep -x speed.exe  >/dev/null 2>&1 && return 0
  pgrep -x wineserver >/dev/null 2>&1 && return 0
  pgrep -f 'Need For Speed.*\.exe' >/dev/null 2>&1 && return 0
  return 1
}

check_idle() {
  [[ "$FORCE" -eq 1 ]] && return 0
  if game_running; then
    pgrep -a -x speed2.exe 2>/dev/null || true
    pgrep -a -x speed.exe  2>/dev/null || true
    pgrep -a -x wineserver 2>/dev/null || true
    die "Ha jogo/Wine rodando. Feche o Heroic e o jogo (ou use --force)."
  fi
}

RSYNC=(rsync -aHAX --numeric-ids --human-readable)
EXCLUDES=(
  --exclude='drive_c/users/*/AppData/Local/Temp/'
  --exclude='drive_c/users/*/Temp/'
  --exclude='drive_c/windows/temp/'
  --exclude='*.lock'
)

rsync_one() {                         # rsync_one SRC DEST [extras...]
  local src=$1 dest=$2
  shift 2
  "${RSYNC[@]}" "$@" "$src" "$dest"
}

verify_dir() {                        # verify_dir SRC DEST [excludes...]
  local src=$1 dest=$2
  shift 2
  local out n
  out=$("${RSYNC[@]}" -n --itemize-changes --delete "$@" "$src" "$dest" 2>/dev/null || true)
  n=$(printf '%s\n' "$out" | grep -c '^[<>ch.*]' || true)
  if [[ "$n" -eq 0 ]]; then
    return 0
  else
    printf '%s\n' "$out" | head -10 >&2
    return 1
  fi
}

merge_library() {                     # merge_library ARQUIVO_ATUAL ARQUIVO_BACKUP
  command -v python3 >/dev/null || return 2
  python3 - "$1" "$2" <<'PY'
import json, os, sys
cur_path, bak_path = sys.argv[1], sys.argv[2]
try:
    cur = json.load(open(cur_path, encoding='utf-8'))
except Exception:
    cur = {'games': []}
try:
    bak = json.load(open(bak_path, encoding='utf-8'))
except Exception:
    sys.exit(0)
games = cur.get('games', [])
index = {g.get('app_name'): i for i, g in enumerate(games)}
for g in bak.get('games', []):
    app = g.get('app_name')
    if app in index:
        games[index[app]] = g
    else:
        games.append(g)
        index[app] = len(games) - 1
cur['games'] = games
os.makedirs(os.path.dirname(cur_path), exist_ok=True)
json.dump(cur, open(cur_path, 'w', encoding='utf-8'), indent='\t', ensure_ascii=False)
PY
}

# -------------------------------- lista --------------------------------------
do_list() {
  echo "${c_bld}Snapshots em $SNAP_ROOT:${c_rst}"
  local d name label cm any=0
  while IFS= read -r d; do
    any=1
    name=$(basename "$d")
    if [[ -f "$d/META.txt" ]]; then
      label=$(sed -n 's/^label=//p' "$d/META.txt")
      cm=$(sed -n 's/^config_mode=//p' "$d/META.txt")
      [[ -n "$cm" ]] && label="$label  [config: $cm]"
    else
      label="(formato antigo, sem META.txt)"
    fi
    printf '  %-34s %-8s %s\n' "$name" "$(du -sh "$d" 2>/dev/null | cut -f1)" "$label"
  done < <(snapshot_dirs | sort -r)
  [[ "$any" -eq 0 ]] && echo "  (nenhum)"
  echo
  echo "Tamanho mostrado = aparente de cada snapshot (hardlinks compartilhados)."
  echo "Uso real do diretorio (cada arquivo contado uma vez): $(du -sh "$SNAP_ROOT" 2>/dev/null | cut -f1)"
  df -h "$SNAP_ROOT" | awk 'NR==2{print "Livre no destino: "$4}'
}

# -------------------------------- verify -------------------------------------
do_verify() {
  local snap
  snap=$(find_snapshot "$TARGET")
  check_idle
  [[ -f "$snap/META.txt" ]] || die "Snapshot no formato antigo; nao sei verificar automaticamente."
  info "Conferindo $(basename "$snap") (so metadados)..."
  local kind path name ok=1 cmode
  kind=$(meta_get "$snap" kind)
  path=$(meta_get "$snap" path)
  if [[ "$PREFIX_ROOT_SET" -eq 1 && "$kind" == "prefix" ]]; then
    path="$PREFIXES_ROOT/$(basename "$path")"
  fi
  cmode=$(meta_get "$snap" config_mode); [[ -z "$cmode" ]] && cmode="full"

  case "$kind" in
    prefix)
      verify_dir "$path/" "$snap/prefix/" "${EXCLUDES[@]}" && info "  prefixo: OK" || { warn "  prefixo: divergencias"; ok=0; } ;;
    folder)
      verify_dir "$path/" "$snap/folder/" "${EXCLUDES[@]}" && info "  pasta: OK" || { warn "  pasta: divergencias"; ok=0; } ;;
    all)
      local d
      for d in "$snap"/prefixes/*/; do
        [[ -d "$d" ]] || continue
        name=$(basename "$d")
        verify_dir "$PREFIXES_ROOT/$name/" "$d" "${EXCLUDES[@]}" \
          && info "  $name: OK" || { warn "  $name: divergencias"; ok=0; }
      done ;;
  esac

  if [[ "$cmode" == "targeted" && -d "$snap/heroic-config" ]]; then
    local f
    for f in "$snap"/heroic-config/GamesConfig/*.json; do
      [[ -f "$f" ]] || continue
      if python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$f" 2>/dev/null; then
        info "  config $(basename "$f"): OK (JSON valido)"
        if ! cmp -s "$f" "$HEROIC_CONFIG/GamesConfig/$(basename "$f")"; then
          info "    obs: a config atual difere do backup (mudou depois dele)"
        fi
      else
        warn "  config $(basename "$f"): JSON invalido"; ok=0
      fi
    done
    local d
    for d in "$snap"/heroic-config/tools/proton/*/; do
      [[ -d "$d" ]] || continue
      name=$(basename "$d")
      verify_dir "$d/" "$HEROIC_CONFIG/tools/proton/$name/" \
        && info "  proton $name: OK" || { warn "  proton $name: divergencias"; ok=0; }
    done
  elif [[ "$cmode" == "full" && -d "$snap/heroic-config" ]]; then
    verify_dir "$HEROIC_CONFIG/" "$snap/heroic-config/" \
      && info "  config Heroic: OK" || { warn "  config Heroic: divergencias"; ok=0; }
  fi

  [[ "$ok" -eq 1 ]] && info "Tudo confere." || warn "Ha divergencias."
}

# -------------------------------- restore ------------------------------------
do_restore() {
  local snap kind path name d cmode
  snap=$(find_snapshot "$TARGET")
  if [[ ! -f "$snap/META.txt" ]]; then
    warn "Snapshot no formato antigo (sem META.txt); nao sei restaurar automaticamente."
    echo "Restaure manualmente, por exemplo:"
    echo "  rsync -aHAX --delete \"$snap/prefix/\" \"$PREFIXES_ROOT/nfs-u2/\""
    echo "  rsync -aHAX --delete \"$snap/heroic-config/\" \"$HEROIC_CONFIG/\""
    die "Nada foi alterado."
  fi

  check_idle
  kind=$(meta_get "$snap" kind)
  path=$(meta_get "$snap" path)
  if [[ "$PREFIX_ROOT_SET" -eq 1 && "$kind" == "prefix" ]]; then
    path="$PREFIXES_ROOT/$(basename "$path")"
  fi
  cmode=$(meta_get "$snap" config_mode); [[ -z "$cmode" ]] && cmode="full"

  echo "${c_bld}Restaurar de:${c_rst} $(basename "$snap")"
  case "$kind" in
    prefix|folder) echo "  -> $path" ;;
    all) for d in "$snap"/prefixes/*/; do [[ -d "$d" ]] && echo "  -> $PREFIXES_ROOT/$(basename "$d")"; done ;;
  esac
  if [[ "$cmode" == "targeted" ]]; then
    echo "  -> GamesConfig do jogo + library + Proton, em $HEROIC_CONFIG"
    echo "     (copia por cima; nao apaga configs de outros jogos)"
    echo "     apps: $(meta_get "$snap" apps)"
    echo "     protons: $(meta_get "$snap" protons)"
  elif [[ "$cmode" == "full" && -d "$snap/heroic-config" ]]; then
    echo "  -> $HEROIC_CONFIG (copia por cima, sem apagar)"
  fi
  [[ -d "$snap/heroic-state" ]] && echo "  -> $HEROIC_STATE"
  echo

  if [[ "$ASSUME_YES" -eq 0 ]]; then
    warn "Isso SOBRESCREVE os arquivos atuais."
    read -r -p "Digite RESTORE para confirmar: " ans
    [[ "$ans" == "RESTORE" ]] || die "Cancelado."
  fi

  case "$kind" in
    prefix)
      mkdir -p "$path"
      rsync_one "$snap/prefix/" "$path/" "${EXCLUDES[@]}" --delete ;;
    folder)
      mkdir -p "$path"
      rsync_one "$snap/folder/" "$path/" "${EXCLUDES[@]}" --delete ;;
    all)
      for d in "$snap"/prefixes/*/; do
        [[ -d "$d" ]] || continue
        name=$(basename "$d")
        mkdir -p "$PREFIXES_ROOT/$name"
        rsync_one "$d/" "$PREFIXES_ROOT/$name/" "${EXCLUDES[@]}" --delete
      done ;;
  esac

  if [[ "$cmode" == "targeted" && -d "$snap/heroic-config" ]]; then
    local f
    for f in "$snap"/heroic-config/GamesConfig/*.json; do
      [[ -f "$f" ]] || continue
      mkdir -p "$HEROIC_CONFIG/GamesConfig"
      cp -a -- "$f" "$HEROIC_CONFIG/GamesConfig/$(basename "$f")"
      info "config restaurada: GamesConfig/$(basename "$f")"
    done
    if [[ -f "$snap/heroic-config/sideload_apps/library.json" ]]; then
      if merge_library "$HEROIC_CONFIG/sideload_apps/library.json" \
                       "$snap/heroic-config/sideload_apps/library.json"; then
        info "library.json mesclada"
      else
        warn "python3 ausente: library.json NAO mesclada (copie a mao se precisar)"
      fi
    fi
    for d in "$snap"/heroic-config/tools/proton/*/; do
      [[ -d "$d" ]] || continue
      name=$(basename "$d")
      mkdir -p "$HEROIC_CONFIG/tools/proton"
      rsync_one "$d/" "$HEROIC_CONFIG/tools/proton/$name/" --delete
      info "Proton restaurado: $name"
    done
  elif [[ "$cmode" == "full" && -d "$snap/heroic-config" ]]; then
    rsync_one "$snap/heroic-config/" "$HEROIC_CONFIG/"
    info "config do Heroic restaurada (sem apagar arquivos mais novos)"
  fi

  if [[ -d "$snap/heroic-state" ]]; then
    rsync_one "$snap/heroic-state/" "$HEROIC_STATE/" --delete
  fi
  info "Restauracao concluida."
  info "Confira $HEROIC_CONFIG/GamesConfig/ (winePrefix, wineVersion e WINEDLLOVERRIDES)."
}

# -------------------------------- menu ---------------------------------------
menu() {
  local names=() d n i=1 ans tok
  mapfile -t names < <(snapshot_dirs | sort -r)
  [[ ${#names[@]} -gt 0 ]] || die "Nenhum snapshot em $SNAP_ROOT"

  echo "${c_bld}Snapshots em $SNAP_ROOT:${c_rst}"
  echo
  for d in "${names[@]}"; do
    n=$(basename "$d")
    printf '  %2d) %-34s %-8s %s\n' "$i" "$n" \
      "$(du -sh "$d" 2>/dev/null | cut -f1)" \
      "$(sed -n 's/^label=//p' "$d/META.txt" 2>/dev/null)"
    i=$((i+1))
  done
  echo "   0) sair"
  echo
  echo "Digite o numero para restaurar, ou 'v NUMERO' para so conferir."
  read -r -p "Escolha: " ans
  [[ -z "$ans" ]] && die "Nada escolhido."
  if [[ "$ans" == "0" ]]; then exit 0; fi

  local verify=0
  if [[ "$ans" =~ ^[vV][[:space:]]*([0-9]+)$ ]]; then
    verify=1; tok="${BASH_REMATCH[1]}"
  elif [[ "$ans" =~ ^[0-9]+$ ]]; then
    tok="$ans"
  else
    die "Opcao invalida: $ans"
  fi
  [[ "$tok" -ge 1 && "$tok" -le ${#names[@]} ]] || die "Numero fora da lista."
  TARGET=$(basename "${names[$((tok-1))]}")
  if [[ "$verify" -eq 1 ]]; then
    do_verify
  else
    do_restore
  fi
}

# -------------------------------- argumentos ---------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage ;;
    -d|--dir)         SNAP_ROOT="$2"; shift ;;
    -f|--force)       FORCE=1 ;;
    --yes|-y)         ASSUME_YES=1 ;;
    --heroic-config)  HEROIC_CONFIG="$2"; shift ;;
    --state)          HEROIC_STATE="$2"; shift ;;
    --prefix-root)    PREFIXES_ROOT="$2"; PREFIX_ROOT_SET=1; shift ;;
    --list)           ACTION="list" ;;
    --verify)
      ACTION="verify"
      if [[ -n "${2:-}" ]]; then TARGET="$2"; shift; fi
      ;;
    --restore)
      ACTION="restore"
      if [[ -n "${2:-}" ]]; then TARGET="$2"; shift; fi
      ;;
    *)                die "Opcao desconhecida: $1 (use --help)" ;;
  esac
  shift
done

[[ -d "$SNAP_ROOT" ]] || die "Pasta de snapshots nao existe: $SNAP_ROOT"

# Se fomos chamados de dentro de um snapshot (restaurar.sh), o padrao e
# restaurar/verificar aquele snapshot.
if [[ -n "$SNAP_FIXED" ]]; then
  [[ -z "$ACTION" ]] && ACTION="restore"
  [[ -z "$TARGET" ]] && TARGET="$SNAP_FIXED"
fi
[[ -z "$ACTION" ]] && ACTION="menu"

case "$ACTION" in
  list)    do_list ;;
  verify)  do_verify ;;
  restore) do_restore ;;
  menu)
    if [[ -t 0 ]]; then
      menu
    else
      die "Sem terminal. Use --list, --verify NOME ou --restore NOME."
    fi
    ;;
esac
RESTORE_HELPER
  chmod 0755 "$tmp"
  if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
  else
    mv -f "$tmp" "$dest"
    info "Script de restauracao: $dest"
  fi
}

game_running() {
  pgrep -x speed2.exe >/dev/null 2>&1 && return 0
  pgrep -x speed.exe  >/dev/null 2>&1 && return 0
  pgrep -x wineserver >/dev/null 2>&1 && return 0
  pgrep -f 'Need For Speed.*\.exe' >/dev/null 2>&1 && return 0
  return 1
}

check_idle() {
  [[ "$FORCE" -eq 1 ]] && return 0
  if game_running; then
    pgrep -a -x speed2.exe 2>/dev/null || true
    pgrep -a -x speed.exe  2>/dev/null || true
    pgrep -a -x wineserver 2>/dev/null || true
    die "Ha jogo/Wine rodando. Feche o Heroic e o jogo (ou use --force)."
  fi
}

sanitize() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-' | sed 's/--*/-/g; s/^-//; s/-$//'
}

list_prefix_names() {
  find "$PREFIXES_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

prefix_game_label() {
  local p=$1 g
  g=$(find "$p/drive_c/Program Files" "$p/drive_c/Program Files (x86)" \
        -mindepth 1 -maxdepth 2 -type d -iname '*Need*Speed*' 2>/dev/null | sort -r | head -1)
  if [[ -n "$g" ]]; then
    basename "$g"
  else
    echo "(jogo nao detectado)"
  fi
}

# Snapshots do formato novo (tem META.txt) ou do formato antigo (heroic-*).
snapshot_dirs() {
  local d b
  while IFS= read -r d; do
    b=$(basename "$d")
    if [[ -f "$d/META.txt" ]] || [[ "$b" =~ ^heroic- ]]; then
      echo "$d"
    fi
  done < <(find "$DEST_BASE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null) | sort
}

# Extrai o slug: prefere o campo slug= do META.txt; senao deduz do nome
# antigo "heroic-<slug>-<YYYYMMDD>-<HHMMSS>[-N]".
snapshot_slug() {
  local d=$1 s b
  s=$(sed -n 's/^slug=//p' "$d/META.txt" 2>/dev/null | head -1)
  [[ -n "$s" ]] && { printf '%s\n' "$s"; return 0; }
  b=$(basename "$d")
  if [[ "$b" =~ ^heroic-(.+)-[0-9]{8}-[0-9]{6}(-[0-9]+)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

latest_dir_with_path() {
  local rel=$1 slug=${2:-} d
  while IFS= read -r d; do
    if [[ -n "$slug" ]]; then
      [[ "$(snapshot_slug "$d")" == "$slug" ]] || continue
    fi
    if [[ -d "$d/$rel" ]]; then
      printf '%s\n' "$d/$rel"
      return 0
    fi
  done < <(snapshot_dirs | sort -r)
  return 1
}

# ----------------------- leitura do GamesConfig (JSON) -----------------------
read_matches_for_prefix() {
  local prefix=$1
  command -v python3 >/dev/null || die "python3 e necessario para ler o GamesConfig."
  python3 - "$prefix" "$HEROIC_CONFIG" <<'PY'
import glob, json, os, sys
prefix = os.path.realpath(sys.argv[1]).rstrip('/')
cfg = sys.argv[2]
for f in sorted(glob.glob(os.path.join(cfg, 'GamesConfig', '*.json'))):
    try:
        d = json.load(open(f, encoding='utf-8'))
    except Exception:
        continue
    if not isinstance(d, dict):
        continue
    for app, v in d.items():
        if not isinstance(v, dict):
            continue
        wp = v.get('winePrefix') or ''
        if not wp:
            continue
        if os.path.realpath(wp).rstrip('/') != prefix:
            continue
        wv = v.get('wineVersion') or {}
        if not isinstance(wv, dict):
            wv = {}
        envs = v.get('enviromentOptions') or []
        env = ';'.join(
            f"{e.get('key')}={e.get('value')}"
            for e in envs if isinstance(e, dict)
        )
        print('\t'.join([f, app, str(wv.get('name', '')), str(wv.get('type', '')),
                         str(wv.get('bin', '')), env]))
PY
}

read_all_matches() {
  command -v python3 >/dev/null || die "python3 e necessario para ler o GamesConfig."
  python3 - "$HEROIC_CONFIG" <<'PY'
import glob, json, os, sys
cfg = sys.argv[1]
for f in sorted(glob.glob(os.path.join(cfg, 'GamesConfig', '*.json'))):
    try:
        d = json.load(open(f, encoding='utf-8'))
    except Exception:
        continue
    if not isinstance(d, dict):
        continue
    for app, v in d.items():
        if not isinstance(v, dict):
            continue
        if not v.get('winePrefix'):
            continue
        wv = v.get('wineVersion') or {}
        if not isinstance(wv, dict):
            wv = {}
        envs = v.get('enviromentOptions') or []
        env = ';'.join(
            f"{e.get('key')}={e.get('value')}"
            for e in envs if isinstance(e, dict)
        )
        print('\t'.join([f, app, str(wv.get('name', '')), str(wv.get('type', '')),
                         str(wv.get('bin', '')), env]))
PY
}

# ------------------------------- rsync base ----------------------------------
RSYNC=(rsync -aHAX --numeric-ids --human-readable)
EXCLUDES=(
  --exclude='drive_c/users/*/AppData/Local/Temp/'
  --exclude='drive_c/users/*/Temp/'
  --exclude='drive_c/windows/temp/'
  --exclude='*.lock'
)

rsync_one() {                         # rsync_one SRC DEST LINKDEST [excludes...]
  local src=$1 dest=$2 ld=${3:-}
  shift 3
  local args=("${RSYNC[@]}" "$@")
  [[ -n "$ld" ]] && args+=(--link-dest="$ld")
  "${args[@]}" "$src" "$dest"
}

verify_dir() {                        # verify_dir SRC DEST [excludes...]
  local src=$1 dest=$2
  shift 2
  local out n
  out=$("${RSYNC[@]}" -n --itemize-changes --delete "$@" "$src" "$dest" 2>/dev/null || true)
  n=$(printf '%s\n' "$out" | grep -c '^[<>ch.*]' || true)
  if [[ "$n" -eq 0 ]]; then
    return 0
  else
    printf '%s\n' "$out" | head -10 >&2
    return 1
  fi
}

# ---------------------- config do Heroic ligada ao prefixo -------------------
copy_proton() {                       # copy_proton SNAP BIN NAME TYPE
  local snap=$1 bin=$2 wname=$3 wtype=$4
  [[ -z "$bin" ]] && return 0
  case "$bin" in
    "$HEROIC_CONFIG"/tools/proton/*)
      local dir name ld
      dir=$(dirname "$bin")
      name=$(basename "$dir")
      if [[ ! -d "$dir" ]]; then
        warn "Proton referenciado nao existe: $dir"
        return 0
      fi
      if [[ "$NO_PROTON" -eq 1 ]]; then
        info "  Proton referenciado: $name (binario NAO copiado: --no-proton)"
        return 0
      fi
      mkdir -p "$snap/heroic-config/tools/proton"
      ld=$(latest_dir_with_path "heroic-config/tools/proton/$name" || true)
      info "  Proton incluido: $name (${wtype:-proton})"
      rsync_one "$dir/" "$snap/heroic-config/tools/proton/$name/" "$ld" >>"$snap/backup.log" 2>&1
      CFG_PROTONS+=("$name")
      ;;
    *)
      warn "wineVersion.bin fora de tools/proton ($bin); binario nao copiado."
      ;;
  esac
}

copy_targeted_config() {              # copy_targeted_config SNAP MATCHES DESC
  local snap=$1 matches=$2 desc=$3
  local file app wname wtype wbin env
  local -A seen_file=() seen_app=() seen_proton=()
  CFG_APPS=()
  CFG_PROTONS=()

  if [[ -z "$matches" ]]; then
    info "  Nenhum GamesConfig aponta para esse prefixo."
    return 0
  fi

  while IFS=$'\t' read -r file app wname wtype wbin env; do
    [[ -z "$file" ]] && continue
    if [[ -z "${seen_file[$file]:-}" ]]; then
      seen_file[$file]=1
      mkdir -p "$snap/heroic-config/GamesConfig"
      cp -a -- "$file" "$snap/heroic-config/GamesConfig/$(basename "$file")"
      info "  GamesConfig: $(basename "$file")"
    fi
    if [[ -n "$app" && -z "${seen_app[$app]:-}" ]]; then
      seen_app[$app]=1
      CFG_APPS+=("$app")
    fi
    if [[ -n "$wbin" && -z "${seen_proton[$wbin]:-}" ]]; then
      seen_proton[$wbin]=1
      copy_proton "$snap" "$wbin" "$wname" "$wtype"
    fi
  done <<< "$matches"

  if [[ ${#CFG_APPS[@]} -gt 0 ]] && command -v python3 >/dev/null; then
    local lib="$HEROIC_CONFIG/sideload_apps/library.json"
    if [[ -f "$lib" ]]; then
      mkdir -p "$snap/heroic-config/sideload_apps"
      python3 - "$lib" "$snap/heroic-config/sideload_apps/library.json" "${CFG_APPS[@]}" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
apps = set(sys.argv[3:])
try:
    d = json.load(open(src, encoding='utf-8'))
except Exception:
    sys.exit(0)
games = [g for g in d.get('games', []) if g.get('app_name') in apps]
if games:
    json.dump({'games': games}, open(dst, 'w', encoding='utf-8'),
              indent='\t', ensure_ascii=False)
PY
      info "  library.json: ${#CFG_APPS[@]} app(s)"
    fi
  fi
}

# ------------------ helpers de snapshot -------------------------------------

create_snapshot_dir() {
  local slug=$1 base name path i root
  base=$(date +%Y%m%d%H%M)
  name="${slug}-${base}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    root="/tmp/heroic-dryrun-$$"
  else
    root="$DEST_BASE"
  fi
  mkdir -p "$root"
  path="$root/$name"
  i=0
  while [[ -e "$path" ]]; do
    i=$((i+1)); path="$root/${name}-$i"
  done
  mkdir -p "$path"
  printf '%s\n' "$path"
}

write_meta() {
  local snap=$1 key=$2 val=$3
  printf '%s=%s\n' "$key" "$val" >> "$snap/META.txt"
}

create_restore_link() {
  local snap=$1
  if [[ "$DRY_RUN" -eq 0 && -f "$DEST_BASE/restaurar-backup.sh" ]]; then
    ln -f "$DEST_BASE/restaurar-backup.sh" "$snap/restaurar.sh" 2>/dev/null \
      || cp -a "$DEST_BASE/restaurar-backup.sh" "$snap/restaurar.sh"
    chmod +x "$snap/restaurar.sh" 2>/dev/null || true
  fi
}

create_tar() {
  [[ "$NO_TAR" -eq 1 || "$DRY_RUN" -eq 1 ]] && return 0
  local snap=$1 tar="${snap}.tar"
  info "  Criando $tar..."
  tar -C "$(dirname "$snap")" -cf "$tar" "$(basename "$snap")"
  info "  Tamanho do tar: $(du -h "$tar" | cut -f1)"
}

prune_old() {
  local slug=$1 i=0 d dirs=()
  [[ "$KEEP" -le 0 ]] && return 0
  while IFS= read -r d; do
    if [[ "$(snapshot_slug "$d")" == "$slug" ]]; then
      dirs+=("$d")
    fi
  done < <(snapshot_dirs | sort -r)
  for d in "${dirs[@]}"; do
    i=$((i+1))
    if [[ "$i" -gt "$KEEP" ]]; then
      info "  Removendo snapshot antigo: $(basename "$d")"
      rm -rf -- "$d" "${d}.tar"
    fi
  done
}

config_mode_str() {
  if [[ "$NO_CONFIG" -eq 1 ]]; then echo none
  elif [[ "$FULL_CONFIG" -eq 1 ]]; then echo full
  else echo targeted; fi
}

# ------------------ backup --------------------------------------------------

backup_prefix() {
  local name=$1 prefix="$PREFIXES_ROOT/$1"
  [[ -d "$prefix" ]] || die "Prefixo nao encontrado: $prefix"
  local matches desc
  matches=$(read_matches_for_prefix "$prefix" || true)
  desc="$(prefix_game_label "$prefix")"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "(dry-run) Backup de: $name ($desc)"
    info "  prefixo: $prefix/ -> <snapshot>/prefix/"
    if [[ "$NO_CONFIG" -eq 0 ]]; then
      if [[ "$FULL_CONFIG" -eq 1 ]]; then
        info "  config: $HEROIC_CONFIG/ (inteira)"
      else
        local file app wname wtype wbin env
        while IFS=$'\t' read -r file app wname wtype wbin env; do
          [[ -z "$file" ]] && continue
          info "  config: $(basename "$file") (app=$app)"
          [[ -n "$wbin" ]] && info "  proton: $(basename "$(dirname "$wbin")")"
        done <<< "$matches"
      fi
    fi
    [[ "$NO_STATE" -eq 0 && -d "$HEROIC_STATE" ]] && info "  state: $HEROIC_STATE/"
    return 0
  fi

  info "Backup de: $name ($desc)"
  local snap ld
  snap=$(create_snapshot_dir "$name")
  : > "$snap/backup.log"

  info "  Copiando prefixo..."
  ld=$(latest_dir_with_path "prefix" "$name" || true)
  [[ "$NO_LINK" -eq 1 ]] && ld=""
  rsync_one "$prefix/" "$snap/prefix/" "$ld" "${EXCLUDES[@]}" >>"$snap/backup.log" 2>&1

  if [[ "$NO_CONFIG" -eq 0 ]]; then
    if [[ "$FULL_CONFIG" -eq 1 ]]; then
      info "  Copiando ~/.config/heroic inteira..."
      rsync_one "$HEROIC_CONFIG/" "$snap/heroic-config/" "" >>"$snap/backup.log" 2>&1
    else
      info "  Copiando config do prefixo..."
      copy_targeted_config "$snap" "$matches" "$desc"
    fi
  fi

  if [[ "$NO_STATE" -eq 0 && -d "$HEROIC_STATE" ]]; then
    info "  Copiando logs..."
    rsync_one "$HEROIC_STATE/" "$snap/heroic-state/" "" >>"$snap/backup.log" 2>&1
  fi

  write_meta "$snap" kind prefix
  write_meta "$snap" slug "$name"
  write_meta "$snap" path "$prefix"
  write_meta "$snap" label "$desc"
  write_meta "$snap" config_mode "$(config_mode_str)"
  write_meta "$snap" apps "${CFG_APPS[*]:-}"
  write_meta "$snap" protons "${CFG_PROTONS[*]:-}"

  {
    echo "Snapshot: $(basename "$snap")"
    echo "Data: $(date)"
    echo "Tipo: prefixo Wine"
    echo "Prefixo: $name"
    echo "Jogo: $desc"
    echo "Config: $(config_mode_str)"
    [[ ${#CFG_APPS[@]} -gt 0 ]] && echo "Apps: ${CFG_APPS[*]}"
    [[ ${#CFG_PROTONS[@]} -gt 0 ]] && echo "Protons: ${CFG_PROTONS[*]}"
    echo "Tamanho: $(du -sh "$snap" 2>/dev/null | cut -f1)"
  } > "$snap/INFO.txt"

  create_restore_link "$snap"
  create_tar "$snap"
  prune_old "$name"
  info "Snapshot criado: $snap"
}

backup_all() {
  local snap name ld count=0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "(dry-run) Backup de TODOS os prefixos:"
    for name in $(list_prefix_names); do
      info "  $name -> <snapshot>/prefixes/$name/"
    done
    [[ "$NO_CONFIG" -eq 0 ]] && info "  config: $HEROIC_CONFIG/ (inteira)"
    return 0
  fi

  info "Backup de TODOS os prefixos"
  snap=$(create_snapshot_dir "heroic-all")
  : > "$snap/backup.log"

  for name in $(list_prefix_names); do
    info "  Prefixo: $name"
    ld=$(latest_dir_with_path "prefixes/$name" "heroic-all" || true)
    [[ "$NO_LINK" -eq 1 ]] && ld=""
    rsync_one "$PREFIXES_ROOT/$name/" "$snap/prefixes/$name/" "$ld" "${EXCLUDES[@]}" >>"$snap/backup.log" 2>&1
    count=$((count+1))
  done
  info "  $count prefixo(s)"

  if [[ "$NO_CONFIG" -eq 0 ]]; then
    info "  Copiando ~/.config/heroic inteira..."
    rsync_one "$HEROIC_CONFIG/" "$snap/heroic-config/" "" >>"$snap/backup.log" 2>&1
  fi
  if [[ "$NO_STATE" -eq 0 && -d "$HEROIC_STATE" ]]; then
    rsync_one "$HEROIC_STATE/" "$snap/heroic-state/" "" >>"$snap/backup.log" 2>&1
  fi

  write_meta "$snap" kind all
  write_meta "$snap" slug "heroic-all"
  write_meta "$snap" label "todos os prefixos"
  write_meta "$snap" config_mode "$([[ "$NO_CONFIG" -eq 1 ]] && echo none || echo full)"
  write_meta "$snap" prefix_count "$count"

  {
    echo "Snapshot: $(basename "$snap")"
    echo "Data: $(date)"
    echo "Tipo: TODOS os prefixos"
    echo "Prefixos: $count"
    echo "Tamanho: $(du -sh "$snap" 2>/dev/null | cut -f1)"
  } > "$snap/INFO.txt"

  create_restore_link "$snap"
  create_tar "$snap"
  prune_old "heroic-all"
  info "Snapshot criado: $snap"
}

backup_config_only() {
  local snap
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "(dry-run) $HEROIC_CONFIG/ -> <snapshot>/heroic-config/"
    return 0
  fi
  info "Backup da config do Heroic"
  snap=$(create_snapshot_dir "heroic-config")
  : > "$snap/backup.log"

  rsync_one "$HEROIC_CONFIG/" "$snap/heroic-config/" "" >>"$snap/backup.log" 2>&1
  if [[ "$NO_STATE" -eq 0 && -d "$HEROIC_STATE" ]]; then
    rsync_one "$HEROIC_STATE/" "$snap/heroic-state/" "" >>"$snap/backup.log" 2>&1
  fi

  write_meta "$snap" kind config
  write_meta "$snap" slug "heroic-config"
  write_meta "$snap" label "config Heroic"
  write_meta "$snap" config_mode full

  {
    echo "Snapshot: $(basename "$snap")"
    echo "Data: $(date)"
    echo "Tipo: config Heroic"
    echo "Tamanho: $(du -sh "$snap" 2>/dev/null | cut -f1)"
  } > "$snap/INFO.txt"

  create_restore_link "$snap"
  create_tar "$snap"
  prune_old "heroic-config"
  info "Snapshot criado: $snap"
}

backup_path() {
  local path=$1
  [[ -d "$path" ]] || die "Pasta nao encontrada: $path"
  local real slug
  real=$(realpath "$path")
  slug=$(sanitize "$(basename "$real")")
  [[ -z "$slug" ]] && slug="path"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "(dry-run) $real/ -> <snapshot>/folder/"
    return 0
  fi

  info "Backup de: $real"
  local snap
  snap=$(create_snapshot_dir "$slug")
  : > "$snap/backup.log"
  rsync_one "$real/" "$snap/folder/" "" "${EXCLUDES[@]}" >>"$snap/backup.log" 2>&1

  write_meta "$snap" kind folder
  write_meta "$snap" slug "$slug"
  write_meta "$snap" path "$real"
  write_meta "$snap" label "pasta: $(basename "$real")"
  write_meta "$snap" config_mode none

  {
    echo "Snapshot: $(basename "$snap")"
    echo "Data: $(date)"
    echo "Tipo: pasta avulsa"
    echo "Origem: $real"
    echo "Tamanho: $(du -sh "$snap" 2>/dev/null | cut -f1)"
  } > "$snap/INFO.txt"

  create_restore_link "$snap"
  create_tar "$snap"
  prune_old "$slug"
  info "Snapshot criado: $snap"
}

# ------------------ listar / restaurar (delega ao helper) -------------------

do_list_main() {
  resolve_dest
  echo "${c_bld}Snapshots em $DEST_BASE:${c_rst}"
  local d name label cm any=0
  while IFS= read -r d; do
    any=1; name=$(basename "$d")
    if [[ -f "$d/META.txt" ]]; then
      label=$(sed -n 's/^label=//p' "$d/META.txt")
      cm=$(sed -n 's/^config_mode=//p' "$d/META.txt")
      [[ -n "$cm" ]] && label="$label  [config: $cm]"
    else
      label="(formato antigo)"
    fi
    printf '  %-34s %-8s %s\n' "$name" "$(du -sh "$d" 2>/dev/null | cut -f1)" "$label"
  done < <(snapshot_dirs | sort -r)
  [[ "$any" -eq 0 ]] && echo "  (nenhum)"
  echo
  echo "Uso real: $(du -sh "$DEST_BASE" 2>/dev/null | cut -f1)"
  df -h "$DEST_BASE" 2>/dev/null | awk 'NR==2{print "Livre: "$4}'
}

delegate_restore_helper() {
  resolve_dest
  ensure_restore_helper
  local helper="$DEST_BASE/restaurar-backup.sh"
  [[ -f "$helper" ]] || die "Helper nao disponivel: $helper"
  local args=(-d "$DEST_BASE")
  [[ "$FORCE" -eq 1 ]] && args+=(--force)
  exec bash "$helper" "${args[@]}" "$@"
}

# ------------------ menu ----------------------------------------------------

menu() {
  resolve_dest
  ensure_restore_helper

  echo "${c_bld}Backup do Heroic - o que salvar?${c_rst}"
  echo "  1) Um prefixo especifico (jogo + config + Proton)"
  echo "  2) Todos os prefixos + config inteira"
  echo "  3) So a config do Heroic"
  echo "  4) Uma pasta qualquer"
  echo "  0) sair"
  echo
  read -r -p "Escolha: " ans
  case "$ans" in
    1)
      local names=() name i=1 num
      mapfile -t names < <(list_prefix_names)
      [[ ${#names[@]} -gt 0 ]] || die "Nenhum prefixo em $PREFIXES_ROOT"
      echo
      for name in "${names[@]}"; do
        printf '  %2d) %-30s %s\n' "$i" "$name" "$(prefix_game_label "$PREFIXES_ROOT/$name")"
        i=$((i+1))
      done
      echo "   0) voltar"
      echo
      read -r -p "Numero: " num
      [[ -z "$num" || "$num" == "0" ]] && exit 0
      [[ "$num" =~ ^[0-9]+$ && "$num" -ge 1 && "$num" -le ${#names[@]} ]] || die "Invalido: $num"
      backup_prefix "${names[$((num-1))]}"
      ;;
    2) backup_all ;;
    3) backup_config_only ;;
    4)
      local pth
      read -r -p "Caminho da pasta: " pth
      [[ -z "$pth" ]] && die "Vazio"
      backup_path "$pth"
      ;;
    0|"") exit 0 ;;
    *) die "Invalido: $ans" ;;
  esac
}

# ------------------ argumentos ----------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage ;;
    -n|--dry-run)     DRY_RUN=1 ;;
    -d|--dest)        DEST_BASE="$2"; shift ;;
    -k|--keep)        KEEP="$2"; shift ;;
    --no-config)      NO_CONFIG=1 ;;
    --no-proton)      NO_PROTON=1 ;;
    --full-config)    FULL_CONFIG=1 ;;
    --no-state)       NO_STATE=1 ;;
    --no-tar)         NO_TAR=1 ;;
    --full)           NO_LINK=1 ;;
    -f|--force)       FORCE=1 ;;
    --menu)           FORCE_MENU=1 ;;
    --list)           ACTION="list" ;;
    --all)            ACTION="all" ;;
    --config-only)    ACTION="config-only" ;;
    --prefix)         ACTION="prefix"; TARGET="$2"; shift ;;
    --path)           ACTION="path";   TARGET="$2"; shift ;;
    --verify)         ACTION="verify";  TARGET="${2:-}"; [[ -n "${2:-}" ]] && shift ;;
    --restore)        ACTION="restore"; TARGET="${2:-}"; [[ -n "${2:-}" ]] && shift ;;
    *)                die "Opcao desconhecida: $1 (use --help)" ;;
  esac
  shift
done

resolve_dest

case "$ACTION" in
  list)     do_list_main ;;
  verify)   delegate_restore_helper --verify "$TARGET" ;;
  restore)  delegate_restore_helper --restore "$TARGET" ;;
  prefix)
    check_idle
    [[ -n "$TARGET" ]] || die "--prefix precisa do nome"
    backup_prefix "$TARGET" ;;
  all)
    check_idle
    backup_all ;;
  config-only)
    check_idle
    backup_config_only ;;
  path)
    check_idle
    [[ -n "$TARGET" ]] || die "--path precisa do caminho"
    backup_path "$TARGET" ;;
  backup)
    if [[ "$FORCE_MENU" -eq 1 || -t 0 ]]; then
      check_idle
      menu
    else
      die "Sem terminal. Use --prefix NOME, --all, --config-only, --path DIR, --list, --verify NOME ou --restore NOME."
    fi ;;
  *)
    die "Acao desconhecida: $ACTION" ;;
esac

if [[ "$DRY_RUN" -eq 1 ]]; then
  info "(dry-run) Fim da simulacao. Nada foi escrito em $DEST_BASE."
  rm -rf "/tmp/heroic-dryrun-$$"
fi
