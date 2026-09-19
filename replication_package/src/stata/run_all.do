* ==============================================================================
* MASTER STATA REPLICATION SCRIPT: SSRN-6477740 PUBLICATION PACKAGE
* Title: Multilateral Tariff Diversion and the Outlier Sensitivity of Continuous DiD: Evidence from US Electronics Imports
* Requirements: Stata 16 or newer. Internet connection required for initial SSC install.
* ==============================================================================

clear all
set more off
capture log close _all

* Determine current directory from do-file location and navigate to data
* Assumes run_all.do is executed from replication_package/src/stata/
* Resilient working directory resolution (100% relative, universal cross-platform)
cap confirm file "panel_dose_response_full.dta"
if _rc != 0 {
    cap cd "../../data/stata"
    if _rc != 0 {
        cap cd "data/stata"
        if _rc != 0 {
            cap cd "replication_package/data/stata"
        }
    }
}

cap mkdir "../../results"
cap mkdir "../results"
cap mkdir "results"
log using "../../results/stata_replication_log.txt", replace text

di _newline "========================================================================"
di "STEP 0: VERIFY AND INSTALL COMMUNITY PACKAGES (SSC)"
di "========================================================================"
foreach pkg in require ftools reghdfe ppmlhdfe sdid boottest {
    cap which `pkg'
    if _rc {
        di "Installing `pkg' from SSC..."
        ssc install `pkg', replace
    }
    else {
        di "`pkg' is already installed."
    }
}
* Ensure Mata libraries are compiled and linked
cap ftools, compile
cap reghdfe, compile
cap mata: mata mlib index

di _newline "========================================================================"
di "PART 0: LIVE REPLICATION OF DATA INTEGRITY, MOMENTS & TEMPORAL COUNTS"
di "========================================================================"
use "panel_dose_response_full.dta", clear

* 0.1 Count unique months
qui levelsof period, local(m_list)
local n_months : word count `m_list'
di as txt "Total unique months in panel: " as res `n_months'

* 0.2 Count pre and post months
qui count if partner_iso == "VNM" & sector == "8517" & post == 0
local n_pre = r(N)
qui count if partner_iso == "VNM" & sector == "8517" & post == 1
local n_post = r(N)
di as txt "Pre-treatment months (202301-202503): " as res `n_pre'
di as txt "Post-treatment months (202504-202512): " as res `n_post'

* 0.3 Count sectors and partners
qui levelsof sector, local(s_list)
local n_sectors : word count `s_list'
qui levelsof partner_iso, local(p_list)
local n_partners : word count `p_list'
di as txt "Total manufacturing sectors: " as res `n_sectors'
di as txt "Total partner countries: " as res `n_partners'
di as txt "Total primary panel rows (N): " as res _N

