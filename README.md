# Swiss IPTV + EPG for Jellyfin

Fully automated Swiss IPTV setup for Jellyfin. A GitHub Actions workflow runs twice daily, fetching free IPTV streams and scraping EPG (TV guide) data.

## Files

| File | Description | Source |
|------|-------------|--------|
| `swiss.m3u` | IPTV channel list (auto-updated) | [iptv-org/iptv](https://github.com/iptv-org/iptv) |
| `epg_swiss.xml` | TV guide / EPG data (auto-updated) | [tvepg.eu](https://tvepg.eu/de/switzerland) |
| `scrape_epg.sh` | Scraper script | — |

## Jellyfin Setup

### 1. Add Tuner (M3U)
- Dashboard → Live TV → Add Tuner
- Type: **M3U Tuner**
- URL: `https://raw.githubusercontent.com/0n1cOn3/SwissIPTV-EPG-Jellyfin/main/swiss.m3u`

### 2. Add EPG (XMLTV)
- Dashboard → Live TV → Add TV Guide Data Provider
- Type: **XMLTV**
- URL: `https://raw.githubusercontent.com/0n1cOn3/SwissIPTV-EPG-Jellyfin/main/epg_swiss.xml`

### 3. Refresh
- Dashboard → Live TV → Refresh Guide Data

## Channel Coverage

- **~85 streams** from iptv-org (free, legal, community-maintained)
- **~360 EPG channels** from tvepg.eu (Swiss + DACH + international)
- `tvg-id` values are auto-mapped so streams match their EPG entries

## Optional: Local Fallback (Synology NAS or other systems)

```bash
# Copy script to NAS
scp scrape_epg.sh user@nas:/volume1/Multimedia/

# Run manually
bash /volume1/Multimedia/scrape_epg.sh

# Or add cronjob
0 5 * * * /usr/bin/bash /volume1/Multimedia/scrape_epg.sh >> /volume1/Multimedia/epg.log 2>&1
```

Then point Jellyfin to local files:
- M3U: `/volume1/Multimedia/swiss.m3u`
- EPG: `/volume1/Multimedia/epg_swiss.xml`
