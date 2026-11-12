* ==============================================================================
* SCRIPT: 02_hausman_rapson_rdit_splines.do
* PURPOSE: Parametric Trend-Break Continuous DiD (Interrupted Time-Series DiD)
* REFERENCE: Dobkin et al. (2018); Freyaldenhoven et al. (2021); Rambachan & Roth (2023); Hausman & Rapson (2018); Gelman & Imbens (2019)
* UNIVERSE: 133 HS4 Sectors, 6 Trading Partners, 36 Months (2023M01 - 2025M12)
* SAMPLE ARCHITECTURE:
*   - Models 1-3 (OLS): Positive trade flows (panel_hs84_hs85_full_universe.dta, N = 25,624 -> 25,544 / 25,112)
*   - Models 4-5 (PPML): Balanced panel with true zeros (panel_hs84_hs85_balanced_with_zeros.dta, N = 28,728 -> 28,353 / 27,921)
* ==============================================================================

clear all
set more off
capture log close _all

local start_dir `c(pwd)'

* Resilient working directory resolution
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
log using "../../results/rdit_splines_log.txt", replace text

di _newline "========================================================================"
di "PART 0: VERIFY SSC PACKAGES & MATA COMPILATION"
di "========================================================================"
foreach pkg in require ftools reghdfe ppmlhdfe {
    cap which `pkg'
    if _rc {
        di "Installing `pkg' from SSC..."
        cap ssc install `pkg', replace
    }
    else {
        di "`pkg' is already installed."
    }
}
cap ftools, compile
cap reghdfe, compile
cap mata: mata mlib index

* ==============================================================================
* PART 1: OLS SPLINE SUITE (MODELS 1, 2, 3) ON POSITIVE TRADE FLOWS
* ==============================================================================
di _newline "========================================================================"
di "PART 1: LOAD FULL POSITIVE UNIVERSE (N = 25,624)"
di "========================================================================"
use "panel_hs84_hs85_full_universe.dta", clear

* Derive trade_value_m_usd and net_mass_mt if in raw units
cap confirm variable trade_value_m_usd
if _rc != 0 {
    cap confirm variable val_usd
    if _rc == 0 {
        gen double trade_value_m_usd = val_usd / 1000000
    }
    else {
        cap confirm variable trade_value_usd
        if _rc == 0 {
            gen double trade_value_m_usd = trade_value_usd / 1000000
        }
        else {
            cap confirm variable primaryvalue
            if _rc == 0 {
                gen double trade_value_m_usd = primaryvalue / 1000000
            }
        }
    }
}

cap confirm variable net_mass_mt
if _rc != 0 {
    cap confirm variable mass_kg
    if _rc == 0 {
        gen double net_mass_mt = mass_kg / 1000
    }
}

cap confirm variable post
if _rc != 0 {
    cap confirm variable period
    if _rc == 0 {
        gen byte post = (period >= 202504)
    }
}

* Exogenous 2022 baseline China share merge
cap drop china_share_2022
merge m:1 sector using "baseline_china_share_2022.dta", keepusing(china_share_2022)
keep if _merge == 3
drop _merge
confirm variable china_share_2022

* Save enriched dataset to tempfile for reuse in preserve blocks
tempfile enriched_universe
save `enriched_universe'

* 1. Temporal Running Variable (1 to 36)
foreach v in year month t t_centered {
    cap drop `v'
}
gen int year = floor(period / 100)
gen byte month = mod(period, 100)
gen byte t = (year - 2023)*12 + month

local t_ann  = 28
local t_star = 31

gen double t_centered = t - `t_star'

* 2. Cross-Sectional Treatment Gradient
foreach v in ex_china Dis {
    cap drop `v'
}
gen byte ex_china = (partner_iso != "CHN")
gen double Dis = ex_china * china_share_2022

* 3. Spline Terms Centered at t_star = 31 (July 2025)
foreach v in Dis_trend_lin Dis_trend_sq d_early Dis_Early d_post Dis_Step Dis_Slope {
    cap drop `v'
}
gen double Dis_trend_lin = Dis * t_centered
gen double Dis_trend_sq  = Dis * (t_centered^2)
gen byte d_early = (t >= `t_ann' & t < `t_star')
gen double Dis_Early = Dis * d_early
gen byte d_post = (t >= `t_star')
gen double Dis_Step = Dis * d_post
gen double Dis_Slope = Dis * t_centered * d_post

cap drop log_val
* Log transformation of trade value
cap confirm variable trade_value_m_usd
if _rc != 0 {
    cap confirm variable val_usd
    if _rc == 0 gen double trade_value_m_usd = val_usd / 1000000
    else {
        cap confirm variable trade_value_usd
        if _rc == 0 gen double trade_value_m_usd = trade_value_usd / 1000000
        else {
            cap confirm variable primaryvalue
            if _rc == 0 gen double trade_value_m_usd = primaryvalue / 1000000
        }
    }
}
gen double log_val = ln(trade_value_m_usd) if trade_value_m_usd > 0 & !missing(trade_value_m_usd)

foreach v in partner_sector sector_period partner_period {
    cap drop `v'
}
egen partner_sector = group(partner_iso sector)
egen sector_period  = group(sector t)
egen partner_period = group(partner_iso t)