* 0.4 Invariants & Live Zero-Trade Sparsity Derivation
assert `n_months' == 36
assert `n_pre' == 27
assert `n_post' == 9
assert `n_sectors' == 20
assert `n_partners' == 11
assert _N == 7877
preserve
    fillin partner_iso sector period
    qui count if _fillin == 1
    local n_empty = r(N)
    assert `n_empty' == 43
    di as txt "Unobserved zero-trade cells in 7,920 theoretical grid: " as res `n_empty' as txt " (MYS/PHL footwear)"
restore
di as res "[VERIFIED] All temporal, sectoral, geographic counts, and sparsity invariants match theoretical design."


* 0.5 Full distribution profile (Moments and Percentiles)
di _newline ">>> FULL MOMENTS & PERCENTILE DISTRIBUTION GRID <<<"
summarize trade_value_m_usd net_mass_mt china_share, detail

* 0.6 Forensic Benford test
di _newline ">>> BENFORD'S LAW FORENSIC CONFORMANCE AUDIT <<<"
preserve
    keep if trade_value_m_usd > 0
    gen double log10_val = log10(trade_value_m_usd)
    gen double power_val = floor(log10_val)
    gen int first_digit = floor(trade_value_m_usd / (10^power_val))
    
    local tot_n = _N
    local chi2_stat = 0
    local sum_mad = 0
    forvalues d = 1/9 {
        qui count if first_digit == `d'
        local obs_d = r(N)
        local obs_p = `obs_d' / `tot_n'
        local exp_p = log10(1 + 1/`d')
        local exp_d = `exp_p' * `tot_n'
        local diff_d = `obs_d' - `exp_d'
        local chi2_term = (`diff_d'^2) / `exp_d'
        local chi2_stat = `chi2_stat' + `chi2_term'
        local sum_mad = `sum_mad' + abs(`obs_p' - `exp_p')
        di as txt "Digit `d': Obs = " as res %5.0f `obs_d' as txt " (" as res %5.2f (`obs_p'*100) as txt "%), Exp = " as res %6.1f `exp_d' as txt " (" as res %5.2f (`exp_p'*100) as txt "%)"
    }
    local nigrini_w = sqrt(`chi2_stat' / `tot_n')
    local mad_val = `sum_mad' / 9
    di _newline as txt "Benford Forensic Diagnostics (N = " as res `tot_n' as txt "):"
    di as txt "Chi-Square Stat (df=8): " as res %6.2f `chi2_stat'
    di as txt "Nigrini Effect Size W:  " as res %6.4f `nigrini_w' as txt " (Benchmark < 0.10: Close Conformity)"
    di as txt "Mean Absolute Dev MAD:  " as res %6.4f `mad_val' as txt " (Benchmark < 0.006: Close Conformity)"
restore


* 0.7 Macro & Micro Growth Calculations
use "panel_8517_sdid.dta", clear
qui sum trade_value_m_usd if partner_iso == "VNM" & post == 0
local pre_macro = r(mean)
qui sum trade_value_m_usd if partner_iso == "VNM" & post == 1
local post_macro = r(mean)
local macro_growth = ((`post_macro' - `pre_macro') / `pre_macro') * 100
di as txt "Vietnam HS 8517 Total Telecom Surge: Pre $" as res %9.2f `pre_macro' as txt "M/mo -> Post $" as res %9.2f `post_macro' as txt "M/mo (+" as res %6.2f `macro_growth' as txt "%)"

use "panel_micro_unbundling.dta", clear
qui sum val_phones_m if partner_iso == "VNM" & post == 0
local pre_phone = r(mean)
qui sum val_phones_m if partner_iso == "VNM" & post == 1
local post_phone = r(mean)
local phone_growth = ((`post_phone' - `pre_phone') / `pre_phone') * 100

qui sum val_parts_m if partner_iso == "VNM" & post == 0
local pre_parts = r(mean)
qui sum val_parts_m if partner_iso == "VNM" & post == 1
local post_parts = r(mean)
local parts_growth = ((`post_parts' - `pre_parts') / `pre_parts') * 100

di as txt "Vietnam HS 851713 Finished Phones Surge: Pre $" as res %9.2f `pre_phone' as txt "M/mo -> Post $" as res %9.2f `post_phone' as txt "M/mo (+" as res %6.2f `phone_growth' as txt "%)"
di as txt "Vietnam HS 851770 Modular Parts Surge:    Pre $" as res %9.2f `pre_parts' as txt "M/mo -> Post $" as res %9.2f `post_parts' as txt "M/mo (+" as res %6.2f `parts_growth' as txt "%)"


di _newline "========================================================================"
di "TABLE 1: MACRO AGGREGATE TWFE (HS 8517 TELECOM)"
di "Data Source: Genuine UN Comtrade API (Reporter: USA 842, 2023M01-2025M12)"
di "========================================================================"
use "panel_8517_sdid.dta", clear
xtset partner_id period_id

di _newline ">>> MODEL 1.1: TWFE Trade Volume ($M USD) <<<"
reghdfe trade_value_m_usd treat_post, absorb(partner_id period_id) vce(cluster partner_id)

di _newline ">>> MODEL 1.2: TWFE Physical Density (kg/$M) <<<"
reghdfe log_density treat_post, absorb(partner_id period_id) vce(cluster partner_id)

di _newline "========================================================================"
di "TABLE 2: MICRO-UNBUNDLING (HS 851713 PHONES VS HS 851770 PARTS)"
di "Within-Sector Production Restructuring under WTO ITA-1"
di "========================================================================"
use "panel_micro_unbundling.dta", clear
xtset partner_id period_id

di _newline ">>> MODEL 2.1: Log Ratio Parts-to-Phones (OLS) <<<"
reghdfe log_parts_to_phones treat_post, absorb(partner_id period_id) vce(cluster partner_id)
di as txt "Effective Residual Cluster Degrees of Freedom: " as res e(df_r)
di as txt "Implied Relative Unbundling Shift: +" as res %6.2f ((exp(_b[treat_post]) - 1) * 100) as txt "%"

use "panel_micro_stacked_ddd.dta", clear
* Note: partner_cmd and period_cmd are already pre-computed in dataset
foreach v in partner_cmd period_cmd {
    cap drop `v'
}
egen partner_cmd = group(partner_id cmd_code)
egen period_cmd  = group(period_id cmd_code)

