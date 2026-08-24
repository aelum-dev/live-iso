#!/usr/bin/env bash
#
# Run the full AestheticOS build pipeline.
# Usage: docker compose run --rm builder [step]
#   step: 1 | 2 | 3 | 4 | 5 | all (default)
#

set -euo pipefail

STEP="${1:-all}"
PROJECT="/project"

log() { echo "==> $*"; }
ok()  { echo "  ✓ $*"; }
err() { echo "  ✗ $*"; }

run_step() {
    local step_num="$1"
    local script="/build-scripts/step-${step_num}.sh"
    
    if [[ ! -f "$script" ]]; then
        err "Step ${step_num} script not found: ${script}"
        exit 1
    fi
    
    bash "$script" "$PROJECT"
}

case "$STEP" in
    1)
        log "Step 1/5: Download official packages"
        run_step 1
        ;;
    2)
        log "Step 2/5: Download AUR packages"
        run_step 2
        ;;
    3)
        log "Step 3/5: Build AUR packages"
        run_step 3
        ;;
    4)
        log "Step 4/5: Create offline repository"
        run_step 4
        ;;
    5)
        log "Step 5/5: Build ISO"
        run_step 5
        ;;
    all)
        log "Running full AestheticOS build pipeline"
        echo ""
        run_step 1
        echo ""
        run_step 2
        echo ""
        run_step 3
        echo ""
        run_step 4
        echo ""
        run_step 5
        echo ""
        log "Build pipeline complete!"
        
        # Show output
        ISO=$(ls -t "${PROJECT}/output"/*.iso 2>/dev/null | head -1)
        if [[ -n "$ISO" ]]; then
            ISO_SIZE=$(du -h "$ISO" | cut -f1)
            echo ""
            ok "ISO: $ISO ($ISO_SIZE)"
        fi
        ;;
    *)
        echo "Usage: $0 [1|2|3|4|5|all]"
        echo ""
        echo "  1  - Download official packages"
        echo "  2  - Download AUR packages"
        echo "  3  - Build AUR packages"
        echo "  4  - Create offline repository"
        echo "  5  - Build ISO"
        echo "  all - Run full pipeline (default)"
        exit 1
        ;;
esac
