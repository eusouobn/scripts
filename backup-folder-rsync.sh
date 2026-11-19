#!/usr/bin/env bash
#
# backup-folder.sh - Backup de pastas com rsync + verificacao de integridade
#                    via sha256sum, escolhendo pasta origem, dispositivo
#                    destino e subpasta destino de forma interativa.
#
# Uso rapido:
#   backup-folder.sh                                menu na pasta atual
#   backup-folder.sh --src /home/bn/Backups         menu, outra pasta base
#   backup-folder.sh --src DIR --all                todas, ainda pergunta device
#   backup-folder.sh --src DIR --folder X \
#       --device /dev/sda1 --dest-sub Heroic/Backup sem perguntas
#   backup-folder.sh --src DIR --all --dry-run      so simula
#   backup-folder.sh --src DIR --list               so lista subpastas
#
# Fluxo (modo backup):
#   1) Lista subpastas de --src (padrao: $PWD), com tamanho.
#   2) Pergunta quais copiar (1,2,3 / 1 2 3 / 'a' para todas / 'q' sair).
#   3) Lista particoes (lsblk) que nao sao de sistema, com label/tipo/tamanho/
#      ponto de montagem. Pergunta qual usar; monta com udisksctl se preciso
#      (fallback: sudo mount em /run/media/$USER/<label>).
#   4) Lista subpastas no destino; pergunta qual usar, ou cria nova, ou '.' p/ raiz.
#   5) Copia com rsync -aHAX --numeric-ids --info=progress2 (uma pasta por vez).
#   6) Gera <dest>/<nome>/sha256sums.txt a partir da origem.
#   7) Verifica com sha256sum -c <manifesto> dentro do destino.
#
# Opcoes:
#   -n, --dry-run           simula, nao escreve nada
#   --src DIR               pasta base (padrao: $PWD)
#   --folder NOME           backup so dessa subpasta (pode repetir)
#   --all                   backup de todas as subpastas
#   --device DEV            dispositivo alvo (pula o menu)
#   --dest-sub DIR          subpasta no dispositivo (pula o menu; cria se faltar)
#   --hash CMD              comando de hash (padrao: sha256sum; use md5sum,
#                           sha512sum, b2sum...)
#   --no-verify             pula a verificacao sha256
#   --mirror                passa --delete ao rsync (espelha, apaga extras)
#   -q, --quiet             so o resumo final
#   -f, --force             continua mesmo com pouco espaco livre
#   --list                  so lista subpastas de --src e sai
#   --verify-only           so verifica contra manifesto existente
#   -h, --help              esta ajuda
#
set -euo pipefail
umask 077

# ------------------------------- configuracao --------------------------------
SRC_DIR="${PWD}"
DEST_MOUNT=""
DEST_SUB=""
DEVICE=""
HASH_CMD="${HASH_CMD:-sha256sum}"
MANIFEST_NAME="sha256sums.txt"
DRY_RUN=0
NO_VERIFY=0
QUIET=0
FORCE=0
MIRROR=0
SELECT_ALL=0
ACTION="backup"
SELECTIONS=()
TMP_MANIFEST=""