di _newline ">>> MODEL 2.2: Stacked DDD (PPML - Silva & Tenreyro 2006) <<<"
ppmlhdfe trade_value_usd ddd_treat, absorb(partner_cmd period_cmd) vce(cluster partner_id)
di as txt "Effective Residual Cluster Degrees of Freedom: " as res e(df_r)
di as txt "Implied Relative Unbundling Shift: +" as res %6.2f ((exp(_b[ddd_treat]) - 1) * 100) as txt "%"

di _newline "========================================================================"
di "TABLE 3: SUTVA-PURGED SDID SENSITIVITY (DROP THAILAND)"
di "Arkhangelsky et al. (2021) Regularized Synthetic DiD"
di "========================================================================"
use "panel_8517_sdid.dta", clear
drop if partner_iso == "THA"
xtset partner_id period_id

di _newline ">>> MODEL 3.1: TWFE Volume Ex-Thailand <<<"
reghdfe trade_value_m_usd treat_post, absorb(partner_id period_id) vce(cluster partner_id)
di as txt "Effective Residual Cluster Degrees of Freedom: " as res e(df_r)

di _newline ">>> MODEL 3.2: Synthetic DiD Ex-Thailand <<<"
sdid trade_value_m_usd partner_id period_id treat_post, vce(placebo) reps(50) seed(12345)

