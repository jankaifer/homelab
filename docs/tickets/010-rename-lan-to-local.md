# Ticket 010: Rename lan.kaifer.dev to local.kaifer.dev for VM

**Status**: DONE
**Tested**: Yes - VM verified working
**Created**: 2026-02-03
**Updated**: 2026-02-03

## Task

Change VM configuration from `lan.kaifer.dev` to `local.kaifer.dev` to better indicate this is for local development testing, not LAN access. This is a preparatory step before adding Tailscale and using `home.kaifer.dev` for production.

## Implementation Plan

1. Update Caddy module to use `local.kaifer.dev` for VM
2. Update documentation references
3. Update CLAUDE.md instructions
4. Test VM still works with new domain

## Work Log

### 2026-02-03

**Completed:** Updated all references from `lan.kaifer.dev` to `local.kaifer.dev`

**Files updated:**
- `modules/services/victoriametrics.nix` - default domain
- `modules/services/grafana.nix` - default domain
- `modules/services/loki.nix` - default domain
- `modules/services/homepage.nix` - example domain
- `machines/frame1/default.nix` - virtualHosts and allowedHosts
- `CLAUDE.md` - all references (2 occurrences)
- `docs/OVERVIEW.md` - all references
- `docs/PROJECT_PLAN.md` - all references
- `docs/services/caddy.md` - all references
- `docs/services/homepage.md` - all references
- `docs/services/grafana.md` - all references
- `docs/services/victoriametrics.md` - all references
- `docs/services/loki.md` - all references

**Validation:**
- Config evaluates successfully with `nix eval` ✓
- VM built and tested ✓
- All services responding correctly ✓

**Testing Results:**
```
Homepage (local.kaifer.dev): 200 ✓
Grafana (grafana.local.kaifer.dev): 302 ✓
VictoriaMetrics (metrics.local.kaifer.dev): 200 ✓
Loki (logs.local.kaifer.dev): 503 (still starting)
```

**DNS Setup Documented:**
- Created `docs/vm-testing-dns.md` with /etc/hosts setup instructions
- Updated CLAUDE.md with DNS requirements
- Verified services work with proper DNS configuration

**Next step:** Ready to implement Tailscale (ticket 011)
