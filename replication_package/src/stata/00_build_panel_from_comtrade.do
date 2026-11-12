* ==============================================================================
* SCRIPT 00: DYNAMIC RAW PANEL CONSTRUCTION FROM UN COMTRADE
* Purpose: Ingest raw UN Comtrade API v1 CSVs, aggregate 2022 baseline China
*          shares across 133 HS4 manufacturing headings, recode Taiwan (490/S19),
*          merge baseline exposure, and construct full positive and balanced panels.
* Inputs:
*   - data/raw/comtrade_usa_ch84_85_baseline_2022.csv
*   - data/raw/comtrade_usa_ch84_85_monthly_2023_2025.csv
* Outputs:
*   - data/stata/baseline_china_share_2022.dta  (N = 133 headings)
*   - data/stata/baseline_china_share_2022.csv  (N = 133 headings)
*   - data/stata/panel_hs84_hs85_full_universe.dta  (N = 25,624 positive flows)
*   - data/stata/panel_hs84_hs85_full_universe.csv  (N = 25,624 positive flows)
*   - data/stata/panel_hs84_hs85_balanced_with_zeros.dta  (N = 28,728 balanced grid)
* Requirements: Stata 16 or newer (BE, SE, or MP)
* ==============================================================================

clear all
macro drop _all
matrix drop _all
scalar drop _all
set more off
capture log close _all

* ------------------------------------------------------------------------------
* STEP 0: RESILIENT WORKING DIRECTORY RESOLUTION (RELATIVE PATHS)
* ------------------------------------------------------------------------------
local start_dir `c(pwd)'
local raw_dir ""
local stata_dir ""

foreach d in "../../data/raw" "replication_package/data/raw" "data/raw" "../raw" "../data/raw" {
    cap confirm file "`d'/comtrade_usa_ch84_85_baseline_2022.csv"
    if _rc == 0 {
        local raw_dir "`d'"
        continue, break
    }
}

foreach d in "../../data/stata" "replication_package/data/stata" "data/stata" "../stata" "../data/stata" {
    cap confirm file "`d'/panel_dose_response_full.dta"
    if _rc == 0 {
        local stata_dir "`d'"
        continue, break
    }
}

if "`raw_dir'" == "" {
    di as err "ERROR: Raw UN Comtrade directory not found."
    exit 601
}
if "`stata_dir'" == "" {
    di as err "ERROR: Data Stata destination directory not found."
    exit 601
}

di as txt "Raw data directory:       `raw_dir'"
di as txt "Stata output directory:   `stata_dir'"

cap mkdir "../../results"
cap mkdir "../results"
cap mkdir "results"
cap log using "../../results/build_panel_from_comtrade_log.txt", replace text

* ------------------------------------------------------------------------------
* STEP 1: INGEST 2022 BASELINE COMTRADE DATA & COMPUTE EXOGENOUS CHINA SHARES
* ------------------------------------------------------------------------------
di _newline "========================================================================"
di "STEP 1: INGESTING 2022 BASELINE COMTRADE DATA & COMPUTING CHINA SHARES"
di "========================================================================"

import delimited using "`raw_dir'/comtrade_usa_ch84_85_baseline_2022.csv", clear case(lower)

* Filter to World (partnercode == 0 | partneriso == "W00") and China (partnercode == 156 | partneriso == "CHN")
cap tostring partnercode, replace
keep if inlist(partneriso, "W00", "CHN") | inlist(partnercode, "0", "156")

* Generate 4-digit HS heading string identifier
cap tostring cmdcode, replace format("%04.0f")
gen str4 sector = string(real(cmdcode), "%04.0f")

* Standardize partner ISO code
gen str3 p_iso = "W00" if inlist(partneriso, "W00") | partnercode == "0"
replace  p_iso = "CHN" if inlist(partneriso, "CHN") | partnercode == "156"

* Aggregate across 12 calendar months to form annual 2022 totals
collapse (sum) val_2022 = primaryvalue, by(sector p_iso)

* Reshape to wide format: sector, val_2022CHN, val_2022W00
reshape wide val_2022, i(sector) j(p_iso) string
rename val_2022CHN china_val_2022
rename val_2022W00 world_val_2022

* Replace missing China values with 0 if heading had zero direct China imports
replace china_val_2022 = 0 if missing(china_val_2022)

* Exogenous baseline China exposure ratio
gen double china_share_2022 = china_val_2022 / world_val_2022
assert !missing(china_share_2022)
assert china_share_2022 >= 0 & china_share_2022 <= 1