# ---------------------------------- helpers ----------------------------------
c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_bld=$'\033[1m'; c_rst=$'\033[0m'
info()  { [[ "$QUIET" -eq 1 ]] || printf '%s[*]%s %s\n' "$c_grn" "$c_rst" "$*"; }
ok()    { [[ "$QUIET" -eq 1 ]] || printf '%s[+]%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$c_yel" "$c_rst" "$*" >&2; }
die()   { printf '%s[x]%s %s\n' "$c_red" "$c_rst" "$*" >&2; exit 1; }

cleanup() {
  [[ -n "$TMP_MANIFEST" && -f "$TMP_MANIFEST" ]] && rm -f "$TMP_MANIFEST" || true
}
trap cleanup EXIT

usage() {
  awk 'NR>1 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print } else { exit } }' "$0"
  exit 0
}

human() { numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "$1 bytes"; }

resolve_src() {
  [[ -d "$SRC_DIR" ]] || die "Pasta base nao existe: $SRC_DIR"
  SRC_DIR=$(realpath "$SRC_DIR")
}

list_subfolders() {
  find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# Lista particoes (type=part, fstype nao vazio, nao swap, fora de / e /boot*)
# saida: NAME<TAB>LABEL<TAB>FSTYPE<TAB>SIZE<TAB>MOUNTPOINT
list_devices() {
  command -v lsblk >/dev/null || die "lsblk nao encontrado (pacote util-linux)."
  lsblk -Pno NAME,LABEL,FSTYPE,SIZE,TYPE,MOUNTPOINT 2>/dev/null | \
    awk -F'"' '
      {
        name=label=fstype=size=type=mount=""
        for (i=1; i<NF; i+=2) {
          key=$i; gsub(/[[:space:]=]+/, "", key)
          val=$(i+1)
          if      (key == "NAME")       name=val
          else if (key == "LABEL")      label=val
          else if (key == "FSTYPE")     fstype=val
          else if (key == "SIZE")       size=val
          else if (key == "TYPE")       type=val
          else if (key == "MOUNTPOINT") mount=val
        }
        if (type != "part") next
        if (fstype == "" || fstype == "swap") next
        if (mount == "/" || mount ~ /^\/boot/) next
        printf "%s\t%s\t%s\t%s\t%s\n", name, label, fstype, size, mount
      }'
}

# Retorna o mountpoint (stdout) ou falha se nao conseguiu montar
get_mountpoint() {
  local dev=$1 mp
  mp=$(lsblk -Pno MOUNTPOINT "$dev" 2>/dev/null \
         | sed -n 's/^MOUNTPOINT="\(.*\)"$/\1/p' | head -1)
  if [[ -n "$mp" ]]; then
    printf '%s\n' "$mp"; return 0
  fi
  if command -v udisksctl >/dev/null 2>&1; then
    udisksctl mount -b "$dev" >/dev/null 2>&1 || true
    mp=$(lsblk -Pno MOUNTPOINT "$dev" 2>/dev/null \
           | sed -n 's/^MOUNTPOINT="\(.*\)"$/\1/p' | head -1)
  fi
  if [[ -z "$mp" ]]; then
    local label mnt
    label=$(lsblk -Pno LABEL "$dev" 2>/dev/null \
              | sed -n 's/^LABEL="\(.*\)"$/\1/p' | head -1)
    [[ -z "$label" ]] && label=$(basename "$dev")
    mnt="/run/media/$USER/$label"
    mkdir -p "$mnt" 2>/dev/null || true
    if sudo mount "$dev" "$mnt" 2>/dev/null; then
      mp="$mnt"
    fi
  fi
  if [[ -n "$mp" ]]; then
    printf '%s\n' "$mp"; return 0
  fi
  return 1
}

check_dest_free() {
  local dest_root=$1 src=$2
  local need avail
  need=$(du -sb "$src" 2>/dev/null | cut -f1 || echo 0)
  avail=$(df -B1 --output=avail "$dest_root" 2>/dev/null | tail -1 | tr -d ' ' || echo 0)
  [[ -z "$need" || -z "$avail" || "$need" -eq 0 || "$avail" -eq 0 ]] && return 0
  if [[ "$avail" -lt "$need" ]]; then
    warn "Espaco insuficiente em $dest_root: precisa $(human "$need"), livre $(human "$avail")"
    [[ "$FORCE" -eq 1 ]] || die "Abortando (use --force para ignorar)."
  fi
}

# -------------------------------- selecao ------------------------------------
select_sources() {
  local folders=() i=1 ans
  mapfile -t folders < <(list_subfolders)
  [[ ${#folders[@]} -gt 0 ]] || die "Nenhuma subpasta em $SRC_DIR"

  echo "${c_bld}Pastas em $SRC_DIR:${c_rst}"
  local f size
  for f in "${folders[@]}"; do
    size=$(du -sh "$SRC_DIR/$f" 2>/dev/null | cut -f1)
    printf '  %2d) %-45s %s\n' "$i" "$f" "$size"
    i=$((i+1))
  done
  echo
  echo "Digite: numero(s) separados por virgula/espaco, 'a' para todas, ou 'q' para sair."
  read -r -p "Escolha: " ans
  [[ -z "$ans" || "$ans" == "q" || "$ans" == "Q" ]] && exit 0

  if [[ "$ans" =~ ^[aA]$ ]]; then
    SELECT_ALL=1
    SELECTIONS=("${folders[@]}")
    return 0
  fi

  local tok
  for tok in $(echo "$ans" | tr ',' ' '); do
    [[ "$tok" =~ ^[0-9]+$ ]] || die "Invalido: $tok"
    [[ "$tok" -ge 1 && "$tok" -le ${#folders[@]} ]] || die "Fora da lista: $tok"
    SELECTIONS+=("${folders[$((tok-1))]}")
  done
  [[ ${#SELECTIONS[@]} -gt 0 ]] || die "Nada selecionado."
}

select_device() {
  if [[ -n "$DEVICE" ]]; then
    local mp
    mp=$(get_mountpoint "$DEVICE") || die "Nao consegui montar $DEVICE"
    DEST_MOUNT="$mp"
    ok "Dispositivo $DEVICE -> $DEST_MOUNT"
    return 0
  fi

  local rows=() i=1 ans
  mapfile -t rows < <(list_devices)
  [[ ${#rows[@]} -gt 0 ]] || die "Nenhuma particao disponivel. Conecte um dispositivo."

  echo "${c_bld}Dispositivos disponiveis:${c_rst}"
  local dev label fstype size mount dlabel dmount
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r dev label fstype size mount <<< "$row"
    dlabel="${label:-(sem label)}"
    dmount="${mount:-(nao montado)}"
    printf '  %2d) %-16s %-22s %-6s %-8s %s\n' \
      "$i" "$dev" "$dlabel" "$fstype" "$size" "$dmount"
    i=$((i+1))
  done
  echo
  read -r -p "Escolha o dispositivo (numero): " ans
  [[ "$ans" =~ ^[0-9]+$ && "$ans" -ge 1 && "$ans" -le ${#rows[@]} ]] \
    || die "Invalido: $ans"
  IFS=$'\t' read -r dev label fstype size mount <<< "${rows[$((ans-1))]}"

  info "Preparando $dev..."
  local mp
  mp=$(get_mountpoint "$dev") || die "Nao consegui montar $dev"
  DEST_MOUNT="$mp"
  ok "$dev -> $DEST_MOUNT"
}

select_dest_sub() {
  local mp="$DEST_MOUNT"
  if [[ -n "$DEST_SUB" ]]; then
    mkdir -p "$mp/$DEST_SUB" || die "Nao criei $mp/$DEST_SUB"
    ok "Subpasta destino: $mp/$DEST_SUB"
    return 0
  fi

  local folders=() i=1 ans
  mapfile -t folders < <(find "$mp" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort)

  echo "${c_bld}Subpastas em $mp:${c_rst}"
  if [[ ${#folders[@]} -gt 0 ]]; then
    local f
    for f in "${folders[@]}"; do
      printf '  %2d) %s\n' "$i" "$f"
      i=$((i+1))
    done
  else
    echo "  (nenhuma)"
  fi
  echo "   n) criar nova pasta"
  echo "   .) usar a raiz do dispositivo (sem subpasta)"
  echo
  read -r -p "Escolha: " ans

  case "$ans" in
    n|N)
      read -r -p "Nome da nova pasta: " ans
      [[ -z "$ans" ]] && die "Nome vazio"
      DEST_SUB="$ans"
      mkdir -p "$mp/$DEST_SUB" || die "Nao criei $mp/$DEST_SUB"
      ;;
    .|"")
      DEST_SUB=""
      ;;
    *)
      [[ "$ans" =~ ^[0-9]+$ && "$ans" -ge 1 && "$ans" -le ${#folders[@]} ]] \
        || die "Invalido: $ans"
      DEST_SUB="${folders[$((ans-1))]}"
      ;;
  esac
  ok "Destino: $mp${DEST_SUB:+/$DEST_SUB}"
}

# ------------------------------ copia + verify -------------------------------
RSYNC=(rsync -aHAX --numeric-ids --human-readable --info=progress2)
EXCLUDES=(
  --exclude='.Trash-*'
  --exclude='.Trashes'
  --exclude='*.tmp'
  --exclude='*.lock'
)

verify_one() {                        # verify_one DEST MANIFEST TOTAL
  local dest=$1 manifest=$2 total=$3
  info "   Verificando integridade ($total arquivo(s))..."
  local out
  if out=$( cd "$dest" && "$HASH_CMD" -c "$manifest" 2>&1 ); then
    ok "   Integridade OK: $total arquivo(s) conferem"
  else
    printf '%s\n' "$out" | grep -v ': OK$' >&2
    die "   Verificacao FALHOU em $dest"
  fi
}

do_backup_one() {                     # do_backup_one NOME
  local name=$1
  local src="$SRC_DIR/$name"
  local dest_root="$DEST_MOUNT${DEST_SUB:+/$DEST_SUB}"
  local dest="$dest_root/$name"
  local manifest="$dest/$MANIFEST_NAME"

  [[ -d "$src" ]] || die "Nao existe: $src"

  info "Backup: $src"
  info "   -> $dest"
  check_dest_free "$dest_root" "$src"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "   (dry-run) ${RSYNC[*]} ${EXCLUDES[*]} \"$src/\" \"$dest/\""
    [[ "$NO_VERIFY" -eq 0 ]] && info "   (dry-run) $HASH_CMD -c $manifest (em $dest)"
    return 0
  fi

  mkdir -p "$dest" || die "Nao criei $dest"

  local extra=()
  [[ "$MIRROR" -eq 1 ]] && extra+=(--delete)

  info "   Copiando com rsync..."
  local rc=0
  "${RSYNC[@]}" "${EXCLUDES[@]}" "${extra[@]}" "$src/" "$dest/" || rc=$?
  # 24 = "some files vanished before they could be transferred" - tolerado
  if [[ $rc -ne 0 && $rc -ne 24 ]]; then
    die "rsync falhou (codigo $rc)"
  fi

  # gera manifesto SHA256 a partir da origem (relativo, portavel)
  TMP_MANIFEST=$(mktemp /tmp/sha256sums.XXXXXX)
  info "   Gerando checksums de origem..."
  ( cd "$src" && find . -type f ! -name "$MANIFEST_NAME" -print0 \
      | sort -z | xargs -0 -r "$HASH_CMD" ) > "$TMP_MANIFEST"
  local total
  total=$(wc -l < "$TMP_MANIFEST")
  ok "   $total arquivo(s) no manifesto"

  cp "$TMP_MANIFEST" "$manifest"
  rm -f "$TMP_MANIFEST"; TMP_MANIFEST=""

  [[ "$NO_VERIFY" -eq 0 ]] && verify_one "$dest" "$manifest" "$total"
}

do_backup() {
  local name
  for name in "${SELECTIONS[@]}"; do
    do_backup_one "$name"
  done
  ok "Concluido: ${#SELECTIONS[@]} pasta(s) copiada(s) para $DEST_MOUNT${DEST_SUB:+/$DEST_SUB}"
}

# ------------------------------ list / verify-only ---------------------------
do_list() {
  resolve_src
  echo "${c_bld}Subpastas em $SRC_DIR:${c_rst}"
  local f size
  while IFS= read -r f; do
    size=$(du -sh "$SRC_DIR/$f" 2>/dev/null | cut -f1)
    printf '  %-45s %s\n' "$f" "$size"
  done < <(list_subfolders)
}

do_verify_only() {
  local name dest manifest total
  for name in "${SELECTIONS[@]}"; do
    dest="$DEST_MOUNT${DEST_SUB:+/$DEST_SUB}/$name"
    manifest="$dest/$MANIFEST_NAME"
    [[ -f "$manifest" ]] || die "Sem manifesto em $dest (rode um backup antes)."
    total=$(wc -l < "$manifest")
    verify_one "$dest" "$manifest" "$total"
  done
}

# -------------------------------- argumentos ---------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)       usage ;;
    -n|--dry-run)    DRY_RUN=1 ;;
    --src)           SRC_DIR="$2"; shift ;;
    --folder)        SELECTIONS+=("$2"); shift ;;
    --all)           SELECT_ALL=1 ;;
    --device)        DEVICE="$2"; shift ;;
    --dest-sub)      DEST_SUB="$2"; shift ;;
    --hash)          HASH_CMD="$2"; shift ;;
    --no-verify)     NO_VERIFY=1 ;;
    --mirror)        MIRROR=1 ;;
    -q|--quiet)      QUIET=1 ;;
    -f|--force)      FORCE=1 ;;
    --list)          ACTION="list" ;;
    --verify-only)   ACTION="verify-only" ;;
    *)               die "Opcao desconhecida: $1 (use --help)" ;;
  esac
  shift
done

resolve_src

case "$ACTION" in
  list)
    do_list
    exit 0
    ;;
  backup|verify-only)
    if [[ "$SELECT_ALL" -eq 1 && ${#SELECTIONS[@]} -eq 0 ]]; then
      mapfile -t SELECTIONS < <(list_subfolders)
      [[ ${#SELECTIONS[@]} -gt 0 ]] || die "Nenhuma subpasta em $SRC_DIR"
    fi
    [[ ${#SELECTIONS[@]} -gt 0 ]] || select_sources
    select_device
    select_dest_sub
    if [[ "$ACTION" == "verify-only" ]]; then
      do_verify_only
    else
      do_backup
    fi
    ;;
esac