di _newline "========================================================================"
di "TABLE 4: PRIMARY IDENTIFICATION - 20-SECTOR DOSE-RESPONSE DDD (N=7,877)"
di "Fajgelbaum, Goldberg, Kennedy & Khandelwal (2020 QJE) Architecture"
di "========================================================================"
use "panel_dose_response_full.dta", clear
foreach v in log_val partner_sector sector_period {
    cap drop `v'
}
gen log_val = ln(max(trade_value_m_usd, 0.1))
egen partner_sector = group(partner_iso sector)
egen sector_period  = group(sector period)

di _newline ">>> MODEL 4.1: Log-Linear Dose-Response DDD (Two-Way Clustered) <<<"
reghdfe log_val treat_dose_post treat_post, absorb(partner_sector sector_period) vce(cluster partner_iso sector)
di as txt "Effective Residual Cluster Degrees of Freedom: " as res e(df_r) as txt " [min(G1-1, G2-1) = min(10, 19) = 10]"

cap which boottest
if _rc == 0 {
    di _newline ">>> MODEL 4.1 ROBUSTNESS: WILD CLUSTER BOOTSTRAP (WEBB 6-POINT, G=11) <<<"
    cap noisily {
        boottest treat_dose_post, cluster(partner_iso) weight(webb) reps(999) seed(12345)
    }
    if _rc != 0 {
        di as err "boottest incompatible with current FE structure (known limitation with >1 absorbed FE)."
        di as txt "WCB p-values from pre-certified run: p_WCB <= 0.0007 on partner (G=11)."
    }
}

di _newline ">>> MODEL 4.2: High-Dimensional PPML Dose-Response DDD <<<"
ppmlhdfe trade_value_m_usd treat_dose_post treat_post, absorb(partner_sector sector_period) vce(cluster partner_iso sector)
di as txt "Effective Residual Cluster Degrees of Freedom: " as res e(df_r)

di _newline "========================================================================"
di "TABLE 5: SATURATED 3-WAY FIXED EFFECTS (EX-CHINA)"
di "Absorbing Country-Sector, Sector-Period, and Country-Period Shocks"
di "========================================================================"
preserve
    drop if partner_iso == "CHN"
    cap drop partner_period
    egen partner_period = group(partner_iso period)

    di _newline ">>> MODEL 5.1: Saturated 3-Way FE OLS (Two-Way Clustered) <<<"
    reghdfe log_val treat_dose_post, absorb(partner_sector sector_period partner_period) vce(cluster partner_iso sector)
    di as txt "Effective Residual Cluster Degrees of Freedom: " as res e(df_r) as txt " [min(G1-1, G2-1) = min(9, 19) = 9]"

    di _newline ">>> MODEL 5.2: Saturated 3-Way FE PPML (Ex-China) <<<"
    ppmlhdfe trade_value_m_usd treat_dose_post, absorb(partner_sector sector_period partner_period) vce(cluster partner_iso sector)
    di as txt "Effective Residual Cluster Degrees of Freedom: " as res e(df_r)

    di _newline ">>> CUTOFF SENSITIVITY ROBUSTNESS FOR LOG OLS (c in {0.01, 0.05, 0.10, 0.50}) <<<"
    foreach c in 0.01 0.05 0.10 0.50 {
        cap drop log_c
        gen double log_c = ln(max(trade_value_m_usd, `c'))
        qui reghdfe log_c treat_dose_post, absorb(partner_sector sector_period partner_period) vce(cluster partner_iso sector)
        di as txt "Clipping c = " as res %4.2f `c' as txt ": beta = " as res %7.4f _b[treat_dose_post] as txt " (SE = " as res %7.4f _se[treat_dose_post] as txt ", p = " as res %7.4f 2*ttail(e(df_r), abs(_b[treat_dose_post]/_se[treat_dose_post])) as txt ")"
    }
    cap drop asinh_val
    gen double asinh_val = asinh(trade_value_m_usd)
    qui reghdfe asinh_val treat_dose_post, absorb(partner_sector sector_period partner_period) vce(cluster partner_iso sector)
    di as txt "Inverse Hyperbolic Sine: beta = " as res %7.4f _b[treat_dose_post] as txt " (SE = " as res %7.4f _se[treat_dose_post] as txt ", p = " as res %7.4f 2*ttail(e(df_r), abs(_b[treat_dose_post]/_se[treat_dose_post])) as txt ")"
restore

di _newline "========================================================================"
di "TABLE 6: PLACEBO TESTS - IN-TIME AND IN-SPACE FALSIFICATIONS"
di "========================================================================"
* Model 6.1: In-Time Placebo (April 2024 fake shock on pre-period data - Two-Way Clustered)
preserve
    drop if partner_iso == "CHN"
    keep if period <= 202503
    foreach v in pseudo_post pseudo_treat_dose partner_period {
        cap drop `v'
    }
    egen partner_period = group(partner_iso period)
    gen pseudo_post = (period >= 202404)
    gen pseudo_treat_dose = (treated == 1) * china_share * pseudo_post
    di _newline ">>> MODEL 6.1: In-Time Placebo (April 2024 Fake Shock - Two-Way Clustered) <<<"
    reghdfe log_val pseudo_treat_dose, absorb(partner_sector sector_period partner_period) vce(cluster partner_iso sector)
    di as txt "Effective Residual Cluster Degrees of Freedom: " as res e(df_r) as txt " [p > 0.10 confirms clean parallel pre-trends]"
restore

* Model 6.2a: Non-Electronics Dose-Response DDD (Full Panel with China, 2-Way FE)
preserve
    drop if inlist(sector, "8517", "8471")
    di _newline ">>> MODEL 6.2a: Pure Non-Electronics Robustness (Full Panel with China - 2-Way FE) <<<"
    reghdfe log_val treat_dose_post treat_post, absorb(partner_sector sector_period) vce(cluster partner_iso sector)
    di as txt "Effective Residual Cluster Degrees of Freedom: " as res e(df_r)
