* ==============================================================================
* MASTER ORCHESTRATION SCRIPT: SSRN-6477740 REPLICATION SUITE
* Purpose: Executes full Data Audit & EDA followed by Master Regression Suite
* Output Destination: replication_package/results/ (and ~/Documents/ if available)
* Requirements: Stata 16-19 (BE, SE, or MP)
* ==============================================================================

clear all
macro drop _all
matrix drop _all
scalar drop _all
set more off
capture log close _all

* Resilient working directory resolution to ensure we are in src/stata
cap confirm file "run_all.do"
if _rc != 0 {
    cap cd "replication_package/src/stata"
    if _rc != 0 {
        cap cd "src/stata"
    }
}
local src_dir `c(pwd)'

* Pre-flight: Harmonize dataset variables
cap do "fix_datasets.do"
cd "`src_dir'"

di _newline "========================================================================"
di "PHASE 1 OF 4: COMPREHENSIVE DATA DUE DILIGENCE & EDA"
di "========================================================================"
do "00_data_audit_and_eda.do"

* Return to source directory between phases
cd "`src_dir'"

di _newline "========================================================================"
di "PHASE 2 OF 4: 20-SECTOR BASELINE & LEVERAGE AUDIT (TABLES 1 THROUGH 6)"
di "========================================================================"
do "run_all.do"

* Return to source directory between phases
cd "`src_dir'"

di _newline "========================================================================"
di "PHASE 3 OF 4: FULL UNIVERSE RECONSTRUCTION (HS 84 & 85, 133 SECTORS)"
di "========================================================================"
do "01_multilateral_hs84_hs85_estimation.do"

* Return to source directory between phases
cd "`src_dir'"

di _newline "========================================================================"
di "PHASE 4 OF 4: COMPARATIVE RDiT SPLINES (HAUSMAN & RAPSON 2018)"
di "========================================================================"
do "02_hausman_rapson_rdit_splines.do"

* Return to source directory between phases
cd "`src_dir'"

di "========================================================================"
di "The complete replication reports are saved as plain text in:"
di "  [1] replication_package/results/data_audit_and_eda_log.txt"
di "  [2] replication_package/results/stata_replication_log.txt"
di "  [3] replication_package/results/multilateral_hs84_hs85_log.txt"
di "  [4] replication_package/results/rdit_splines_log.txt"
di "========================================================================"
