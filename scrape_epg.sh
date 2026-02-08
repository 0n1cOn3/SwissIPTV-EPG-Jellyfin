#!/usr/bin/env bash
# =============================================================================
# Swiss IPTV EPG Scraper + Stream Fetcher for Jellyfin
#
# 1. Fetches free Swiss IPTV streams from iptv-org/iptv (GitHub, community-maintained)
# 2. Scrapes EPG data from tvepg.eu (all available Swiss channels)
# 3. Remaps tvg-id values so M3U ↔ XMLTV match perfectly
# 4. Outputs Jellyfin-ready swiss.m3u + epg_swiss.xml
#
# PRIMARY: GitHub Actions (.github/workflows/scrape-epg.yml)
#   → M3U:  https://raw.githubusercontent.com/<USER>/<REPO>/main/swiss.m3u
#   → EPG:  https://raw.githubusercontent.com/<USER>/<REPO>/main/epg_swiss.xml
#
# OPTIONAL: Local cronjob on Synology NAS
#   0 5 * * * /usr/bin/bash /volume1/Multimedia/scrape_epg.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EPG_OUTPUT="${SCRIPT_DIR}/epg_swiss.xml"
M3U_OUTPUT="${SCRIPT_DIR}/swiss.m3u"
TMPDIR=$(mktemp -d)
BASE_URL="https://tvepg.eu/de/switzerland/c"
IPTV_SOURCE="https://iptv-org.github.io/iptv/countries/ch.m3u"

TODAY=$(date +%Y%m%d)
YESTERDAY=$(date -d "yesterday" +%Y%m%d 2>/dev/null || date -v-1d +%Y%m%d)
TOMORROW=$(date -d "tomorrow" +%Y%m%d 2>/dev/null || date -v+1d +%Y%m%d)
DAY_AFTER=$(date -d "+2 days" +%Y%m%d 2>/dev/null || date -v+2d +%Y%m%d)

trap 'rm -rf "$TMPDIR"' EXIT

# =============================================================================
# PART 1: Fetch & remap IPTV streams
# =============================================================================

echo "========================================"
echo "[$(date '+%F %T')] PART 1: Fetching IPTV streams"
echo "========================================"

curl -sf --max-time 30 "$IPTV_SOURCE" -o "$TMPDIR/iptv_org.m3u"
STREAM_COUNT=$(grep -c "^#EXTINF" "$TMPDIR/iptv_org.m3u")
echo "Fetched $STREAM_COUNT streams from iptv-org"

# ── Build tvg-id mapping: iptv-org ID → tvepg.eu slug ───────────────────────
# This maps the iptv-org format (e.g. "SRF1.ch@SD") to tvepg.eu slugs (e.g. "srf-1")
# We generate this dynamically by normalizing channel names to slugs

cat > "$TMPDIR/id_map.tsv" <<'MAPEOF'
3sat.de	3sat
BlueSport1.ch	blue-sport-1
BlueSport2.ch	blue-sport-2
BlueZoomD.ch	blue-zoom-d
BlueZoomF.ch	blue-zoom-f
Canal9.ch	canal-9
CanalAlphaJura.ch	canal-alpha-jura
CanalAlphaNeuchatel.ch	canal-alpha-neuchatel
Carac1.ch	carac-1
Carac2.ch	carac-2
Carac3.ch	carac-3
Carac4.ch	carac-4
Carac5.ch	carac-5
ComedyCentral.de	comedy-central
Couleur3.ch	couleur-3
DisneyChannel.de	disney-channel-d
DritaTV.ch	drita-tv
Kanal9.ch	kanal-9
LaTele.ch	la-tele
LemanBleu.ch	leman-bleu-television
Meteonews.ch	meteonews
MoreThanSportsTV.de	more-than-sports-tv
MTV.fr	mtv
ntv.de	n-tv
NRTV.ch	nrtv
RhoneTV.ch	rhone-tv
RSILa1.ch	rsi-la-1
RSILa2.ch	rsi-la-2
RTS1.ch	rts-un
RTS2.ch	rts-deux
SRF1.ch	srf-1
SRFinfo.ch	srf-info
SRFzwei.ch	srf-zwei
StarTV.ch	star-tv
Tele1.ch	tele-1
TeleM1.ch	tele-m1
TeleBarn.ch	tele-barn
TeleBielingue.ch	tele-bielingue
TeleTicino.ch	tele-ticino
TeleZuri.ch	tele-zuri
TV24.ch	tv24
TVRheintal.ch	tv-rheintal
TVM3.ch	tvm3
TVO.ch	tvo
RTLCrime.de	rtl-crime
LCI.fr	la-chaine-info
NDRFernsehenInternational.de	ndr
Nickelodeon.de	nickelodeon
SportdigitalFUSSBALL.de	sport1
MAPEOF