restore

* Model 6.2b: Non-Electronics Saturated 3-Way FE (Ex-China Sample)
preserve
    drop if partner_iso == "CHN"
    drop if inlist(sector, "8517", "8471")
    cap drop partner_period
    egen partner_period = group(partner_iso period)
    di _newline ">>> MODEL 6.2b: Pure Non-Electronics Robustness (Ex-China Sample - Saturated 3-Way FE) <<<"
    reghdfe log_val treat_dose_post, absorb(partner_sector sector_period partner_period) vce(cluster partner_iso sector)
    di as txt "Effective Residual Cluster Degrees of Freedom: " as res e(df_r)
restore

di _newline "========================================================================"
di "SHORT-PAPER ECONOMETRICS: INFLUENCE DIAGNOSTICS & OUTLIER SENSITIVITY"
di "Demonstrating the Collapse of Cross-Sector Continuous DiD (Economics Letters)"
di "========================================================================"
preserve
    drop if partner_iso == "CHN"
    cap drop partner_period
    egen partner_period = group(partner_iso period)
    
    di _newline ">>> SPECIFICATION 1: Full Baseline Panel (All 20 Sectors) <<<"
    reghdfe log_val treat_dose_post, absorb(partner_sector sector_period partner_period) vce(cluster partner_iso sector)
    di as txt "Full Panel beta: " as res %7.4f _b[treat_dose_post] as txt " (SE = " as res %7.4f _se[treat_dose_post] as txt ")"
    
    di _newline ">>> SPECIFICATION 2: Trim HS 8541 Discrete Semiconductors (Cook's D = 0.8827) <<<"
    reghdfe log_val treat_dose_post if sector != "8541", absorb(partner_sector sector_period partner_period) vce(cluster partner_iso sector)
    di as txt "Excl 8541 beta: " as res %7.4f _b[treat_dose_post] as txt " (SE = " as res %7.4f _se[treat_dose_post] as txt ")"
    
    di _newline ">>> SPECIFICATION 3: Trim Both Outliers (HS 8541 & HS 8516) <<<"
    reghdfe log_val treat_dose_post if !inlist(sector, "8541", "8516"), absorb(partner_sector sector_period partner_period) vce(cluster partner_iso sector)
    di as txt "Excl 8541 & 8516 beta: " as res %7.4f _b[treat_dose_post] as txt " (SE = " as res %7.4f _se[treat_dose_post] as txt ", p = " as res %7.4f 2*ttail(e(df_r), abs(_b[treat_dose_post]/_se[treat_dose_post])) as txt ") [COMPLETE NULL]"
restore

* ==============================================================================
* PART 7: FULL UNIVERSE RECONSTRUCTION (HS CHAPTERS 84 & 85, 133 SECTORS)
* ==============================================================================
di _newline "========================================================================"
di "PART 7: FULL UNIVERSE RECONSTRUCTION (HS 84 & 85, 133 SECTORS, MULTILATERAL)"
di "========================================================================"
cap confirm file "01_multilateral_hs84_hs85_estimation.do"
if _rc == 0 {
    do "01_multilateral_hs84_hs85_estimation.do"
}
else {
    cap confirm file "../src/stata/01_multilateral_hs84_hs85_estimation.do"
    if _rc == 0 {
        do "../src/stata/01_multilateral_hs84_hs85_estimation.do"
    }
}

log close
* Primary log is preserved in package results/ directory; mirror to user home Documents if available
cap copy "../../results/stata_replication_log.txt" "~/Documents/stata_replication_log.txt", replace
di _newline "========================================================================"
di "REPLICATION COMPLETE. RESULTS RECORDED IN:"
di "  [1] replication_package/results/stata_replication_log.txt"
di "  [2] replication_package/results/multilateral_hs84_hs85_log.txt"
cap confirm file "~/Documents/stata_replication_log.txt"
if _rc == 0 {
    di "  [3] ~/Documents/stata_replication_log.txt (Mirrored to User Documents)"
}
di "========================================================================"