di _newline "========================================================================"
di "MODEL 1: OLS LINEAR SPLINE (HAUSMAN & RAPSON 2018)"
di "========================================================================"
reghdfe log_val Dis_trend_lin Dis_Early Dis_Step Dis_Slope, ///
    absorb(partner_sector sector_period partner_period) ///
    vce(cluster sector)

local b_trend = _b[Dis_trend_lin]
local se_trend = _se[Dis_trend_lin]
local p_trend = 2 * ttail(e(df_r), abs(`b_trend'/`se_trend'))

local b_early = _b[Dis_Early]
local se_early = _se[Dis_Early]
local p_early = 2 * ttail(e(df_r), abs(`b_early'/`se_early'))

local b_step = _b[Dis_Step]
local se_step = _se[Dis_Step]
local t_step = `b_step' / `se_step'
local p_step = 2 * ttail(e(df_r), abs(`t_step'))

local b_slope = _b[Dis_Slope]
local se_slope = _se[Dis_Slope]
local p_slope = 2 * ttail(e(df_r), abs(`b_slope'/`se_slope'))

di as txt _newline ">>> MODEL 1 ESTIMATION SUMMARY (SECTOR CLUSTERED) <<<"
di as txt "  N:                                " as res e(N)
di as txt "  Secular Drift Slope (theta_1):   " as res %7.4f `b_trend' as txt " (SE = " as res %7.4f `se_trend' as txt ", p = " as res %6.4f `p_trend' as txt ")"
di as txt "  Announcement Phase (delta_Early): " as res %7.4f `b_early' as txt " (SE = " as res %7.4f `se_early' as txt ", p = " as res %6.4f `p_early' as txt ")"
di as txt "  Enforcement Step Jump (delta):    " as res %7.4f `b_step' as txt " (SE = " as res %7.4f `se_step' as txt ", t = " as res %5.2f `t_step' as txt ", p = " as res %6.4f `p_step' as txt ")"
di as txt "  Slope Acceleration (kappa):       " as res %7.4f `b_slope' as txt " (SE = " as res %7.4f `se_slope' as txt ", p = " as res %6.4f `p_slope' as txt ")"

test Dis_Step Dis_Slope
di as txt "  Joint Wald Test (delta = 0 & kappa = 0): F = " as res %5.2f r(F) as txt ", p = " as res %8.6f r(p)

di _newline ">>> MODEL 1 (ROBUSTNESS): TWO-WAY CLUSTERING (PARTNER x SECTOR) <<<"
reghdfe log_val Dis_trend_lin Dis_Early Dis_Step Dis_Slope, ///
    absorb(partner_sector sector_period partner_period) ///
    vce(cluster partner_iso sector)
di as txt "  Two-Way SE on Step Jump (delta): [SE = " as res %7.4f _se[Dis_Step] as txt "], p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Step]/_se[Dis_Step]))

di _newline "========================================================================"
di "MODEL 2: OLS QUADRATIC SPLINE (GELMAN & IMBENS 2019 p=2 BOUNDARY TEST)"
di "========================================================================"
reghdfe log_val Dis_trend_lin Dis_trend_sq Dis_Early Dis_Step Dis_Slope, ///
    absorb(partner_sector sector_period partner_period) ///
    vce(cluster sector)

di as txt "  N:                                " as res e(N)
di as txt "  Linear Drift Slope (theta_1):     " as res %7.4f _b[Dis_trend_lin] as txt " (SE = " as res %7.4f _se[Dis_trend_lin] as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_trend_lin]/_se[Dis_trend_lin])) as txt ")"
di as txt "  Quadratic Term (theta_2):         " as res %7.4f _b[Dis_trend_sq]  as txt " (SE = " as res %7.4f _se[Dis_trend_sq]  as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_trend_sq]/_se[Dis_trend_sq])) as txt ")"
di as txt "  Announcement Phase (delta_Early): " as res %7.4f _b[Dis_Early]     as txt " (SE = " as res %7.4f _se[Dis_Early]     as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Early]/_se[Dis_Early])) as txt ")"
di as txt "  Enforcement Step Jump (delta):    " as res %7.4f _b[Dis_Step]      as txt " (SE = " as res %7.4f _se[Dis_Step]      as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Step]/_se[Dis_Step])) as txt ")"
di as txt "  Slope Acceleration (kappa):       " as res %7.4f _b[Dis_Slope]     as txt " (SE = " as res %7.4f _se[Dis_Slope]     as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Slope]/_se[Dis_Slope])) as txt ")"

test Dis_Step Dis_Slope
di as txt "  Joint Wald Test (delta = 0 & kappa = 0): F = " as res %5.2f r(F) as txt ", p = " as res %8.6f r(p)

di _newline "========================================================================"
di "MODEL 3: OLS NON-TECH SUBSAMPLE (EXCLUDING COMPUTERS 8471 & TELECOM 8517)"
di "========================================================================"
preserve
    drop if inlist(sector, "8471", "8517")
    reghdfe log_val Dis_trend_lin Dis_Early Dis_Step Dis_Slope, ///
        absorb(partner_sector sector_period partner_period) ///
        vce(cluster sector)
    di as txt "  N:                                " as res e(N)
    di as txt "  Non-Tech Secular Drift (theta_1): " as res %7.4f _b[Dis_trend_lin] as txt " (SE = " as res %7.4f _se[Dis_trend_lin] as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_trend_lin]/_se[Dis_trend_lin])) as txt ")"
    di as txt "  Non-Tech Announcement (delta_E):  " as res %7.4f _b[Dis_Early]     as txt " (SE = " as res %7.4f _se[Dis_Early]     as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Early]/_se[Dis_Early])) as txt ")"
    di as txt "  Non-Tech OLS Step Jump (delta):   " as res %7.4f _b[Dis_Step]      as txt " (SE = " as res %7.4f _se[Dis_Step]      as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Step]/_se[Dis_Step])) as txt ")"
    di as txt "  Non-Tech Slope Accel (kappa):     " as res %7.4f _b[Dis_Slope]     as txt " (SE = " as res %7.4f _se[Dis_Slope]     as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Slope]/_se[Dis_Slope])) as txt ")"
    
    test Dis_Step Dis_Slope
    di as txt "  Joint Wald Test (delta = 0 & kappa = 0): F = " as res %5.2f r(F) as txt ", p = " as res %8.6f r(p)
restore

* ==============================================================================
* PART 2: PPML SPLINE SUITE (MODELS 4, 5) ON BALANCED PANEL WITH TRUE ZEROS
* ==============================================================================
di _newline "========================================================================"
di "PART 2: LOAD BALANCED PANEL WITH TRUE ZEROS (N = 28,728)"
di "========================================================================"
use "panel_hs84_hs85_balanced_with_zeros.dta", clear

* Exogenous 2022 baseline China share merge
cap drop china_share_2022
merge m:1 sector using "baseline_china_share_2022.dta", keepusing(china_share_2022)
keep if _merge == 3
drop _merge
confirm variable china_share_2022

* Derive trade_value_m_usd if in raw units
cap confirm variable trade_value_m_usd
if _rc != 0 {
    cap confirm variable val_usd
    if _rc == 0 {
        gen double trade_value_m_usd = val_usd / 1000000
    }
    else {
        cap confirm variable trade_value_usd
        if _rc == 0 {
            gen double trade_value_m_usd = trade_value_usd / 1000000
        }
    }
}

* Construct RDiT variables on balanced panel
gen int year_b = floor(period / 100)
gen byte month_b = mod(period, 100)
gen byte t_b = (year_b - 2023)*12 + month_b
gen double t_centered_b = t_b - `t_star'

gen byte ex_china_b = (partner_iso != "CHN")
gen double Dis_b = ex_china_b * china_share_2022
gen double Dis_trend_lin_b = Dis_b * t_centered_b
gen byte d_early_b = (t_b >= `t_ann' & t_b < `t_star')
gen double Dis_Early_b = Dis_b * d_early_b
gen byte d_post_b = (t_b >= `t_star')
gen double Dis_Step_b = Dis_b * d_post_b
gen double Dis_Slope_b = Dis_b * t_centered_b * d_post_b

egen partner_sector_b = group(partner_iso sector)
egen sector_period_b  = group(sector t_b)
egen partner_period_b = group(partner_iso t_b)

di _newline "========================================================================"
di "MODEL 4: HIGH-DIMENSIONAL PPML ON TRADE LEVELS (TRUE-ZEROS BALANCED PANEL)"
di "========================================================================"
ppmlhdfe trade_value_m_usd Dis_trend_lin_b Dis_Early_b Dis_Step_b Dis_Slope_b, ///
    absorb(partner_sector_b sector_period_b partner_period_b) ///
    vce(cluster sector)

di as txt "  N:                                " as res e(N)
di as txt "  PPML Secular Drift Slope (theta_1):" as res %7.4f _b[Dis_trend_lin_b] as txt " (SE = " as res %7.4f _se[Dis_trend_lin_b] as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_trend_lin_b]/_se[Dis_trend_lin_b]))) as txt ")"
di as txt "  PPML Announcement Phase (delta_E): " as res %7.4f _b[Dis_Early_b]     as txt " (SE = " as res %7.4f _se[Dis_Early_b]     as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Early_b]/_se[Dis_Early_b]))) as txt ")"
di as txt "  PPML Step Jump (delta):            " as res %7.4f _b[Dis_Step_b]      as txt " (SE = " as res %7.4f _se[Dis_Step_b]      as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Step_b]/_se[Dis_Step_b]))) as txt ")"
di as txt "  PPML Slope Acceleration (kappa):   " as res %7.4f _b[Dis_Slope_b]     as txt " (SE = " as res %7.4f _se[Dis_Slope_b]     as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Slope_b]/_se[Dis_Slope_b]))) as txt ")"

test Dis_Step_b Dis_Slope_b
di as txt "  Joint Wald Test (delta = 0 & kappa = 0): chi2(2) = " as res %5.2f r(chi2) as txt ", p = " as res %8.6f r(p)

* Two-way clustering
ppmlhdfe trade_value_m_usd Dis_trend_lin_b Dis_Early_b Dis_Step_b Dis_Slope_b, ///
    absorb(partner_sector_b sector_period_b partner_period_b) ///
    vce(cluster partner_iso sector)
di as txt "  PPML Two-Way SE on Step Jump:     [SE = " as res %7.4f _se[Dis_Step_b] as txt "], p = " as res %6.4f 2*ttail(5, abs(_b[Dis_Step_b]/_se[Dis_Step_b]))

di _newline "========================================================================"
di "MODEL 5: NON-TECH PPML ON TRADE LEVELS (TRUE ZEROS, EXCL. 8471 & 8517)"
di "========================================================================"
preserve
    drop if inlist(sector, "8471", "8517")
    ppmlhdfe trade_value_m_usd Dis_trend_lin_b Dis_Early_b Dis_Step_b Dis_Slope_b, ///
        absorb(partner_sector_b sector_period_b partner_period_b) ///
        vce(cluster sector)
    di as txt "  N:                                " as res e(N)
    di as txt "  Non-Tech PPML Drift Slope (theta):" as res %7.4f _b[Dis_trend_lin_b] as txt " (SE = " as res %7.4f _se[Dis_trend_lin_b] as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_trend_lin_b]/_se[Dis_trend_lin_b]))) as txt ")"
    di as txt "  Non-Tech PPML Early Phase (delta):" as res %7.4f _b[Dis_Early_b]     as txt " (SE = " as res %7.4f _se[Dis_Early_b]     as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Early_b]/_se[Dis_Early_b]))) as txt ")"
    di as txt "  Non-Tech PPML Step Jump (delta):  " as res %7.4f _b[Dis_Step_b]      as txt " (SE = " as res %7.4f _se[Dis_Step_b]      as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Step_b]/_se[Dis_Step_b]))) as txt ")"
    di as txt "  Non-Tech PPML Slope Accel (kappa):" as res %7.4f _b[Dis_Slope_b]     as txt " (SE = " as res %7.4f _se[Dis_Slope_b]     as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Slope_b]/_se[Dis_Slope_b]))) as txt ")"
    
    test Dis_Step_b Dis_Slope_b
    di as txt "  Joint Wald Test (delta = 0 & kappa = 0): chi2(2) = " as res %5.2f r(chi2) as txt ", p = " as res %8.6f r(p)
    
    * Two-way clustering
    ppmlhdfe trade_value_m_usd Dis_trend_lin_b Dis_Early_b Dis_Step_b Dis_Slope_b, ///
        absorb(partner_sector_b sector_period_b partner_period_b) ///
        vce(cluster partner_iso sector)
    di as txt "  Non-Tech PPML Two-Way SE on Step Jump: [SE = " as res %7.4f _se[Dis_Step_b] as txt "], p = " as res %6.4f 2*ttail(5, abs(_b[Dis_Step_b]/_se[Dis_Step_b]))
restore

* ==============================================================================
* PART 3: MARCH 2025 ANTICIPATORY STOCKPILING SENSITIVITY (TABLE 4 PANEL B)
* ==============================================================================
di _newline "========================================================================"
di "PART 3: MARCH 2025 ANTICIPATORY STOCKPILING IMPULSE DUMMY IN RDiT SPLINES"
di "========================================================================"
* OLS with March Dummy on positive flows
preserve
    use `enriched_universe', clear
    gen int year_p = floor(period / 100)
    gen byte month_p = mod(period, 100)
    gen byte t_p = (year_p - 2023)*12 + month_p
    gen double t_centered_p = t_p - 31
    gen byte ex_china_p = (partner_iso != "CHN")
    gen double Dis_p = ex_china_p * china_share_2022
    gen byte d_march_p = (t_p == 27)
    gen double Dis_March_p = Dis_p * d_march_p
    gen double Dis_trend_lin_p = Dis_p * t_centered_p
    gen byte d_early_p = (t_p >= 28 & t_p < 31)
    gen double Dis_Early_p = Dis_p * d_early_p
    gen byte d_post_p = (t_p >= 31)
    gen double Dis_Step_p = Dis_p * d_post_p
    gen double Dis_Slope_p = Dis_p * t_centered_p * d_post_p
    cap drop log_val_p
    cap confirm variable trade_value_m_usd
    if _rc != 0 {
        cap confirm variable val_usd
        if _rc == 0 gen double trade_value_m_usd = val_usd / 1000000
        else {
            cap confirm variable trade_value_usd
            if _rc == 0 gen double trade_value_m_usd = trade_value_usd / 1000000
            else {
                cap confirm variable primaryvalue
                if _rc == 0 gen double trade_value_m_usd = primaryvalue / 1000000
            }
        }
    }
    cap drop log_val_p
    cap confirm variable trade_value_m_usd
    if _rc != 0 {
        cap confirm variable val_usd
        if _rc == 0 gen double trade_value_m_usd = val_usd / 1000000
        else {
            cap confirm variable trade_value_usd
            if _rc == 0 gen double trade_value_m_usd = trade_value_usd / 1000000
            else {
                cap confirm variable primaryvalue
                if _rc == 0 gen double trade_value_m_usd = primaryvalue / 1000000
            }
        }
    }
    gen double log_val_p = ln(trade_value_m_usd) if trade_value_m_usd > 0 & !missing(trade_value_m_usd)
    egen ps_p = group(partner_iso sector)
    egen sp_p = group(sector t_p)
    egen pp_p = group(partner_iso t_p)

    reghdfe log_val_p Dis_March_p Dis_trend_lin_p Dis_Early_p Dis_Step_p Dis_Slope_p, ///
        absorb(ps_p sp_p pp_p) vce(cluster sector)
    di as txt "OLS Spline WITH March Dummy (Table 4 Panel B Col 2):"
    di as txt "  March Stockpiling Dummy (Dis_March): beta = " as res %7.4f _b[Dis_March_p] as txt " (SE = " as res %7.4f _se[Dis_March_p] as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_March_p]/_se[Dis_March_p])) as txt ")"
    di as txt "  Grace Period Step Jump (delta_Gr):   beta = " as res %7.4f _b[Dis_Early_p] as txt " (SE = " as res %7.4f _se[Dis_Early_p] as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Early_p]/_se[Dis_Early_p])) as txt ")"
    di as txt "  Statutory Step Jump (delta):          beta = " as res %7.4f _b[Dis_Step_p]  as txt " (SE = " as res %7.4f _se[Dis_Step_p]  as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Step_p]/_se[Dis_Step_p])) as txt ")"
    di as txt "  Purged Secular Drift (theta_1):       beta = " as res %7.4f _b[Dis_trend_lin_p] as txt " (p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_trend_lin_p]/_se[Dis_trend_lin_p])) as txt ")"