# ── Rewrite M3U with remapped tvg-ids ───────────────────────────────────────

echo "#EXTM3U" > "$M3U_OUTPUT"

# Process iptv-org M3U: remap tvg-id, keep everything else
while IFS= read -r line; do
  # Skip the #EXTM3U header (we already wrote ours)
  [[ "$line" == "#EXTM3U"* ]] && continue

  if [[ "$line" == "#EXTINF:"* ]]; then
    # Extract original tvg-id (format: "SomeName.tld@Quality")
    orig_id=$(echo "$line" | grep -oP 'tvg-id="\K[^"]*' || true)
    # Strip @SD/@HD/@quality suffix for mapping lookup
    base_id="${orig_id%%@*}"

    # Look up slug in our map
    new_id=$(grep -P "^${base_id}\t" "$TMPDIR/id_map.tsv" 2>/dev/null | cut -f2 || true)

    if [ -n "$new_id" ]; then
      # Replace tvg-id with tvepg.eu slug
      line=$(echo "$line" | sed "s|tvg-id=\"[^\"]*\"|tvg-id=\"$new_id\"|")
    else
      # No mapping found — generate slug from base_id: CamelCase → kebab-case
      auto_slug=$(echo "$base_id" | sed 's/\.\(ch\|de\|fr\|it\|uk\|us\|es\|lu\|at\)$//' | \
        sed 's/\([a-z]\)\([A-Z]\)/\1-\2/g' | \
        sed 's/\([A-Za-z]\)\([0-9]\)/\1-\2/g' | \
        sed 's/\([0-9]\)\([A-Z]\)/\1-\2/g' | \
        tr '[:upper:]' '[:lower:]')
      line=$(echo "$line" | sed "s|tvg-id=\"[^\"]*\"|tvg-id=\"$auto_slug\"|")
    fi

    echo "$line" >> "$M3U_OUTPUT"
  else
    # Stream URL or other line — pass through (strip \r)
    echo "$line" | tr -d '\r' >> "$M3U_OUTPUT"
  fi
done < "$TMPDIR/iptv_org.m3u"

FINAL_STREAMS=$(grep -c "^#EXTINF" "$M3U_OUTPUT")
echo "Written $FINAL_STREAMS streams to swiss.m3u"

# =============================================================================
# PART 2: Scrape EPG from tvepg.eu
# =============================================================================

echo ""
echo "========================================"
echo "[$(date '+%F %T')] PART 2: Scraping EPG data"
echo "========================================"

# ── Discover all channel slugs ──────────────────────────────────────────────

MAIN_HTML="$TMPDIR/main.html"
curl -sf --max-time 30 "https://tvepg.eu/de/switzerland" -o "$MAIN_HTML"
grep -oP 'href="/de/switzerland/c/\K[a-z0-9][a-z0-9-]*' "$MAIN_HTML" | sort -u > "$TMPDIR/slugs.txt"
TOTAL_CHANNELS=$(wc -l < "$TMPDIR/slugs.txt")
echo "Discovered $TOTAL_CHANNELS EPG channels on tvepg.eu"

