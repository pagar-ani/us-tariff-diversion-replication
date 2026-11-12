* ==============================================================================
* MASTER ORCHESTRATION SCRIPT: US TARIFF DIVERSION REPLICATION SUITE
* Purpose: Dynamic Panel Construction -> Data Audit -> Multilateral Estimation -> RDiT Splines
* Output Destination: replication_package/results/
* Requirements: Stata 16 or newer (BE, SE, or MP)
* ==============================================================================

clear all
macro drop _all
matrix drop _all
scalar drop _all
set more off
capture log close _all

* Resilient working directory resolution to ensure execution from src/stata
cap confirm file "00_build_panel_from_comtrade.do"
if _rc != 0 {
    cap cd "replication_package/src/stata"
    if _rc != 0 {
        cap cd "src/stata"
        if _rc != 0 {
            cap cd "../src/stata"
        }
    }
}
local src_dir `c(pwd)'

* Verify and install all required SSC packages upfront
foreach pkg in require ftools reghdfe ppmlhdfe {
    cap which `pkg'
    if _rc {
        di "Installing `pkg' from SSC..."
        cap ssc install `pkg', replace
    }
}
cap ftools, compile
cap reghdfe, compile
cap mata: mata mlib index

di _newline "========================================================================"
di "PHASE 0: DYNAMIC RAW PANEL CONSTRUCTION FROM UN COMTRADE"
di "========================================================================"
do "00_build_panel_from_comtrade.do"
cd "`src_dir'"

di _newline "========================================================================"
di "PHASE 1: COMPREHENSIVE DATA AUDIT & DESCRIPTIVE STATISTICS"
di "========================================================================"
do "00_data_audit_and_eda.do"
cd "`src_dir'"

di _newline "========================================================================"
di "PHASE 2: FULL UNIVERSE ESTIMATION (HS CHAPTERS 84 & 85, 133 HEADINGS)"
di "========================================================================"
do "01_multilateral_hs84_hs85_estimation.do"
cd "`src_dir'"

di _newline "========================================================================"
di "PHASE 3: COMPARATIVE RDiT SPLINES & STOCKPILING DYNAMICS (HAUSMAN & RAPSON 2018)"
di "========================================================================"
do "02_hausman_rapson_rdit_splines.do"
cd "`src_dir'"

di "========================================================================"
di "The complete replication reports are saved as plain text in:"
di "  [1] replication_package/results/build_panel_from_comtrade_log.txt"
di "  [2] replication_package/results/data_audit_and_eda_log.txt"
di "  [3] replication_package/results/multilateral_hs84_hs85_log.txt"
di "  [4] replication_package/results/rdit_splines_log.txt"
di "========================================================================"