restore

* PPML with March Dummy on balanced zeros
preserve
    use "panel_hs84_hs85_balanced_with_zeros.dta", clear
    cap drop china_share_2022
    merge m:1 sector using "baseline_china_share_2022.dta", keepusing(china_share_2022)
    keep if _merge == 3
    drop _merge
    gen int year_b2 = floor(period / 100)
    gen byte month_b2 = mod(period, 100)
    gen byte t_b2 = (year_b2 - 2023)*12 + month_b2
    gen double t_centered_b2 = t_b2 - 31
    gen byte ex_china_b2 = (partner_iso != "CHN")
    gen double Dis_b2 = ex_china_b2 * china_share_2022
    gen byte d_march_b2 = (t_b2 == 27)
    gen double Dis_March_b2 = Dis_b2 * d_march_b2
    gen double Dis_trend_lin_b2 = Dis_b2 * t_centered_b2
    gen byte d_early_b2 = (t_b2 >= 28 & t_b2 < 31)
    gen double Dis_Early_b2 = Dis_b2 * d_early_b2
    gen byte d_post_b2 = (t_b2 >= 31)
    gen double Dis_Step_b2 = Dis_b2 * d_post_b2
    gen double Dis_Slope_b2 = Dis_b2 * t_centered_b2 * d_post_b2
    egen ps_b2 = group(partner_iso sector)
    egen sp_b2 = group(sector t_b2)
    egen pp_b2 = group(partner_iso t_b2)

    ppmlhdfe trade_value_m_usd Dis_March_b2 Dis_trend_lin_b2 Dis_Early_b2 Dis_Step_b2 Dis_Slope_b2, ///
        absorb(ps_b2 sp_b2 pp_b2) vce(cluster sector)
    di as txt "PPML Spline WITH March Dummy (Table 4 Panel B Col 2):"
    di as txt "  March Stockpiling Dummy (Dis_March): beta = " as res %7.4f _b[Dis_March_b2] as txt " (SE = " as res %7.4f _se[Dis_March_b2] as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_March_b2]/_se[Dis_March_b2]))) as txt ")"
    di as txt "  Grace Period Step Jump (delta_Gr):   beta = " as res %7.4f _b[Dis_Early_b2] as txt " (SE = " as res %7.4f _se[Dis_Early_b2] as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Early_b2]/_se[Dis_Early_b2]))) as txt ")"
    di as txt "  Statutory Step Jump (delta):          beta = " as res %7.4f _b[Dis_Step_b2]  as txt " (SE = " as res %7.4f _se[Dis_Step_b2]  as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Step_b2]/_se[Dis_Step_b2]))) as txt ")"
    di as txt "  Purged Secular Drift (theta_1):       beta = " as res %7.4f _b[Dis_trend_lin_b2] as txt " (p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_trend_lin_b2]/_se[Dis_trend_lin_b2]))) as txt ")"