# ── XMLTV header ────────────────────────────────────────────────────────────

cat > "$TMPDIR/header.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tv SYSTEM "xmltv.dtd">
<tv source-info-name="tvepg.eu" generator-info-name="scrape_epg.sh">
EOF

CHANNEL_DEFS="$TMPDIR/channels.xml"
PROGRAMMES="$TMPDIR/programmes.xml"
: > "$CHANNEL_DEFS"
: > "$PROGRAMMES"

# ── Scrape each channel ─────────────────────────────────────────────────────

while IFS= read -r slug; do
  CH_HTML="$TMPDIR/ch.html"
  if ! curl -sf --max-time 15 "$BASE_URL/$slug" -o "$CH_HTML" 2>/dev/null; then
    continue
  fi

  # Extract display name
  DISPLAY_NAME=$(grep -oP '<title>\K[^<|]*' "$CH_HTML" | head -1 | sed 's/ - .*//;s/^TVEpg.eu – //;s/TV Programm //;s/ heute$//' || true)
  [ -z "$DISPLAY_NAME" ] && DISPLAY_NAME="$slug"
  DISPLAY_NAME="${DISPLAY_NAME//&/&amp;}"
  DISPLAY_NAME="${DISPLAY_NAME//</&lt;}"
  DISPLAY_NAME="${DISPLAY_NAME//>/&gt;}"

  # Channel definition
  echo "  <channel id=\"$slug\">" >> "$CHANNEL_DEFS"
  echo "    <display-name>$DISPLAY_NAME</display-name>" >> "$CHANNEL_DEFS"
  echo "  </channel>" >> "$CHANNEL_DEFS"

  # Programme entries
  grep -oP "href=\"/de/switzerland/c/${slug}/\K[0-9]{6}/[^\"]*\"[^>]*title=\"[^\"]*\"" "$CH_HTML" 2>/dev/null | while IFS= read -r match; do
    datecode="${match%%/*}"
    title_raw=$(echo "$match" | grep -oP 'title="\K[^"]*')
    day="${datecode:0:2}"
    hour="${datecode:2:2}"
    min="${datecode:4:2}"
    prog_title="${title_raw#* }"

    case "$day" in
      07) prog_date="$YESTERDAY" ;;
      08) prog_date="$TODAY" ;;
      09) prog_date="$TOMORROW" ;;
      10) prog_date="$DAY_AFTER" ;;
      *)  prog_date="$TODAY" ;;
    esac

    prog_title="${prog_title//&/&amp;}"
    prog_title="${prog_title//</&lt;}"
    prog_title="${prog_title//>/&gt;}"
    prog_title="${prog_title//\"/&quot;}"

    echo "  <programme start=\"${prog_date}${hour}${min}00 +0100\" channel=\"$slug\">"
    echo "    <title lang=\"de\">$prog_title</title>"
    echo "  </programme>"
  done >> "$PROGRAMMES"

  sleep 0.3
done < "$TMPDIR/slugs.txt"

# ── Assemble XMLTV ──────────────────────────────────────────────────────────

{
  cat "$TMPDIR/header.xml"
  cat "$CHANNEL_DEFS"
  cat "$PROGRAMMES"
  echo "</tv>"
} > "$EPG_OUTPUT"

FINAL_CH=$(grep -c '<channel ' "$EPG_OUTPUT" 2>/dev/null || echo 0)
FINAL_PROGS=$(grep -c '<programme' "$EPG_OUTPUT" 2>/dev/null || echo 0)

echo ""
echo "========================================"
echo "[$(date '+%F %T')] DONE"
echo "  Streams: $FINAL_STREAMS channels → swiss.m3u"
echo "  EPG:     $FINAL_CH channels, $FINAL_PROGS programmes → epg_swiss.xml"
echo "========================================"
