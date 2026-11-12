* ==============================================================================
* SCRIPT 00: COMPREHENSIVE DATA AUDIT & DESCRIPTIVE STATISTICS
* Purpose: Descriptive statistics, panel balance, and data integrity checks
* Universe: Full 133-Heading Universe (HS Chapters 84 & 85) and 20-Sector Panel
* Requirements: Stata 16 or newer (BE, SE, or MP)
* ==============================================================================

clear all
set more off
capture log close _all

local start_dir `c(pwd)'

* Resilient working directory resolution (100% relative)
cap confirm file "panel_hs84_hs85_full_universe.dta"
if _rc != 0 {
    cap cd "../../data/stata"
    if _rc != 0 {
        cap cd "data/stata"
        if _rc != 0 {
            cap cd "replication_package/data/stata"
            if _rc != 0 {
                cap cd "../data/stata"
            }
        }
    }
}

cap mkdir "../../results"
cap mkdir "../results"
cap mkdir "results"
log using "../../results/data_audit_and_eda_log.txt", replace text


di _newline "========================================================================"
di "PART 1: DATASET INVENTORY & OBSERVED ROW COUNTS"
di "========================================================================"

foreach dta in panel_hs84_hs85_full_universe panel_hs84_hs85_balanced_with_zeros ///
               panel_dose_response_full baseline_china_share_2022 {
    cap confirm file "`dta'.dta"
    if _rc == 0 {
        use "`dta'.dta", clear
        qui count
        di as txt "Dataset: " as res "`dta'.dta" _col(45) as txt "Obs: " as res %7.0f r(N) _col(60) as txt "Vars: " as res %3.0f c(k)
    }
}

di _newline "========================================================================"
di "PART 2: PRIMARY 133-HEADING FULL UNIVERSE PANEL INTEGRITY (N=25,624)"
di "========================================================================"
use "panel_hs84_hs85_full_universe.dta", clear

* 2.1 Duplicate Check on Primary Key
duplicates report partner_iso sector period
assert r(unique_value) == _N
di as txt "Primary key uniqueness confirmed: zero duplicate observations on (partner_iso, sector, period)."

* 2.2 Missing Values Check
misstable summarize

* 2.3 Non-Negativity & Boundedness Properties
assert trade_value_m_usd >= 0
assert net_mass_mt >= 0 if !missing(net_mass_mt)
assert china_share_2022 >= 0 & china_share_2022 <= 1
assert post == 0 | post == 1
di as txt "Non-negativity and boundedness properties verified."

* 2.4 Temporal Continuity: 36 Consecutive Months (202301 to 202512)
qui levelsof period, local(m_list)
local n_months : word count `m_list'
assert `n_months' == 36

qui count if partner_iso == "VNM" & sector == "8471" & post == 0
local n_pre = r(N)
assert `n_pre' == 27

qui count if partner_iso == "VNM" & sector == "8471" & post == 1
local n_post = r(N)
assert `n_post' == 9

di as txt "Temporal structure: 36 unique months (27 pre-treatment, 9 post-treatment)."
tab period, sort
tabstat trade_value_m_usd net_mass_mt, by(period) statistics(n sum mean) format(%14.2f)

* 2.5 Cross-Sectional Distribution: 6 Partners and 133 Headings
qui levelsof partner_iso, local(p_list)
local n_partners : word count `p_list'
assert `n_partners' == 6

qui levelsof sector, local(s_list)
local n_sectors : word count `s_list'
assert `n_sectors' == 133

di as txt "Cross-sectional structure: 6 partner economies and 133 manufacturing headings."
tab partner_iso, sort
tab sector, sort

* 2.6 Exposure Measure Correlation (2022 vs 2024 Baseline Shares across 133 Headings)
cap confirm variable china_share_2024
if _rc == 0 {
    preserve
        duplicates drop sector, force
        di _newline as txt "Correlation between China Exposure Measures (N = " as res _N as txt " headings):"
        correlate china_share_2022 china_share_2024
    restore
    summarize trade_value_m_usd net_mass_mt china_share_2022 china_share_2024 post, detail
}
else {
    summarize trade_value_m_usd net_mass_mt china_share_2022 post, detail
}

* 2.8 Pre- vs Post-Treatment Distributional Shifts (Full Universe)
di _newline "========================================================================"
di "PART 4: FULL UNIVERSE PRE- VS POST-TREATMENT DISTRIBUTIONAL SHIFTS"
di "========================================================================"
tabstat trade_value_m_usd net_mass_mt, by(post) ///
    statistics(n mean sd min p25 p50 p75 max) columns(statistics) format(%12.2f)

* 2.9 Partner-Level Trade Totals
di _newline "========================================================================"
di "PART 5: FULL UNIVERSE COUNTRY-LEVEL TRADE TOTALS (RANKED BY VOLUME)"
di "========================================================================"
tabstat trade_value_m_usd, by(partner_iso) ///
    statistics(n mean sum p50) format(%12.2f)

* 2.10 Sector-Level Trade Totals & Baseline China Exposure
di _newline "========================================================================"
di "PART 6: 133-HEADING TRADE TOTALS & BASELINE CHINA EXPOSURE"
di "========================================================================"
tabstat trade_value_m_usd china_share_2022, by(sector) ///
    statistics(n mean sum p50) format(%12.2f)


di _newline "========================================================================"
di "PART 7: SECONDARY 20-SECTOR PANEL AUDIT (N=7,877)"
di "========================================================================"
use "panel_dose_response_full.dta", clear

* Duplicate Check on 20-sector panel
duplicates report partner_iso sector period
assert r(unique_value) == _N

* Check theoretical grid (7,920 potential cells vs 7,877 recorded cells; 43 unrecorded zero-trade cells).
preserve
    fillin partner_iso sector period
    qui count if _fillin == 1
    local n_empty = r(N)
    assert `n_empty' == 43
    di as txt "Grid check: 43 unobserved zero-trade cells in 7,920 theoretical grid."
restore

* 20-sector Descriptive Statistics
summarize trade_value_m_usd net_mass_mt china_share treated post treat_post treat_dose_post, detail

log close
cap cd "`start_dir'"
di _newline "========================================================================"
di "DATA AUDIT COMPLETE. RESULTS RECORDED IN:"
di "  replication_package/results/data_audit_and_eda_log.txt"
di "========================================================================"