* Verify universe completeness: exactly 133 HS4 manufacturing headings
qui count
assert r(N) == 133
di as txt "Baseline China exposure successfully computed for exactly " as res r(N) as txt " headings."

* Save clean baseline reference datasets
save "`stata_dir'/baseline_china_share_2022.dta", replace
export delimited using "`stata_dir'/baseline_china_share_2022.csv", replace
tempfile baseline_shares
save `baseline_shares'

* ------------------------------------------------------------------------------
* STEP 2: INGEST MONTHLY 2023-2025 COMTRADE DATA & ASSEMBLE FULL UNIVERSE PANEL
* ------------------------------------------------------------------------------
di _newline "========================================================================"
di "STEP 2: INGESTING MONTHLY 2023-2025 COMTRADE DATA & RECODING TAIWAN"
di "========================================================================"

import delimited using "`raw_dir'/comtrade_usa_ch84_85_monthly_2023_2025.csv", clear case(lower)

* Recode Taiwan: UN Comtrade API v1 designates Taiwan as partnercode 490 / partneriso S19
cap tostring partnercode, replace
gen str3 partner_iso = partneriso
replace partner_iso = "TWN" if partnercode == "490" | partneriso == "S19" | partneriso == "TWN"

* Retain the 6 core multilateral partner economies
keep if inlist(partner_iso, "CHN", "TWN", "MEX", "VNM", "THA", "IND")

* Format sector identifier and economic metrics
cap tostring cmdcode, replace format("%04.0f")
gen str4 sector = string(real(cmdcode), "%04.0f")
gen double val_usd = primaryvalue
gen double mass_kg = netwgt
gen double trade_value_m_usd = val_usd / 1000000
gen double net_mass_mt = mass_kg / 1000
gen byte post = (period >= 202504)

* Retain necessary variables
keep partner_iso sector period val_usd mass_kg trade_value_m_usd net_mass_mt post

* Merge exogenous 2022 baseline China exposure
merge m:1 sector using `baseline_shares', keepusing(china_share_2022)
assert _merge == 3
drop _merge

* Data integrity and primary key uniqueness checks
duplicates report partner_iso sector period
assert r(unique_value) == _N

* Verify exact full universe positive row count (N = 25,624)
assert _N == 25624
di as txt "Full universe positive-flow panel verified: N = " as res _N as txt " observations."

* Save positive flow universe
save "`stata_dir'/panel_hs84_hs85_full_universe.dta", replace
export delimited using "`stata_dir'/panel_hs84_hs85_full_universe.csv", replace

* ------------------------------------------------------------------------------
* STEP 3: CONSTRUCT BALANCED GRID WITH TRUE ZEROS (N = 28,728)
* ------------------------------------------------------------------------------
di _newline "========================================================================"
di "STEP 3: BALANCED GRID EXPANSION & TRUE ZERO FILLIN (133 x 6 x 36 = 28,728)"
di "========================================================================"

* Expand grid to complete Cartesian product: 133 sectors x 6 partners x 36 months
fillin partner_iso sector period

* Recode imputed zero cells
replace trade_value_m_usd = 0 if _fillin == 1
replace val_usd = 0 if _fillin == 1
replace net_mass_mt = 0 if _fillin == 1
replace mass_kg = 0 if _fillin == 1
replace post = (period >= 202504) if _fillin == 1
drop _fillin

* Re-merge baseline China share for filled cells
drop china_share_2022
merge m:1 sector using `baseline_shares', keepusing(china_share_2022)
assert _merge == 3
drop _merge

* Verify exact balanced panel dimensions: 133 * 6 * 36 = 28,728
assert _N == 28728
di as txt "Balanced grid with true zeros verified: N = " as res _N as txt " observations."

* Save balanced panel
save "`stata_dir'/panel_hs84_hs85_balanced_with_zeros.dta", replace

di _newline "========================================================================"
di "PANEL DATASET CONSTRUCTION COMPLETE. SAVED TO:"
di "  [1] `stata_dir'/baseline_china_share_2022.dta (N = 133)"
di "  [2] `stata_dir'/panel_hs84_hs85_full_universe.dta (N = 25,624)"
di "  [3] `stata_dir'/panel_hs84_hs85_balanced_with_zeros.dta (N = 28,728)"
di "========================================================================"

cap log close
cap cd "`start_dir'"