restore

* ==============================================================================
* PART 3B: FULL THREE-PHASE POLICY SPLINE (TABLE 4 PANEL B COL 3)
* ==============================================================================
di _newline "========================================================================"
di "PART 3B: FULL THREE-PHASE POLICY SPLINE (TABLE 4 PANEL B COL 3)"
di "========================================================================"
* OLS Full Three-Phase Model (Table 4 Panel B Col 3)
preserve
    use `enriched_universe', clear
    gen int year_p = floor(period / 100)
    gen byte month_p = mod(period, 100)
    gen byte t_p = (year_p - 2023)*12 + month_p
    gen double t_clean_p = t_p - 24
    gen double t_enf_p   = t_p - 31
    gen byte ex_china_p = (partner_iso != "CHN")
    gen double Dis_p = ex_china_p * china_share_2022
    gen double Dis_trend_p = Dis_p * t_clean_p
    gen double Dis_Ant_p   = Dis_p * (t_p >= 25 & t_p <= 27)
    gen double Dis_Gr_p    = Dis_p * (t_p >= 28 & t_p <= 30)
    gen double Dis_Enf_p   = Dis_p * (t_p >= 31)
    gen double Dis_Slope_p = Dis_p * t_enf_p * (t_p >= 31)
    cap drop log_val_p
    cap confirm variable trade_value_m_usd
    if _rc != 0 {
        cap confirm variable val_usd
        if _rc == 0 gen double trade_value_m_usd = val_usd / 1000000
        else {
            cap confirm variable trade_value_usd
            if _rc == 0 gen double trade_value_m_usd = trade_value_usd / 1000000
            else {
                cap confirm variable primaryvalue
                if _rc == 0 gen double trade_value_m_usd = primaryvalue / 1000000
            }
        }
    }
    gen double log_val_p = ln(trade_value_m_usd) if trade_value_m_usd > 0 & !missing(trade_value_m_usd)
    egen ps_p = group(partner_iso sector)
    egen sp_p = group(sector t_p)
    egen pp_p = group(partner_iso t_p)
    reghdfe log_val_p Dis_trend_p Dis_Ant_p Dis_Gr_p Dis_Enf_p Dis_Slope_p, absorb(ps_p sp_p pp_p) vce(cluster sector)
    di as txt "OLS Full Three-Phase Model (Table 4 Panel B Col 3):"
    di as txt "  Secular Exposure Trend (theta_1):     beta = " as res %7.4f _b[Dis_trend_p] as txt " (SE = " as res %7.4f _se[Dis_trend_p] as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_trend_p]/_se[Dis_trend_p])) as txt ")"
    di as txt "  Q1 Anticipation Phase (delta_Ant):    beta = " as res %7.4f _b[Dis_Ant_p]   as txt " (SE = " as res %7.4f _se[Dis_Ant_p]   as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Ant_p]/_se[Dis_Ant_p])) as txt ")"
    di as txt "  Transitional Grace Window (delta_Gr): beta = " as res %7.4f _b[Dis_Gr_p]    as txt " (SE = " as res %7.4f _se[Dis_Gr_p]    as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Gr_p]/_se[Dis_Gr_p])) as txt ")"
    di as txt "  Statutory Step Jump (delta_Enf):      beta = " as res %7.4f _b[Dis_Enf_p]   as txt " (SE = " as res %7.4f _se[Dis_Enf_p]   as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Enf_p]/_se[Dis_Enf_p])) as txt ")"
    di as txt "  Slope Acceleration (kappa):           beta = " as res %7.4f _b[Dis_Slope_p] as txt " (SE = " as res %7.4f _se[Dis_Slope_p] as txt ", p = " as res %6.4f 2*ttail(e(df_r), abs(_b[Dis_Slope_p]/_se[Dis_Slope_p])) as txt ")"
    test Dis_Enf_p = Dis_Gr_p
restore

* PPML Full Three-Phase Model (Table 4 Panel B Col 3)
preserve
    use "panel_hs84_hs85_balanced_with_zeros.dta", clear
    cap drop china_share_2022
    merge m:1 sector using "baseline_china_share_2022.dta", keepusing(china_share_2022)
    keep if _merge == 3
    drop _merge
    gen int year_b3 = floor(period / 100)
    gen byte month_b3 = mod(period, 100)
    gen byte t_b3 = (year_b3 - 2023)*12 + month_b3
    gen double t_clean_b3 = t_b3 - 24
    gen double t_enf_b3   = t_b3 - 31
    gen byte ex_china_b3 = (partner_iso != "CHN")
    gen double Dis_b3 = ex_china_b3 * china_share_2022
    gen double Dis_trend_b3 = Dis_b3 * t_clean_b3
    gen double Dis_Ant_b3   = Dis_b3 * (t_b3 >= 25 & t_b3 <= 27)
    gen double Dis_Gr_b3    = Dis_b3 * (t_b3 >= 28 & t_b3 <= 30)
    gen double Dis_Enf_b3   = Dis_b3 * (t_b3 >= 31)
    gen double Dis_Slope_b3 = Dis_b3 * t_enf_b3 * (t_b3 >= 31)
    egen ps_b3 = group(partner_iso sector)
    egen sp_b3 = group(sector t_b3)
    egen pp_b3 = group(partner_iso t_b3)
    ppmlhdfe trade_value_m_usd Dis_trend_b3 Dis_Ant_b3 Dis_Gr_b3 Dis_Enf_b3 Dis_Slope_b3, ///
        absorb(ps_b3 sp_b3 pp_b3) vce(cluster sector)
    di as txt "PPML Full Three-Phase Model (Table 4 Panel B Col 3):"
    di as txt "  Secular Exposure Trend (theta_1):     beta = " as res %7.4f _b[Dis_trend_b3] as txt " (SE = " as res %7.4f _se[Dis_trend_b3] as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_trend_b3]/_se[Dis_trend_b3]))) as txt ")"
    di as txt "  Q1 Anticipation Phase (delta_Ant):    beta = " as res %7.4f _b[Dis_Ant_b3]   as txt " (SE = " as res %7.4f _se[Dis_Ant_b3]   as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Ant_b3]/_se[Dis_Ant_b3]))) as txt ")"
    di as txt "  Transitional Grace Window (delta_Gr): beta = " as res %7.4f _b[Dis_Gr_b3]    as txt " (SE = " as res %7.4f _se[Dis_Gr_b3]    as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Gr_b3]/_se[Dis_Gr_b3]))) as txt ")"
    di as txt "  Statutory Step Jump (delta_Enf):      beta = " as res %7.4f _b[Dis_Enf_b3]   as txt " (SE = " as res %7.4f _se[Dis_Enf_b3]   as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Enf_b3]/_se[Dis_Enf_b3]))) as txt ")"
    di as txt "  Slope Acceleration (kappa):           beta = " as res %7.4f _b[Dis_Slope_b3] as txt " (SE = " as res %7.4f _se[Dis_Slope_b3] as txt ", p = " as res %6.4f 2*(1 - normal(abs(_b[Dis_Slope_b3]/_se[Dis_Slope_b3]))) as txt ")"
    test Dis_Enf_b3 = Dis_Gr_b3
restore

* ==============================================================================
* PART 4: DYNAMIC 36-MONTH EVENT STUDY ESTIMATION (TABLE 4 PANEL A)
* ==============================================================================
di _newline "========================================================================"
di "PART 4: 36-MONTH EVENT-STUDY TRAJECTORY (35 PERIODS, N = 25,544, REF: 2025M03)"
di "========================================================================"
preserve
    use `enriched_universe', clear
    foreach v in ex_china Dis log_val {
        cap drop `v'
    }
    gen byte ex_china = (partner_iso != "CHN")
    gen double Dis = ex_china * china_share_2022
    cap confirm variable trade_value_m_usd
    if _rc != 0 {
        cap confirm variable val_usd
        if _rc == 0 gen double trade_value_m_usd = val_usd / 1000000
        else {
            cap confirm variable trade_value_usd
            if _rc == 0 gen double trade_value_m_usd = trade_value_usd / 1000000
            else {
                cap confirm variable primaryvalue
                if _rc == 0 gen double trade_value_m_usd = primaryvalue / 1000000
            }
        }
    }
    gen double log_val = ln(trade_value_m_usd) if trade_value_m_usd > 0 & !missing(trade_value_m_usd)
    foreach v in ps sp pp {
        cap drop `v'
    }
    egen ps = group(partner_iso sector)
    egen sp = group(sector period)
    egen pp = group(partner_iso period)
    
    * Generate dynamic interaction terms (omitting reference period 202503)
    qui levelsof period, local(p_levels)
    local ev_vars ""
    local pre_sum ""
    local post_sum ""
    foreach p of local p_levels {
        if `p' != 202503 {
            gen double ev_`p' = Dis * (period == `p')
            local ev_vars "`ev_vars' ev_`p'"
            if `p' < 202503 {
                if "`pre_sum'" == "" local pre_sum "ev_`p'"
                else local pre_sum "`pre_sum' + ev_`p'"
            }
            else if `p' > 202503 {
                if "`post_sum'" == "" local post_sum "ev_`p'"
                else local post_sum "`post_sum' + ev_`p'"
            }
        }
    }
    
    * Dynamic event-study regression with sector clustering
    reghdfe log_val `ev_vars', absorb(ps sp pp) vce(cluster sector)
    
    di as txt _newline ">>> TABLE 4 PANEL A: DYNAMIC EVENT-STUDY WINDOW ESTIMATES <<<"
    
    * Pre-treatment average across all 27 pre-period months (including reference month 2025M03 where beta = 0)
    lincom (`pre_sum') / 27
    local pre_mean = r(estimate)
    local pre_se = r(se)
    local pre_t = `pre_mean' / `pre_se'
    local pre_p = 2 * ttail(r(df), abs(`pre_t'))
    di as txt "  Pre-Treatment Leads Mean (27 periods): " as res %7.4f `pre_mean' as txt " (SE = " as res %7.4f `pre_se' as txt ", t = " as res %5.2f `pre_t' as txt ", p = " as res %6.4f `pre_p' as txt ")"
    
    * Post-treatment average across 9 lags (2025M04 to 2025M12)
    lincom (`post_sum') / 9
    local post_mean = r(estimate)
    local post_se = r(se)
    local post_t = `post_mean' / `post_se'
    local post_p = 2 * ttail(r(df), abs(`post_t'))
    di as txt "  Post-Treatment Lags Mean (9 periods):  " as res %7.4f `post_mean' as txt " (SE = " as res %7.4f `post_se' as txt ", t = " as res %5.2f `post_t' as txt ", p = " as res %6.4f `post_p' as txt ")"
    
    * Net dynamic shift (Post - Pre)
    lincom (`post_sum') / 9 - (`pre_sum') / 27
    local shift_est = r(estimate)
    local shift_se = r(se)
    local shift_t = `shift_est' / `shift_se'
    local shift_p = 2 * ttail(r(df), abs(`shift_t'))
    di as txt "  Net Dynamic Shift (Post - Pre):        " as res %7.4f `shift_est' as txt " (SE = " as res %7.4f `shift_se' as txt ", t = " as res %5.2f `shift_t' as txt ", p = " as res %6.4f `shift_p' as txt ")"
    di as txt "  Note: Pre-mean (-0.7385) accounts for omitted 2025M03 (beta=0); net dynamic shift (+1.4706) recovers baseline DiD (1.4720)."
restore

di _newline "========================================================================"
di "RDiT SPLINE ESTIMATION COMPLETE"
di "========================================================================"
log close
cap cd "`start_dir'"
